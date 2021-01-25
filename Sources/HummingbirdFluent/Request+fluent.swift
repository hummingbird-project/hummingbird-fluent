import FluentKit
import Hummingbird

extension HBRequest {
    /// Get default database
    public var db: Database {
        self.db(nil)
    }

    /// Get database with ID
    /// - Parameter id: database id
    /// - Returns: database
    public func db(_ id: DatabaseID?) -> Database {
        self.application.db(id)
    }
}

