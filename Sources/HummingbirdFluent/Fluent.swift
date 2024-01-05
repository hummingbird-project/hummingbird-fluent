//===----------------------------------------------------------------------===//
//
// This source file is part of the Hummingbird server framework project
//
// Copyright (c) 2021-2023 the Hummingbird authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See hummingbird/CONTRIBUTORS.txt for the list of Hummingbird authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import FluentKit
import Hummingbird
import ServiceLifecycle

@MainActor
public struct MainActorBox<Value>: Sendable {
    public let value: Value
}

extension DatabaseID: @unchecked Sendable {}

/// Manage fluent databases and migrations
///
/// You can either create this separate from `HBApplication` or add it to your application
/// using `HBApplication.addFluent`.
public struct HBFluent: Sendable, Service {
    /// Event loop group
    public let eventLoopGroup: EventLoopGroup
    /// Logger
    public let logger: Logger
    /// List of migrations. Only accessible from the main actor
    @MainActor
    public var migrations: Migrations { self._migrations.value }
    /// Databases attached
    public var databases: Databases { self._databases.wrappedValue }

    private let _databases: UnsafeTransfer<Databases>
    private let _migrations: MainActorBox<Migrations>

    /// Initialize HBFluent
    /// - Parameters:
    ///   - eventLoopGroup: EventLoopGroup used by databases
    ///   - threadPool: NIOThreadPool used by databases
    ///   - logger: Logger used by databases
    public init(
        eventLoopGroupProvider: EventLoopGroupProvider = .singleton,
        threadPool: NIOThreadPool = .singleton,
        logger: Logger
    ) {
        let eventLoopGroup = eventLoopGroupProvider.eventLoopGroup
        self._databases = .init(Databases(threadPool: threadPool, on: eventLoopGroup))
        self._migrations = .init(value: .init())
        self.eventLoopGroup = eventLoopGroup
        self.logger = logger
    }

    public func run() async throws {
        await GracefulShutdownWaiter().wait()
        self._databases.wrappedValue.shutdown()
    }

    /// fluent migrator
    @MainActor
    public var migrator: Migrator {
        Migrator(
            databases: self.databases,
            migrations: self.migrations,
            logger: self.logger,
            on: self.eventLoopGroup.next()
        )
    }

    /// Run migration if needed
    @MainActor
    public func migrate() async throws {
        try await self.migrator.setupIfNeeded().get()
        try await self.migrator.prepareBatch().get()
    }

    /// Run revert if needed
    @MainActor
    public func revert() async throws {
        try await self.migrator.setupIfNeeded().get()
        try await self.migrator.revertAllBatches().get()
    }

    /// Return Database connection
    ///
    /// - Parameters:
    ///   - id: ID of database
    ///   - history: Query history storage
    ///   - pageSizeLimit: Set page size limit to avoid server overload
    /// - Returns: Database connection
    public func db(_ id: DatabaseID? = nil, history: QueryHistory? = nil, pageSizeLimit: Int? = nil) -> Database {
        self._databases.wrappedValue
            .database(
                id,
                logger: self.logger,
                on: self.eventLoopGroup.any(),
                history: history,
                pageSizeLimit: pageSizeLimit
            )!
    }
}
