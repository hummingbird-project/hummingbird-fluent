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

/// Manage fluent databases and migrations
///
/// You can either create this separate from `HBApplication` or add it to your application
/// using `HBApplication.addFluent`.
public struct HBFluent {
    /// Fluent history management
    public class History {
        /// Is history recording enabled
        public private(set) var enabled: Bool
        // History of queries to Fluent
        public private(set) var history: QueryHistory?

        init() {
            self.enabled = false
            self.history = nil
        }

        /// Start recording history
        public func start() {
            self.enabled = true
            self.history = .init()
        }

        /// Stop recording history
        public func stop() {
            self.enabled = false
        }

        /// Clear history
        public func clear() {
            self.history = .init()
        }
    }

    /// Databases attached
    public let databases: Databases
    /// List of migrations
    public let migrations: Migrations
    /// Event loop group used by migrator
    public let eventLoopGroup: EventLoopGroup
    /// Logger
    public let logger: Logger
    /// Fluent history setup
    public let history: History

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
        self.history = .init()
    }

    /// Shutdown databases
    public func shutdown() {
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
    public func migrate() -> EventLoopFuture<Void> {
        self.migrator.setupIfNeeded().flatMap {
            self.migrator.prepareBatch()
        }
    }

    /// Run revert if needed
    public func revert() -> EventLoopFuture<Void> {
        self.migrator.setupIfNeeded().flatMap {
            self.migrator.revertAllBatches()
        }
    }

    /// Return Database connection
    ///
    /// - Parameters:
    ///   - id: ID of database
    ///   - eventLoop: Eventloop database connection is running on
    /// - Returns: Database connection
    public func db(_ id: DatabaseID? = nil, on eventLoop: EventLoop) -> Database {
        self.databases
            .database(
                id,
                logger: self.logger,
                on: eventLoop,
                history: self.history.enabled ? self.history.history : nil
            )!
    }
}

/// async/await
@available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
extension HBFluent {
    /// Run migration if needed
    public func migrate() async throws {
        try await self.migrate().get()
    }

    /// Run revert if needed
    public func revert() async throws {
        try await self.revert().get()
    }
}
