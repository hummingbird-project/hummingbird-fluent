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

import AsyncAlgorithms
import FluentKit
import Foundation
import Hummingbird
import NIOCore
import ServiceLifecycle

/// Fluent driver for persist system for storing persistent cross request key/value pairs
public final class FluentPersistDriver: PersistDriver {
    let fluent: Fluent
    let databaseID: DatabaseID?
    let tidyUpFrequency: Duration

    /// Initialize FluentPersistDriver
    /// - Parameters:
    ///   - fluent: Fluent setup
    ///   - databaseID: ID of database to use
    ///   - tidyUpFrequency: How frequently cleanup expired database entries should occur
    public init(fluent: Fluent, databaseID: DatabaseID? = nil, tidyUpFrequency: Duration = .seconds(600)) async {
        self.fluent = fluent
        self.databaseID = databaseID
        self.tidyUpFrequency = tidyUpFrequency
        await self.fluent.migrations.add(CreatePersistModel())
        self.tidy()
    }

    /// Create new key. This doesn't check for the existence of this key already so may fail if the key already exists
    public func create(key: String, value: some Codable, expires: Duration?) async throws {
        let db = self.fluent.db(self.databaseID)
        let data = try JSONEncoder().encode(value)
        let date = expires.map { Date.now + Double($0.components.seconds) } ?? Date.distantFuture
        let model = PersistModel(id: key, data: data, expires: date)
        do {
            try await model.save(on: db)
        } catch let error as DatabaseError where error.isConstraintFailure {
            throw PersistError.duplicate
        } catch {
            self.fluent.logger.debug("Error: \(error)")
        }
    }

    /// Set value for key.
    public func set(key: String, value: some Codable, expires: Duration?) async throws {
        let db = self.fluent.db(self.databaseID)
        let data = try JSONEncoder().encode(value)
        let date = expires.map { Date.now + Double($0.components.seconds) }
        let model = PersistModel(id: key, data: data, expires: date ?? Date.distantFuture)
        do {
            try await model.save(on: db)
        } catch let error as DatabaseError where error.isConstraintFailure {
            // if save fails because of constraint then try to update instead
            let model = try await PersistModel.query(on: db)
                .filter(\._$id == key)
                .first()
            if let model {
                model.data = data
                if let date {
                    model.expires = date
                }
                try await model.update(on: db)
            } else {
                let model = PersistModel(id: key, data: data, expires: date ?? Date.distantFuture)
                try await model.save(on: db)
            }
        } catch {
            self.fluent.logger.debug("Error: \(error)")
        }
    }

    /// Get value for key
    public func get<Object: Codable>(key: String, as object: Object.Type) async throws -> Object? {
        let db = self.fluent.db(self.databaseID)
        do {
            let query = try await PersistModel.query(on: db)
                .filter(\._$id == key)
                .filter(\.$expires > Date())
                .first()
            guard let data = query?.data else { return nil }
            do {
                return try JSONDecoder().decode(object, from: data)
            } catch is DecodingError {
                throw PersistError.invalidConversion
            }
        }
    }

    /// Remove key
    public func remove(key: String) async throws {
        let db = self.fluent.db(self.databaseID)
        let model = try await PersistModel.find(key, on: db)
        guard let model else { return }
        return try await model.delete(force: true, on: db)
    }

    /// tidy up database by cleaning out expired keys
    func tidy() {
        _ = PersistModel.query(on: self.fluent.db(self.databaseID))
            .filter(\.$expires < Date())
            .delete()
    }
}

/// Service protocol requirements
extension FluentPersistDriver {
    public func run() async throws {
        let timerSequence = AsyncTimerSequence(interval: self.tidyUpFrequency, clock: .suspending)
            .cancelOnGracefulShutdown()
        for try await _ in timerSequence {
            self.tidy()
        }
    }
}

/// Fluent model used to store persist data
final class PersistModel: Model, @unchecked Sendable {
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
        database.schema("_hb_persist_").delete()
    }
}
