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
public class HBFluentPersistDriver: HBPersistDriver {
    /// Initialize HBFluentPersistDriver
    /// - Parameters:
    ///   - fluent: Fluent setup
    ///   - databaseID: ID of database to use
    public init(fluent: HBFluent, databaseID: DatabaseID? = nil) {
        self.fluent = fluent
        self.databaseID = databaseID
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
    public func create<Object: Codable>(key: String, value: Object, expires: TimeAmount?, request: HBRequest) -> EventLoopFuture<Void> {
        do {
            let db = self.database(on: request.eventLoop)
            let data = try JSONEncoder().encode(value)
            let date = expires.map { Date() + Double($0.nanoseconds) / 1_000_000_000 } ?? Date.distantFuture
            let model = PersistModel(id: key, data: data, expires: date)
            return model.save(on: db)
                .flatMapErrorThrowing { error in
                    // if save fails because of constraint then throw duplicate error
                    if let error = error as? DatabaseError, error.isConstraintFailure {
                        throw HBPersistError.duplicate
                    }
                    throw error
                }
                .map { _ in }
        } catch {
            return request.eventLoop.makeFailedFuture(error)
        }
    }

    /// Set value for key.
    public func set<Object: Codable>(key: String, value: Object, expires: TimeAmount?, request: HBRequest) -> EventLoopFuture<Void> {
        do {
            let db = self.database(on: request.eventLoop)
            let data = try JSONEncoder().encode(value)
            let date = expires.map { Date() + Double($0.nanoseconds) / 1_000_000_000 } ?? Date.distantFuture
            let model = PersistModel(id: key, data: data, expires: date)
            return model.save(on: db)
                .flatMapError { error in
                    // if save fails because of constraint then try to update instead
                    if let error = error as? DatabaseError, error.isConstraintFailure {
                        return PersistModel.query(on: db)
                            .filter(\._$id == key)
                            .first()
                            .flatMap { model in
                                if let model = model {
                                    model.data = data
                                    model.expires = date
                                    return model.update(on: db).map { _ in }
                                } else {
                                    let model = PersistModel(id: key, data: data, expires: date)
                                    return model.save(on: db).map { _ in }
                                }
                            }
                    }
                    return request.eventLoop.makeFailedFuture(error)
                }
                .map { _ in }
        } catch {
            return request.eventLoop.makeFailedFuture(error)
        }
    }

    /// Get value for key
    public func get<Object: Codable>(key: String, as object: Object.Type, request: HBRequest) -> EventLoopFuture<Object?> {
        let db = self.database(on: request.eventLoop)
        return PersistModel.query(on: db)
            .filter(\._$id == key)
            .filter(\.$expires > Date())
            .first()
            .flatMapThrowing {
                guard let data = $0?.data else { return nil }
                return try JSONDecoder().decode(object, from: data)
            }
            .flatMapErrorThrowing { error in
                print(error)
                throw error
            }
    }

    /// Remove key
    public func remove(key: String, request: HBRequest) -> EventLoopFuture<Void> {
        let db = self.database(on: request.eventLoop)
        return PersistModel.find(key, on: db)
            .flatMap { model in
                guard let model = model else { return request.eventLoop.makeSucceededVoidFuture() }
                return model.delete(force: true, on: db)
            }
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

    let fluent: HBFluent
    let databaseID: DatabaseID?
    var tidyTask: RepeatedTask?
}

/// Factory class for persist drivers
extension HBPersistDriverFactory {
    /// Fluent driver for persist system
    public static var fluent: HBPersistDriverFactory {
        .init(create: { app in
            precondition(
                app.extensions.exists(\HBApplication.fluent),
                "Cannot use Fluent persist driver without having setup Fluent. Please call HBApplication.addFluent()"
            )
            return HBFluentPersistDriver(fluent: app.fluent, databaseID: nil)
        })
    }

    /// Fluent driver for persist system using a specific database id
    public static func fluent(_ datebaseID: DatabaseID?) -> HBPersistDriverFactory {
        .init(create: { app in
            precondition(
                app.extensions.exists(\HBApplication.fluent),
                "Cannot use Fluent persist driver without having setup Fluent. Please call HBApplication.addFluent()"
            )
            return HBFluentPersistDriver(fluent: app.fluent, databaseID: datebaseID)
        })
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
