import FluentKit
import Hummingbird

extension HBRequest {
    public var db: Database {
        self.db(nil)
    }

    public func db(_ id: DatabaseID?) -> Database {
        self.application.db(id)
    }
}

