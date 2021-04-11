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

    @Timestamp(key: "expires", on: .delete, format: .iso8601)
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
            .field(.string("value"), .custom("JSONB"), .required)
            .field(.string("expires"), .date)
            .create()
    }

    func revert(on database: Database) -> EventLoopFuture<Void> {
        database.schema("_persist_").delete()
    }
}

/// In memory driver for persist system for storing persistent cross request key/value pairs
struct HBFluentPersistDriver: HBPersistDriver {
    init(application: HBApplication) {
        self.application = application
        self.application.fluent.migrations.add(CreatePersistModel())
    }

    func set<Object: Codable>(key: String, value: Object, on eventLoop: EventLoop) -> EventLoopFuture<Void> {
        do {
            let data = try JSONEncoder().encode(value)
            let model = PersistModel(id: key, value: data, expires: nil)
            return model.save(on: application.db)
                .map { _ in }
        } catch {
            return eventLoop.makeFailedFuture(error)
        }
    }

    func set<Object: Codable>(key: String, value: Object, expires: TimeAmount, on eventLoop: EventLoop) -> EventLoopFuture<Void> {
        do {
            let data = try JSONEncoder().encode(value)
            let model = PersistModel(id: key, value: data, expires: Date() + Double(expires.nanoseconds) / 1_000_000_000)
            return model.save(on: application.db)
                .map { _ in }
        } catch {
            return eventLoop.makeFailedFuture(error)
        }
    }

    func get<Object: Codable>(key: String, as object: Object.Type, on eventLoop: EventLoop) -> EventLoopFuture<Object?> {
        return PersistModel.find(key, on: application.db)
            .flatMapThrowing {
                guard let data = $0?.value else { return nil }
                return try JSONDecoder().decode(object, from: data)
            }
    }

    func remove(key: String, on eventLoop: EventLoop) -> EventLoopFuture<Void> {
        return PersistModel.find(key, on: application.db)
            .flatMap { model in
                guard let model = model else { return eventLoop.makeSucceededVoidFuture() }
                return model.delete(force: true, on: application.db)
            }
    }

    let application: HBApplication
}

/// Factory class for persist drivers
extension HBPersistDriverFactory {
    /// In memory driver for persist system
    public static var fluent: HBPersistDriverFactory {
        .init(create: { app in HBFluentPersistDriver(application: app) })
    }
}
