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

import FluentKit
import FluentSQLiteDriver
// import FluentMySQLDriver
// import FluentPostgresDriver
import Hummingbird
import HummingbirdFluent
import HummingbirdFoundation
import HummingbirdXCT
import Logging
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

    struct CreateResponse: HBResponseCodable {
        let id: UUID
    }

    func testPutGet() async throws {
        let logger = Logger(label: "FluentTests")
        let fluent = HBFluent(
            logger: logger
        )
        // add sqlite database
        fluent.databases.use(.sqlite(.memory), as: .sqlite)
        /* fluent.databases.use(
             .postgres(
                 configuration: .init(
                     hostname: "localhost",
                     port: 5432,
                     username: "hummingbird",
                     password: "hummingbird",
                     database: "hummingbird", tls: .disable
                 ),
                 maxConnectionsPerEventLoop: 32
             ),
             as: .psql
         ) */
        // add migration
        await fluent.migrations.add(CreatePlanet())
        // run migrations
        try await fluent.migrate()

        let router = HBRouter()
        router.put("planet") { request, context in
            let planet = try await request.decode(as: Planet.self, context: context)
            try await planet.create(on: fluent.db())
            return CreateResponse(id: planet.id!)
        }
        router.get("planet/:id") { _, context in
            let id = try context.parameters.require("id", as: UUID.self)
            return try await Planet.query(on: fluent.db())
                .filter(\.$id == id)
                .first()
        }
        var app = HBApplication(responder: router.buildResponder())
        app.addServices(fluent)
        try await app.test(.live) { client in
            let planet = Planet(name: "Saturn")
            let id = try await client.XCTExecute(
                uri: "/planet",
                method: .put,
                body: JSONEncoder().encodeAsByteBuffer(planet, allocator: ByteBufferAllocator())
            ) { response in
                let buffer = try XCTUnwrap(response.body)
                let createResponse = try JSONDecoder().decode(CreateResponse.self, from: buffer)
                return createResponse.id
            }

            let planet2 = try await client.XCTExecute(
                uri: "/planet/\(id.uuidString)",
                method: .get
            ) { response in
                let buffer = try XCTUnwrap(response.body)
                return try JSONDecoder().decode(Planet.self, from: buffer)
            }
            XCTAssertEqual(planet2.name, "Saturn")
        }
    }
}
