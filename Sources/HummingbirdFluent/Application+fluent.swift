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
import Hummingbird
import Logging
import NIOCore

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
        self.fluent.db(id, on: self.eventLoopGroup.any())
    }

    /// Fluent interface object
    public var fluent: HBFluent {
        get { self.extensions.get(\.fluent) }
        set {
            self.extensions.set(\.fluent, value: newValue) { fluent in
                fluent.shutdown()
            }
        }
    }
}
