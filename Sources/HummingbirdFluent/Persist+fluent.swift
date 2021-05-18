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

/// Fluent driver for persist system for storing persistent cross request key/value pairs
class HBFluentPersistDriver: HBPersistDriver {
    /// Initialize HBFluentPersistDriver
    init(application: HBApplication, databaseID: DatabaseID?) {
        precondition(
            application.extensions.exists(\HBApplication.fluent),
            "Cannot use Fluent persist driver without having setup Fluent. Please call HBApplication.addFluent()"
        )
        self.application = application
        self.databaseID = databaseID
        application.fluent.migrations.add(CreatePersistModel())
        self.tidyTask = application.eventLoopGroup.next().scheduleRepeatedTask(initialDelay: .hours(1), delay: .hours(1)) { _ in
            self.tidy()
        }
    }

    /// shutdown driver, cancel tidy task
    func shutdown() {
        self.tidyTask?.cancel()
    }

    /// Create new key. This doesn't check for the existence of this key already so may fail if the key already exists
    func create<Object: Codable>(key: String, value: Object, expires: TimeAmount?, request: HBRequest) -> EventLoopFuture<Void> {
        do {
            let db = request.db(self.databaseID)
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
    func set<Object: Codable>(key: String, value: Object, expires: TimeAmount?, request: HBRequest) -> EventLoopFuture<Void> {
        do {
            let db = request.db(self.databaseID)
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
    func get<Object: Codable>(key: String, as object: Object.Type, request: HBRequest) -> EventLoopFuture<Object?> {
        return PersistModel.query(on: request.db(self.databaseID))
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
    func remove(key: String, request: HBRequest) -> EventLoopFuture<Void> {
        return PersistModel.find(key, on: request.db(self.databaseID))
            .flatMap { model in
                guard let model = model else { return request.eventLoop.makeSucceededVoidFuture() }
                return model.delete(force: true, on: request.db(self.databaseID))
            }
    }

    /// tidy up database by cleaning out expired keys
    func tidy() {
        _ = PersistModel.query(on: self.application.db(self.databaseID))
            .filter(\.$expires < Date())
            .delete()
    }

    let application: HBApplication
    let databaseID: DatabaseID?
    var tidyTask: RepeatedTask?
}

/// Factory class for persist drivers
extension HBPersistDriverFactory {
    /// fluent driver for persist system
    public static var fluent: HBPersistDriverFactory {
        .init(create: { app in HBFluentPersistDriver(application: app, databaseID: nil) })
    }

    /// fluent driver for persist system using a specific database id
    public static func fluent(_ datebaseID: DatabaseID?) -> HBPersistDriverFactory {
        .init(create: { app in HBFluentPersistDriver(application: app, databaseID: datebaseID) })
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
