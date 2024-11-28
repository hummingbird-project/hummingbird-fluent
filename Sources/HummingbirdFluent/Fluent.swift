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
import Hummingbird
import ServiceLifecycle

/// Manage fluent databases and migrations
///
/// `Fluent` requires lifecycle management and should be added to your list of services
/// ```
/// let fluent = Fluent(logger: logger)
/// let app = Application(
///     router: router,
///     services: [fluent]
/// )
/// ````
public struct Fluent: Sendable, Service {
    /// Event loop group
    public var eventLoopGroup: EventLoopGroup { self.databases.eventLoopGroup }
    /// Logger
    public let logger: Logger
    /// Databases attached
    public let databases: Databases
    /// Database Migrations
    public var migrations: FluentMigrations

    /// Initialize Fluent
    /// - Parameters:
    ///   - eventLoopGroupProvider: EventLoopGroup used by databases
    ///   - threadPool: NIOThreadPool used by databases
    ///   - logger: Logger used by databases
    public init(
        eventLoopGroupProvider: EventLoopGroupProvider = .singleton,
        threadPool: NIOThreadPool = .singleton,
        logger: Logger
    ) {
        let eventLoopGroup = eventLoopGroupProvider.eventLoopGroup
        self.databases = Databases(threadPool: threadPool, on: eventLoopGroup)
        self.migrations = .init()
        self.logger = logger
    }

    /// Run Fluent service.
    ///
    /// Waits for graceful shutdown and then shuts down any database connections
    public func run() async throws {
        try? await gracefulShutdown()
        try await self.shutdown()
    }

    /// Migrate fluent databases
    public func migrate() async throws {
        try await self.migrations.migrate(databases: self.databases, logger: self.logger)
    }

    /// Revert fluent database migration
    public func revert() async throws {
        try await self.migrations.revert(databases: self.databases, logger: self.logger)
    }

    /// Shutdown Fluent databases
    public func shutdown() async throws {
        await self.databases.shutdownAsync()
    }

    /// Return Database connection
    ///
    /// - Parameters:
    ///   - id: ID of database
    ///   - logger: Logger database uses
    ///   - history: Query history storage
    ///   - pageSizeLimit: Set page size limit to avoid server overload
    /// - Returns: Database connection
    public func db(_ id: DatabaseID? = nil, logger: Logger? = nil, history: QueryHistory? = nil, pageSizeLimit: Int? = nil) -> Database {
        self.databases
            .database(
                id,
                logger: logger ?? self.logger,
                on: self.eventLoopGroup.any(),
                history: history,
                pageSizeLimit: pageSizeLimit
            )!
    }
}

/// Manage Fluent database migrations
public actor FluentMigrations {
    public let migrations: Migrations

    init() {
        self.migrations = .init()
    }

    ///  Add array of migrations
    /// - Parameters:
    ///   - migrations: Migrations array
    ///   - id: database id
    @inlinable
    public func add(_ migrations: Migration..., to id: DatabaseID? = nil) {
        self.add(migrations, to: id)
    }

    ///  Add array of migrations
    /// - Parameters:
    ///   - migrations: Migrations array
    ///   - id: database id
    @inlinable
    public func add(_ migrations: [Migration], to id: DatabaseID? = nil) {
        self.migrations.add(migrations, to: id)
    }

    ///  Migrate fluent databases
    /// - Parameters:
    ///   - databases: List of databases to migrate
    ///   - logger: Logger to use
    func migrate(databases: Databases, logger: Logger) async throws {
        let migrator = Migrator(
            databases: databases,
            migrations: self.migrations,
            logger: logger,
            on: databases.eventLoopGroup.any()
        )
        try await migrator.setupIfNeeded().get()
        try await migrator.prepareBatch().get()
    }

    ///  Revert fluent database migration
    /// - Parameters:
    ///   - databases: List of databases on which to revert migrations
    ///   - logger: Logger to use
    func revert(databases: Databases, logger: Logger) async throws {
        let migrator = Migrator(
            databases: databases,
            migrations: self.migrations,
            logger: logger,
            on: databases.eventLoopGroup.any()
        )
        try await migrator.setupIfNeeded().get()
        try await migrator.revertAllBatches().get()
    }

    ///  Revert last batch of fluent database migrations
    /// - Parameters:
    ///   - databases: List of databases on which to revert migrations
    ///   - logger: Logger to use
    public func revertLast(databases: Databases, logger: Logger) async throws {
        let migrator = Migrator(
            databases: databases,
            migrations: self.migrations,
            logger: logger,
            on: databases.eventLoopGroup.any()
        )
        try await migrator.setupIfNeeded().get()
        try await migrator.revertLastBatch().get()
    }
}
