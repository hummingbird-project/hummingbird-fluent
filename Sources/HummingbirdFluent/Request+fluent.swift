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

extension HBRequest {
    /// Get default database
    public var db: Database {
        self.db(nil)
    }

    /// Get database with ID
    /// - Parameter id: database id
    /// - Returns: database
    public func db(_ id: DatabaseID?) -> Database {
        self.application.fluent.databases
            .database(
                id,
                logger: self.logger,
                on: self.eventLoop,
                history: self.application.fluent.history.enabled ? self.application.fluent.history.history : nil
            )!
    }

    /// Object to attach fluent related structures (currently unused)
    public struct Fluent {
        let request: HBRequest
    }

    public var fluent: Fluent { return .init(request: self) }
}
