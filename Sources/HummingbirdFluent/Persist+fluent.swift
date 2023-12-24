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

import FluentKit
import Foundation
import Hummingbird
import NIOCore

/// Fluent driver for persist system for storing persistent cross request key/value pairs
public final class HBFluentPersistDriver<C: Clock>: HBPersistDriver {
    let fluent: HBFluent
    let databaseID: DatabaseID?
    let clock: C
    var tidyTask: RepeatedTask?

    /// Initialize HBFluentPersistDriver
    /// - Parameters:
    ///   - fluent: Fluent setup
    ///   - databaseID: ID of database to use
    public init(fluent: HBFluent, databaseID: DatabaseID? = nil, clock: C = .suspending) {
        self.fluent = fluent
        self.databaseID = databaseID
        self.clock = clock
        self.fluent.migrations.add(CreatePersistModel())
        self.tidyTask = fluent.eventLoopGroup.next().scheduleRepeatedTask(initialDelay: .hours(1), delay: .hours(1)) { _ in
            self.tidy()
        }
    }

    /// shutdown driver, cancel tidy task
    public func shutdown() {
        self.tidyTask?.cancel()
    }

    /// Create new key. This doesn't check for the existence of this key already so may fail if the key already exists
    public func create<Object: Codable>(key: String, value: Object, expires: Duration?) async throws {
        let db = self.database(on: self.fluent.eventLoopGroup.any())
        let data = try JSONEncoder().encode(value)
        let date = expires.map { Date.now + Double($0.components.seconds) } ?? Date.distantFuture
        let model = PersistModel(id: key, data: data, expires: date)
        do {
            try await model.save(on: db)
        } catch let error as DatabaseError where error.isConstraintFailure {
            throw HBPersistError.duplicate
        }
    }

    /// Set value for key.
    public func set<Object: Codable>(key: String, value: Object, expires: Duration?) async throws {
        let db = self.database(on: self.fluent.eventLoopGroup.any())
        let data = try JSONEncoder().encode(value)
        let date = expires.map { Date.now + Double($0.components.seconds) } ?? Date.distantFuture
        let model = PersistModel(id: key, data: data, expires: date)
        do {
            try await model.save(on: db)
        } catch let error as DatabaseError where error.isConstraintFailure {
            // if save fails because of constraint then try to update instead
            let model = try await PersistModel.query(on: db)
                .filter(\._$id == key)
                .first()
            if let model = model {
                model.data = data
                model.expires = date
                try await model.update(on: db)
            } else {
                let model = PersistModel(id: key, data: data, expires: date)
                try await model.save(on: db)
            }
        }
    }

    /// Get value for key
    public func get<Object: Codable>(key: String, as object: Object.Type) async throws -> Object? {
        let db = self.database(on: self.fluent.eventLoopGroup.any())
        do {
            let query = try await PersistModel.query(on: db)
                .filter(\._$id == key)
                .filter(\.$expires > Date())
                .first()
            guard let data = query?.data else { return nil }
            return try JSONDecoder().decode(object, from: data)
        }
    }

    /// Remove key
    public func remove(key: String) async throws {
        let db = self.database(on: self.fluent.eventLoopGroup.any())
        let model = try await PersistModel.find(key, on: db)
        guard let model = model else { return }
        return try await model.delete(force: true, on: db)
    }

    /// tidy up database by cleaning out expired keys
    func tidy() {
        _ = PersistModel.query(on: self.database(on: self.fluent.eventLoopGroup.next()))
            .filter(\.$expires < Date())
            .delete()
    }

    /// Get database connection on event loop
    func database(on eventLoop: EventLoop) -> Database {
        self.fluent.db(self.databaseID, on: eventLoop)
    }
}

/// Fluent model used to store persist data
final class PersistModel: Model {
    init() {}

    // name of persist table
    static let schema = "_hb_persist_"

    @ID(custom: "id")
    var id: String?

    @Field(key: "data")
    var data: Data

    @Field(key: "expires")
    var expires: Date?

    init(id: String, data: Data, expires: Date? = nil) {
        self.id = id
        self.data = data
        self.expires = expires
    }
}

/// Migration for creating persist model
struct CreatePersistModel: Migration {
    func prepare(on database: Database) -> EventLoopFuture<Void> {
        database.schema("_hb_persist_")
            .field(.id, .string, .identifier(auto: false))
            .field("data", .data, .required)
            .field("expires", .datetime)
            .create()
    }

    func revert(on database: Database) -> EventLoopFuture<Void> {
        database.schema("_persist_").delete()
    }
}
