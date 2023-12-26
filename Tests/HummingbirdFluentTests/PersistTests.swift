//===----------------------------------------------------------------------===//
//
// This source file is part of the Hummingbird server framework project
//
// Copyright (c) 2021-2021 the Hummingbird authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See hummingbird/CONTRIBUTORS.txt for the list of Hummingbird authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import FluentSQLiteDriver
// import FluentMySQLDriver
// import FluentPostgresDriver
import Hummingbird
import HummingbirdFluent
import XCTest

final class PersistTests: XCTestCase {
    func createRouter(fluent: HBFluent) async throws -> (HBRouter<some HBRequestContext>, HBPersistDriver) {
        // add sqlite database
        fluent.databases.use(.sqlite(.memory), as: .sqlite)
        // fluent.databases.use(.postgres(hostname: "localhost", username: "postgres", password: "vapor", database: "vapor"), as: .psql)
        let persist = await HBFluentPersistDriver(fluent: fluent)
        // run migrations
        try await fluent.migrate()

        let router = HBRouter()

        router.put("/persist/:tag") { request, context -> HTTPResponse.Status in
            let buffer = try await request.body.collect(upTo: .max)
            let tag = try context.parameters.require("tag")
            try await persist.set(key: tag, value: String(buffer: buffer))
            return .ok
        }
        router.put("/persist/:tag/:time") { request, context -> HTTPResponse.Status in
            guard let time = context.parameters.get("time", as: Int.self) else { throw HBHTTPError(.badRequest) }
            let buffer = try await request.body.collect(upTo: .max)
            let tag = try context.parameters.require("tag")
            try await persist.set(key: tag, value: String(buffer: buffer), expires: .seconds(time))
            return .ok
        }
        router.get("/persist/:tag") { _, context -> String? in
            guard let tag = context.parameters.get("tag", as: String.self) else { throw HBHTTPError(.badRequest) }
            return try await persist.get(key: tag, as: String.self)
        }
        router.delete("/persist/:tag") { _, context -> HTTPResponse.Status in
            guard let tag = context.parameters.get("tag", as: String.self) else { throw HBHTTPError(.badRequest) }
            try await persist.remove(key: tag)
            return .noContent
        }
        return (router, persist)
    }

    func testSetGet() async throws {
        var logger = Logger(label: "FluentTests")
        logger.logLevel = .trace
        let fluent = HBFluent(logger: logger)
        let (router, _) = try await createRouter(fluent: fluent)
        var app = HBApplication(responder: router.buildResponder())
        app.addService(fluent)
        try await app.test(.live) { client in
            let tag = UUID().uuidString
            try await client.XCTExecute(uri: "/persist/\(tag)", method: .put, body: ByteBufferAllocator().buffer(string: "Persist")) { _ in }
            try await client.XCTExecute(uri: "/persist/\(tag)", method: .get) { response in
                let body = try XCTUnwrap(response.body)
                XCTAssertEqual(String(buffer: body), "Persist")
            }
        }
    }

    func testCreateGet() async throws {
        let fluent = HBFluent(logger: Logger(label: "FluentTests"))
        let (router, persist) = try await createRouter(fluent: fluent)

        router.put("/create/:tag") { request, context -> HTTPResponse.Status in
            let buffer = try await request.body.collect(upTo: .max)
            let tag = try context.parameters.require("tag")
            try await persist.create(key: tag, value: String(buffer: buffer))
            return .ok
        }
        var app = HBApplication(responder: router.buildResponder())
        app.addService(fluent)
        try await app.test(.live) { client in
            let tag = UUID().uuidString
            try await client.XCTExecute(uri: "/create/\(tag)", method: .put, body: ByteBufferAllocator().buffer(string: "Persist")) { _ in }
            try await client.XCTExecute(uri: "/persist/\(tag)", method: .get) { response in
                let body = try XCTUnwrap(response.body)
                XCTAssertEqual(String(buffer: body), "Persist")
            }
        }
    }

    func testDoubleCreateFail() async throws {
        let fluent = HBFluent(logger: Logger(label: "FluentTests"))
        let (router, persist) = try await createRouter(fluent: fluent)
        router.put("/create/:tag") { request, context -> HTTPResponse.Status in
            let buffer = try await request.body.collect(upTo: .max)
            let tag = try context.parameters.require("tag")
            do {
                try await persist.create(key: tag, value: String(buffer: buffer))
            } catch let error as HBPersistError where error == .duplicate {
                throw HBHTTPError(.conflict)
            }
            return .ok
        }
        var app = HBApplication(responder: router.buildResponder())
        app.addService(fluent)
        try await app.test(.live) { client in
            let tag = UUID().uuidString
            try await client.XCTExecute(uri: "/create/\(tag)", method: .put, body: ByteBufferAllocator().buffer(string: "Persist")) { response in
                XCTAssertEqual(response.status, .ok)
            }
            try await client.XCTExecute(uri: "/create/\(tag)", method: .put, body: ByteBufferAllocator().buffer(string: "Persist")) { response in
                XCTAssertEqual(response.status, .conflict)
            }
        }
    }

