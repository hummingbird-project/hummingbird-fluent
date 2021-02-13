import FluentKit
import Hummingbird

extension HBApplication {
    /// Create Fluent management object.
    public func addFluent() {
        self.fluent = .init(application: self)
    }

    /// Get default database
    public var db: Database {
        self.db(nil)
    }

    /// Get database with ID
    /// - Parameter id: database id
    /// - Returns: database
    public func db(_ id: DatabaseID?) -> Database {
        self.fluent.databases
            .database(
                id,
                logger: self.logger,
                on: self.eventLoopGroup.next(),
                history: self.fluent.history.enabled ? self.fluent.history.history : nil
            )!
    }

    public struct Fluent {
        /// databases attached
        public let databases: Databases
        /// list of migrations
        public let migrations: Migrations
        /// application
        unowned let application: HBApplication

        init(application: HBApplication) {
            self.databases = Databases(threadPool: application.threadPool, on: application.eventLoopGroup)
            self.migrations = .init()
            self.application = application
        }

        func shutdown() {
            self.databases.shutdown()
        }

        /// fluent migrator
        public var migrator: Migrator {
            Migrator(
                databases: self.databases,
                migrations: self.migrations,
                logger: self.application.logger,
                on: self.application.eventLoopGroup.next()
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
    }

    /// Fluent interface object
    public var fluent: Fluent {
        get { self.extensions.get(\.fluent) }
        set {
            self.extensions.set(\.fluent, value: newValue) { fluent in
                fluent.shutdown()
            }
        }
    }
}
