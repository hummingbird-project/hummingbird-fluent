//===----------------------------------------------------------------------===//
//
// This source file is part of the Hummingbird server framework project
//
// Copyright (c) 2021-2024 the Hummingbird authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See hummingbird/CONTRIBUTORS.txt for the list of Hummingbird authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import FluentSQLiteDriver
import Hummingbird
import HummingbirdFluent
import HummingbirdTesting
import XCTest

final class PersistTests: XCTestCase {
    func createApplication(_ updateRouter: (Router<BasicRequestContext>, PersistDriver) -> Void = { _, _ in }) async throws -> some ApplicationProtocol {
        var logger = Logger(label: "FluentTests")
        logger.logLevel = .trace
        let fluent = Fluent(logger: logger)
        // add sqlite database
        fluent.databases.use(.sqlite(.memory), as: .sqlite)
        let persist = await FluentPersistDriver(fluent: fluent)
        // run migrations
        try await fluent.migrate()

        let router = Router()

        router.put("/persist/:tag") { request, context -> HTTPResponse.Status in
            let buffer = try await request.body.collect(upTo: .max)
            let tag = try context.parameters.require("tag")
            try await persist.set(key: tag, value: String(buffer: buffer))
            return .ok
        }
        router.put("/persist/:tag/:time") { request, context -> HTTPResponse.Status in
            guard let time = context.parameters.get("time", as: Int.self) else { throw HTTPError(.badRequest) }
            let buffer = try await request.body.collect(upTo: .max)
            let tag = try context.parameters.require("tag")
            try await persist.set(key: tag, value: String(buffer: buffer), expires: .seconds(time))
            return .ok
        }
        router.get("/persist/:tag") { _, context -> String? in
            guard let tag = context.parameters.get("tag", as: String.self) else { throw HTTPError(.badRequest) }
            return try await persist.get(key: tag, as: String.self)
        }
        router.delete("/persist/:tag") { _, context -> HTTPResponse.Status in
            guard let tag = context.parameters.get("tag", as: String.self) else { throw HTTPError(.badRequest) }
            try await persist.remove(key: tag)
            return .noContent
        }
        updateRouter(router, persist)
        var app = Application(responder: router.buildResponder())
        app.addServices(fluent, persist)

        return app
    }

    func testSetGet() async throws {
        let app = try await self.createApplication()
        try await app.test(.live) { client in
            let tag = UUID().uuidString
            try await client.execute(uri: "/persist/\(tag)", method: .put, body: ByteBufferAllocator().buffer(string: "Persist")) { _ in }
            try await client.execute(uri: "/persist/\(tag)", method: .get) { response in
                let body = try XCTUnwrap(response.body)
                XCTAssertEqual(String(buffer: body), "Persist")
            }
        }
    }

    func testCreateGet() async throws {
        let app = try await self.createApplication { router, persist in
            router.put("/create/:tag") { request, context -> HTTPResponse.Status in
                let buffer = try await request.body.collect(upTo: .max)
                let tag = try context.parameters.require("tag")
                try await persist.create(key: tag, value: String(buffer: buffer))
                return .ok
            }
        }
        try await app.test(.live) { client in
            let tag = UUID().uuidString
            try await client.execute(uri: "/create/\(tag)", method: .put, body: ByteBufferAllocator().buffer(string: "Persist")) { _ in }
            try await client.execute(uri: "/persist/\(tag)", method: .get) { response in
                let body = try XCTUnwrap(response.body)
                XCTAssertEqual(String(buffer: body), "Persist")
            }
        }
    }

    func testDoubleCreateFail() async throws {
        let app = try await self.createApplication { router, persist in
            router.put("/create/:tag") { request, context -> HTTPResponse.Status in
                let buffer = try await request.body.collect(upTo: .max)
                let tag = try context.parameters.require("tag")
                do {
                    try await persist.create(key: tag, value: String(buffer: buffer))
                } catch let error as PersistError where error == .duplicate {
                    throw HTTPError(.conflict)
                }
                return .ok
            }
        }
        try await app.test(.live) { client in
            let tag = UUID().uuidString
            try await client.execute(uri: "/create/\(tag)", method: .put, body: ByteBufferAllocator().buffer(string: "Persist")) { response in
                XCTAssertEqual(response.status, .ok)
            }
            try await client.execute(uri: "/create/\(tag)", method: .put, body: ByteBufferAllocator().buffer(string: "Persist")) { response in
                XCTAssertEqual(response.status, .conflict)
            }
        }
    }