    func testSetTwice() async throws {
        let fluent = HBFluent(logger: Logger(label: "FluentTests"))
        let (router, _) = try await createRouter(fluent: fluent)
        var app = HBApplication(responder: router.buildResponder())
        app.addService(fluent)
        try await app.test(.live) { client in

            let tag = UUID().uuidString
            try await client.XCTExecute(uri: "/persist/\(tag)", method: .put, body: ByteBufferAllocator().buffer(string: "test1")) { _ in }
            try await client.XCTExecute(uri: "/persist/\(tag)", method: .put, body: ByteBufferAllocator().buffer(string: "test2")) { response in
                XCTAssertEqual(response.status, .ok)
            }
            try await client.XCTExecute(uri: "/persist/\(tag)", method: .get) { response in
                let body = try XCTUnwrap(response.body)
                XCTAssertEqual(String(buffer: body), "test2")
            }
        }
    }

    func testExpires() async throws {
        let fluent = HBFluent(logger: Logger(label: "FluentTests"))
        let (router, _) = try await createRouter(fluent: fluent)
        var app = HBApplication(responder: router.buildResponder())
        app.addService(fluent)
        try await app.test(.live) { client in

            let tag1 = UUID().uuidString
            let tag2 = UUID().uuidString

            try await client.XCTExecute(uri: "/persist/\(tag1)/0", method: .put, body: ByteBufferAllocator().buffer(string: "ThisIsTest1")) { _ in }
            try await client.XCTExecute(uri: "/persist/\(tag2)/10", method: .put, body: ByteBufferAllocator().buffer(string: "ThisIsTest2")) { _ in }
            try await Task.sleep(nanoseconds: 1_000_000_000)
            try await client.XCTExecute(uri: "/persist/\(tag1)", method: .get) { response in
                XCTAssertEqual(response.status, .noContent)
            }
            try await client.XCTExecute(uri: "/persist/\(tag2)", method: .get) { response in
                let body = try XCTUnwrap(response.body)
                XCTAssertEqual(String(buffer: body), "ThisIsTest2")
            }
        }
    }

    func testCodable() async throws {
        #if os(macOS)
        // disable macOS tests in CI. GH Actions are currently running this when they shouldn't
        guard HBEnvironment().get("CI") != "true" else { throw XCTSkip() }
        #endif
        struct TestCodable: Codable {
            let buffer: String
        }
        let fluent = HBFluent(logger: Logger(label: "FluentTests"))
        let (router, persist) = try await createRouter(fluent: fluent)
        router.put("/codable/:tag") { request, context -> HTTPResponse.Status in
            guard let tag = context.parameters.get("tag") else { throw HBHTTPError(.badRequest) }
            let buffer = try await request.body.collect(upTo: .max)
            try await persist.set(key: tag, value: TestCodable(buffer: String(buffer: buffer)))
            return .ok
        }
        router.get("/codable/:tag") { _, context -> String? in
            guard let tag = context.parameters.get("tag") else { throw HBHTTPError(.badRequest) }
            let value = try await persist.get(key: tag, as: TestCodable.self)
            return value?.buffer
        }
        var app = HBApplication(responder: router.buildResponder())
        app.addService(fluent)

        try await app.test(.live) { client in
            let tag = UUID().uuidString
            try await client.XCTExecute(uri: "/codable/\(tag)", method: .put, body: ByteBufferAllocator().buffer(string: "Persist")) { _ in }
            try await client.XCTExecute(uri: "/codable/\(tag)", method: .get) { response in
                let body = try XCTUnwrap(response.body)
                XCTAssertEqual(String(buffer: body), "Persist")
            }
        }
    }

    func testRemove() async throws {
        let fluent = HBFluent(logger: Logger(label: "FluentTests"))
        let (router, _) = try await createRouter(fluent: fluent)
        var app = HBApplication(responder: router.buildResponder())
        app.addService(fluent)
        try await app.test(.live) { client in
            let tag = UUID().uuidString
            try await client.XCTExecute(uri: "/persist/\(tag)", method: .put, body: ByteBufferAllocator().buffer(string: "ThisIsTest1")) { _ in }
            try await client.XCTExecute(uri: "/persist/\(tag)", method: .delete) { _ in }
            try await client.XCTExecute(uri: "/persist/\(tag)", method: .get) { response in
                XCTAssertEqual(response.status, .noContent)
            }
        }
    }

    func testExpireAndAdd() async throws {
        let fluent = HBFluent(logger: Logger(label: "FluentTests"))
        let (router, _) = try await createRouter(fluent: fluent)
        var app = HBApplication(responder: router.buildResponder())
        app.addService(fluent)
        try await app.test(.live) { client in
            let tag = UUID().uuidString
            try await client.XCTExecute(uri: "/persist/\(tag)/0", method: .put, body: ByteBufferAllocator().buffer(string: "ThisIsTest1")) { _ in }
            try await Task.sleep(nanoseconds: 1_000_000_000)
            try await client.XCTExecute(uri: "/persist/\(tag)", method: .get) { response in
                XCTAssertEqual(response.status, .noContent)
            }
            try await client.XCTExecute(uri: "/persist/\(tag)/10", method: .put, body: ByteBufferAllocator().buffer(string: "ThisIsTest1")) { response in
                XCTAssertEqual(response.status, .ok)
            }
            try await client.XCTExecute(uri: "/persist/\(tag)", method: .get) { response in
                XCTAssertEqual(response.status, .ok)
                let body = try XCTUnwrap(response.body)
                XCTAssertEqual(String(buffer: body), "ThisIsTest1")
            }
        }
    }
}
