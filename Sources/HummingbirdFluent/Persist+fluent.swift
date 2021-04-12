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

final class PersistModel: Model {
    init() {}

    // name of persist table
    static let schema = "_persist_"

    @ID(custom: "id")
    var id: String?

    @Field(key: "value")
    var value: Data

    @Field(key: "expires")
    var expires: Date?

    init(id: String, value: Data, expires: Date? = nil) {
        self.id = id
        self.value = value
        self.expires = expires
    }
}

struct CreatePersistModel: Migration {
    func prepare(on database: Database) -> EventLoopFuture<Void> {
        database.schema("_persist_")
            .field(.id, .string, .identifier(auto: false))
            .field("value", .data, .required)
            .field("expires", .datetime)
            .create()
    }

    func revert(on database: Database) -> EventLoopFuture<Void> {
        database.schema("_persist_").delete()
    }
}

/// Fluent driver for persist system for storing persistent cross request key/value pairs
class HBFluentPersistDriver: HBPersistDriver {
    /// Initialize HBFluentPersistDriver
    init(application: HBApplication, databaseID: DatabaseID?) {
        self.application = application
        self.databaseID = databaseID
        application.fluent.migrations.add(CreatePersistModel())
        application.eventLoopGroup.next().scheduleRepeatedTask(initialDelay: .seconds(10), delay: .hours(1)) { _ in
            self.tidy()
        }
    }

    /// Set value for key.
    ///
    /// Checks to see if key already exists, if it does then updates the value for that key otherwise saves a value for key
    func set<Object: Codable>(key: String, value: Object, request: HBRequest) -> EventLoopFuture<Void> {
        do {
            let db = request.db(self.databaseID)
            let data = try JSONEncoder().encode(value)
            return PersistModel.query(on: db)
                .filter(\._$id == key)
                .first()
                .flatMap { model in
                    if let model = model {
                        model.value = data
                        model.expires = Date.distantFuture
                        return model.update(on: db).map { _ in }
                    } else {
                        let model = PersistModel(id: key, value: data, expires: Date.distantFuture)
                        return model.save(on: db).map { _ in }
                    }
                }
                .flatMapErrorThrowing { error in
                    print(error)
                    throw error
                }
        } catch {
            return request.eventLoop.makeFailedFuture(error)
        }
    }

    func set<Object: Codable>(key: String, value: Object, expires: TimeAmount, request: HBRequest) -> EventLoopFuture<Void> {
        do {
            let db = request.db(self.databaseID)
            let data = try JSONEncoder().encode(value)
            return PersistModel.query(on: db)
                .filter(\._$id == key)
                .first()
                .flatMap { model in
                    if let model = model {
                        model.value = data
                        model.expires = Date() + Double(expires.nanoseconds) / 1_000_000_000
                        return model.update(on: db).map { _ in }
                    } else {
                        let model = PersistModel(id: key, value: data, expires: Date() + Double(expires.nanoseconds) / 1_000_000_000)
                        return model.save(on: db).map { _ in }
                    }
                }
                .flatMapErrorThrowing { error in
                    print(error)
                    throw error
                }
        } catch {
            return request.eventLoop.makeFailedFuture(error)
        }
    }

    func get<Object: Codable>(key: String, as object: Object.Type, request: HBRequest) -> EventLoopFuture<Object?> {
        return PersistModel.query(on: request.db(self.databaseID))
            .filter(\._$id == key)
            .filter(\.$expires > Date())
            .first()
            .flatMapThrowing {
                guard let data = $0?.value else { return nil }
                return try JSONDecoder().decode(object, from: data)
            }
            .flatMapErrorThrowing { error in
                print(error)
                throw error
            }
    }

    func remove(key: String, request: HBRequest) -> EventLoopFuture<Void> {
        return PersistModel.find(key, on: request.db(self.databaseID))
            .flatMap { model in
                guard let model = model else { return request.eventLoop.makeSucceededVoidFuture() }
                return model.delete(force: true, on: request.db(self.databaseID))
            }
    }

    func tidy() {
        _ = PersistModel.query(on: application.db(self.databaseID))
            .filter(\.$expires < Date())
            .delete()
    }

    let application: HBApplication
    let databaseID: DatabaseID?
}

/// Factory class for persist drivers
extension HBPersistDriverFactory {
    /// In memory driver for persist system
    public static var fluent: HBPersistDriverFactory {
        .init(create: { app in HBFluentPersistDriver(application: app, databaseID: nil) })
    }

    /// In memory driver for persist system
    public static func fluent(_ datebaseID: DatabaseID?) -> HBPersistDriverFactory {
        .init(create: { app in HBFluentPersistDriver(application: app, databaseID: datebaseID) })
    }
}
