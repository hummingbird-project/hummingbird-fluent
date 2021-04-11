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
import Hummingbird
import HummingbirdFluent
import XCTest

final class PersistTests: XCTestCase {

    func testSetGet() throws {
        let app = HBApplication(testing: .live)
        // add Fluent
        app.addFluent()
        // add sqlite database
        app.fluent.databases.use(.sqlite(.memory), as: .sqlite)
        // add persist
        app.addPersist(using: .fluent)
        // run migrations
        try app.fluent.migrate().wait()

        app.router.put("/") { request -> EventLoopFuture<HTTPResponseStatus> in
            guard let buffer = request.body.buffer else { return request.failure(.badRequest) }
            return request.persist.set(key: "test", value: String(buffer: buffer), on: request.eventLoop).map { _ in .ok }
        }
        app.router.get("/") { request in
            return request.persist.get(key: "test", as: String.self, on: request.eventLoop)
        }
        app.XCTStart()
        defer { app.XCTStop() }

        app.XCTExecute(uri: "/", method: .PUT, body: ByteBufferAllocator().buffer(string: "Persist")) { _ in }
        app.XCTExecute(uri: "/", method: .GET) { response in
            let body = try XCTUnwrap(response.body)
            XCTAssertEqual(String(buffer: body), "Persist")
        }
    }

    func testExpires() throws {
        let app = HBApplication(testing: .live)
        // add Fluent
        app.addFluent()
        // add sqlite database
        app.fluent.databases.use(.sqlite(.memory), as: .sqlite)
        // add persist
        app.addPersist(using: .fluent)
        // run migrations
        try app.fluent.migrate().wait()

        app.router.put("/persist/:tag/:time") { request -> EventLoopFuture<HTTPResponseStatus> in
            guard let time = request.parameters.get("time", as: Int.self) else { return request.failure(.badRequest) }
            guard let tag = request.parameters.get("tag") else { return request.failure(.badRequest) }
            guard let buffer = request.body.buffer else { return request.failure(.badRequest) }
            return request.persist.set(key: tag, value: String(buffer: buffer), expires: .seconds(numericCast(time)), on: request.eventLoop)
                .map { _ in .ok }
        }
        app.router.get("/persist/:tag") { request -> EventLoopFuture<String?> in
            guard let tag = request.parameters.get("tag", as: String.self) else { return request.failure(.badRequest) }
            return request.persist.get(key: tag, as: String.self, on: request.eventLoop)
        }
        app.XCTStart()
        defer { app.XCTStop() }

        app.XCTExecute(uri: "/persist/test1/0", method: .PUT, body: ByteBufferAllocator().buffer(string: "ThisIsTest1")) { _ in }
        app.XCTExecute(uri: "/persist/test2/10", method: .PUT, body: ByteBufferAllocator().buffer(string: "ThisIsTest2")) { _ in }
        Thread.sleep(forTimeInterval: 1)
        app.XCTExecute(uri: "/persist/test1", method: .GET) { response in
            XCTAssertEqual(response.status, .notFound)
        }
        app.XCTExecute(uri: "/persist/test2", method: .GET) { response in
            let body = try XCTUnwrap(response.body)
            XCTAssertEqual(String(buffer: body), "ThisIsTest2")
        }
    }

    func testCodable() throws {
        struct TestCodable: Codable {
            let buffer: String
        }
        let app = HBApplication(testing: .live)
        // add Fluent
        app.addFluent()
        // add sqlite database
        app.fluent.databases.use(.sqlite(.memory), as: .sqlite)
        // add persist
        app.addPersist(using: .fluent)
        // run migrations
        try app.fluent.migrate().wait()

        app.router.put("/") { request -> EventLoopFuture<HTTPResponseStatus> in
            guard let buffer = request.body.buffer else { return request.failure(.badRequest) }
            return request.persist.set(key: "test", value: TestCodable(buffer: String(buffer: buffer)), on: request.eventLoop)
                .map { _ in .ok }
        }
        app.router.get("/") { request in
            return request.persist.get(key: "test", as: TestCodable.self, on: request.eventLoop).map { $0.map(\.buffer) }
        }
        app.XCTStart()
        defer { app.XCTStop() }

        app.XCTExecute(uri: "/", method: .PUT, body: ByteBufferAllocator().buffer(string: "Persist")) { _ in }
        app.XCTExecute(uri: "/", method: .GET) { response in
            let body = try XCTUnwrap(response.body)
            XCTAssertEqual(String(buffer: body), "Persist")
        }
    }

    func testRemove() throws {
        let app = HBApplication(testing: .live)
        // add Fluent
        app.addFluent()
        // add sqlite database
        app.fluent.databases.use(.sqlite(.memory), as: .sqlite)
        // add persist
        app.addPersist(using: .fluent)
        // run migrations
        try app.fluent.migrate().wait()

        app.router.put("/persist/:tag") { request -> EventLoopFuture<HTTPResponseStatus> in
            guard let tag = request.parameters.get("tag") else { return request.failure(.badRequest) }
            guard let buffer = request.body.buffer else { return request.failure(.badRequest) }
            return request.persist.set(key: tag, value: String(buffer: buffer), on: request.eventLoop)
                .map { _ in .ok }
        }
        app.router.get("/persist/:tag") { request -> EventLoopFuture<String?> in
            guard let tag = request.parameters.get("tag", as: String.self) else { return request.failure(.badRequest) }
            return request.persist.get(key: tag, as: String.self, on: request.eventLoop)
        }
        app.router.delete("/persist/:tag") { request -> EventLoopFuture<HTTPResponseStatus> in
            guard let tag = request.parameters.get("tag", as: String.self) else { return request.failure(.badRequest) }
            return request.persist.remove(key: tag, on: request.eventLoop)
                .map { _ in .noContent }
        }
        app.XCTStart()
        defer { app.XCTStop() }

        app.XCTExecute(uri: "/persist/test1", method: .PUT, body: ByteBufferAllocator().buffer(string: "ThisIsTest1")) { _ in }
        app.XCTExecute(uri: "/persist/test1", method: .DELETE) { _ in }
        app.XCTExecute(uri: "/persist/test1", method: .GET) { response in
            XCTAssertEqual(response.status, .notFound)
        }
    }
}
