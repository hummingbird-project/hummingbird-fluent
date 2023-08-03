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
/// This type is available from `HBApplication` after you have called `HBApplication.addFluent`.
public struct HBFluent {
    /// Fluent history management
    public class History {
        public private(set) var enabled: Bool
        public private(set) var history: QueryHistory?

        init() {
            self.enabled = false
            self.history = nil
        }

        public func start() {
            self.enabled = true
            self.history = .init()
        }

        public func stop() {
            self.enabled = false
        }

        public func clear() {
            self.history = .init()
        }
    }

    /// databases attached
    public let databases: Databases
    /// list of migrations
    public let migrations: Migrations
    /// event loop group used by migrator
    public let eventLoopGroup: EventLoopGroup
    /// Logger
    public let logger: Logger
    /// Fluent history setup
    public let history: History

    init(application: HBApplication) {
        self.databases = Databases(threadPool: application.threadPool, on: application.eventLoopGroup)
        self.migrations = .init()
        self.eventLoopGroup = application.eventLoopGroup
        self.logger = application.logger
        self.history = .init()
    }

    init(
        eventLoopGroup: EventLoopGroup,
        threadPool: NIOThreadPool,
        logger: Logger
    ) {
        self.databases = Databases(threadPool: threadPool, on: eventLoopGroup)
        self.migrations = .init()
        self.eventLoopGroup = eventLoopGroup
        self.logger = logger
        self.history = .init()
    }

    func shutdown() {
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

    public func db(_ id: DatabaseID?, on eventLoop: EventLoop) -> Database {
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