    func testSetTwice() async throws {
        let app = try await self.createApplication()
        try await app.test(.live) { client in

            let tag = UUID().uuidString
            try await client.execute(uri: "/persist/\(tag)", method: .put, body: ByteBufferAllocator().buffer(string: "test1")) { _ in }
            try await client.execute(uri: "/persist/\(tag)", method: .put, body: ByteBufferAllocator().buffer(string: "test2")) { response in
                XCTAssertEqual(response.status, .ok)
            }
            try await client.execute(uri: "/persist/\(tag)", method: .get) { response in
                let body = try XCTUnwrap(response.body)
                XCTAssertEqual(String(buffer: body), "test2")
            }
        }
    }

    func testExpires() async throws {
        let app = try await self.createApplication()
        try await app.test(.live) { client in

            let tag1 = UUID().uuidString
            let tag2 = UUID().uuidString

            try await client.execute(uri: "/persist/\(tag1)/0", method: .put, body: ByteBufferAllocator().buffer(string: "ThisIsTest1")) { _ in }
            try await client.execute(uri: "/persist/\(tag2)/10", method: .put, body: ByteBufferAllocator().buffer(string: "ThisIsTest2")) { _ in }
            try await Task.sleep(nanoseconds: 1_000_000_000)
            try await client.execute(uri: "/persist/\(tag1)", method: .get) { response in
                XCTAssertEqual(response.status, .noContent)
            }
            try await client.execute(uri: "/persist/\(tag2)", method: .get) { response in
                let body = try XCTUnwrap(response.body)
                XCTAssertEqual(String(buffer: body), "ThisIsTest2")
            }
        }
    }

    func testCodable() async throws {
        struct TestCodable: Codable {
            let buffer: String
        }
        let app = try await self.createApplication { router, persist in
            router.put("/codable/:tag") { request, context -> HTTPResponse.Status in
                guard let tag = context.parameters.get("tag") else { throw HTTPError(.badRequest) }
                let buffer = try await request.body.collect(upTo: .max)
                try await persist.set(key: tag, value: TestCodable(buffer: String(buffer: buffer)))
                return .ok
            }
            router.get("/codable/:tag") { _, context -> String? in
                guard let tag = context.parameters.get("tag") else { throw HTTPError(.badRequest) }
                let value = try await persist.get(key: tag, as: TestCodable.self)
                return value?.buffer
            }
        }
        try await app.test(.live) { client in

            let tag = UUID().uuidString
            try await client.execute(uri: "/codable/\(tag)", method: .put, body: ByteBufferAllocator().buffer(string: "Persist")) { _ in }
            try await client.execute(uri: "/codable/\(tag)", method: .get) { response in
                let body = try XCTUnwrap(response.body)
                XCTAssertEqual(String(buffer: body), "Persist")
            }
        }
    }

    func testRemove() async throws {
        let app = try await self.createApplication()
        try await app.test(.live) { client in
            let tag = UUID().uuidString
            try await client.execute(uri: "/persist/\(tag)", method: .put, body: ByteBufferAllocator().buffer(string: "ThisIsTest1")) { _ in }
            try await client.execute(uri: "/persist/\(tag)", method: .delete) { _ in }
            try await client.execute(uri: "/persist/\(tag)", method: .get) { response in
                XCTAssertEqual(response.status, .noContent)
            }
        }
    }

    func testExpireAndAdd() async throws {
        let app = try await self.createApplication()
        try await app.test(.live) { client in

            let tag = UUID().uuidString
            try await client.execute(uri: "/persist/\(tag)/0", method: .put, body: ByteBufferAllocator().buffer(string: "ThisIsTest1")) { _ in }
            try await Task.sleep(nanoseconds: 1_000_000_000)
            try await client.execute(uri: "/persist/\(tag)", method: .get) { response in
                XCTAssertEqual(response.status, .noContent)
            }
            try await client.execute(uri: "/persist/\(tag)/10", method: .put, body: ByteBufferAllocator().buffer(string: "ThisIsTest1")) { response in
                XCTAssertEqual(response.status, .ok)
            }
            try await client.execute(uri: "/persist/\(tag)", method: .get) { response in
                XCTAssertEqual(response.status, .ok)
                let body = try XCTUnwrap(response.body)
                XCTAssertEqual(String(buffer: body), "ThisIsTest1")
            }
        }
    }
}
