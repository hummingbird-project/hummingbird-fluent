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

#if compiler(>=5.5.2) && canImport(_Concurrency)

import FluentKit
import FluentSQLiteDriver
// import FluentMySQLDriver
// import FluentPostgresDriver
import Hummingbird
import HummingbirdFluent
import HummingbirdFoundation
import HummingbirdXCT
import XCTest

@available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
final class FluentTests: XCTestCase {
    final class Planet: Model, HBResponseCodable {
        // Name of the table or collection.
        static let schema = "planets"

        // Unique identifier for this Planet.
        @ID(key: .id)
        var id: UUID?

        // The Planet's name.
        @Field(key: "name")
        var name: String

        // Creates a new, empty Planet.
        init() {}

        // Creates a new Planet with all properties set.
        init(id: UUID? = nil, name: String) {
            self.id = id
            self.name = name
        }
    }

    struct CreatePlanet: AsyncMigration {
        // Prepares the database for storing Galaxy models.
        func prepare(on database: Database) async throws {
            try await database.schema("planets")
                .id()
                .field("name", .string)
                .create()
        }

        // Optionally reverts the changes made in the prepare method.
        func revert(on database: Database) async throws {
            try await database.schema("planets").delete()
        }
    }

    func createApplication() throws -> HBApplication {
        let app = HBApplication(testing: .live)
        app.decoder = JSONDecoder()
        app.encoder = JSONEncoder()
        // add Fluent
        app.addFluent()
        // add sqlite database
        app.fluent.databases.use(.sqlite(.memory), as: .sqlite)
        // app.fluent.databases.use(.postgres(hostname: "localhost", username: "postgres", password: "vapor", database: "vapor"), as: .psql)
        /* app.fluent.databases.use(.mysql(
                                     hostname: "localhost",
                                     username: "root",
                                     password: "vapor",
                                     database: "vapor",
                                     tlsConfiguration: .forClient(certificateVerification: .none)
         ), as: .mysql) */
        // add persist
        app.fluent.migrations.add(CreatePlanet())
        // run migrations
        try app.fluent.migrate().wait()

        return app
    }

    struct CreateResponse: HBResponseCodable {
        let id: UUID
    }

    func testPutGet() async throws {
        let app = try createApplication()
        app.router.put("planet") { request in
            let planet = try request.decode(as: Planet.self)
            try await planet.create(on: request.db)
            return CreateResponse(id: planet.id!)
        }
        app.router.get("planet/:id") { request in
            let id = try request.parameters.require("id", as: UUID.self)
            return try await Planet.query(on: request.db)
                .filter(\.$id == id)
                .first()
        }

        try app.XCTStart()
        defer { app.XCTStop() }

        let planet = Planet(name: "Saturn")
        let id = try app.XCTExecute(
            uri: "/planet",
            method: .PUT,
            body: JSONEncoder().encodeAsByteBuffer(planet, allocator: ByteBufferAllocator())
        ) { response in
            let buffer = try XCTUnwrap(response.body)
            let createResponse = try JSONDecoder().decode(CreateResponse.self, from: buffer)
            return createResponse.id
        }

        let planet2 = try app.XCTExecute(
            uri: "/planet/\(id.uuidString)",
            method: .GET
        ) { response in
            let buffer = try XCTUnwrap(response.body)
            return try JSONDecoder().decode(Planet.self, from: buffer)
        }
        XCTAssertEqual(planet2.name, "Saturn")
    }
}

#endif // compiler(>=5.5.2) && canImport(_Concurrency)
