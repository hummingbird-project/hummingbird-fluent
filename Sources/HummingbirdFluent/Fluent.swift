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

/// Manage fluent databases and migrations
///
/// You can either create this separate from `HBApplication` or add it to your application
/// using `HBApplication.addFluent`.
public struct HBFluent: @unchecked Sendable, Service {
    /// Databases attached
    public let databases: Databases
    /// List of migrations
    public let migrations: Migrations
    /// Event loop group
    public let eventLoopGroup: EventLoopGroup
    /// Logger
    public let logger: Logger

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
        self.databases = Databases(threadPool: threadPool, on: eventLoopGroup)
        self.migrations = .init()
        self.eventLoopGroup = eventLoopGroup
        self.logger = logger
    }

    public func run() async throws {
        await GracefulShutdownWaiter().wait()
        self.databases.shutdown()
    }

    /// fluent migrator
    public var migrator: Migrator {
        Migrator(
            databases: self.databases,
            migrations: self.migrations,
            logger: self.logger,
            on: self.eventLoopGroup.next()
        )
    }

    /// Run migration if needed
    public func migrate() async throws {
        try await self.migrator.setupIfNeeded().get()
        try await self.migrator.prepareBatch().get()
    }

    /// Run revert if needed
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
        self.databases
            .database(
                id,
                logger: self.logger,
                on: self.eventLoopGroup.any(),
                history: history,
                pageSizeLimit: pageSizeLimit
            )!
    }
}
