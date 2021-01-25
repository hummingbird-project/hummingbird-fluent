import FluentKit
import Hummingbird

extension HBApplication {
    public var db: Database {
        self.db(nil)
    }

    public func db(_ id: DatabaseID?) -> Database {
        self.databases
            .database(
                id,
                logger: self.logger,
                on: self.eventLoopGroup.next(),
                history: nil
            )!
    }

    public var databases: Databases {
        self.fluent.databases
    }

    public var migrations: Migrations {
        self.fluent.migrations
    }

    struct Fluent {
        let databases: Databases
        let migrations: Migrations
        let application: HBApplication
        
        init(application: HBApplication) {
            self.databases = Databases(threadPool: application.threadPool, on: application.eventLoopGroup)
            self.migrations = .init()
            self.application = application
        }
        
        func shutdown() {
            self.databases.shutdown()
        }

        public var migrator: Migrator {
            Migrator(
                databases: self.databases,
                migrations: self.migrations,
                logger: self.application.logger,
                on: self.application.eventLoopGroup.next()
            )
        }

        public func migrate() -> EventLoopFuture<Void> {
            self.migrator.setupIfNeeded().flatMap {
                self.migrator.prepareBatch()
            }
        }

        public func revert() -> EventLoopFuture<Void> {
            self.migrator.setupIfNeeded().flatMap {
                self.migrator.revertAllBatches()
            }
        }
    }
    
    var fluent: Fluent {
        get { self.extensions.get(\.fluent) }
        set {
            self.extensions.set(\.fluent, value: newValue) { fluent in
                fluent.shutdown()
            }
        }
    }
}
