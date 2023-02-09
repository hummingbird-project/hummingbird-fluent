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

extension HBFluent {
    public struct History {
        let application: HBApplication

        public var enabled: Bool {
            self.application.extensions.get(\.fluent.history.enabled) ?? false
        }

        public var history: QueryHistory? {
            self.application.extensions.get(\.fluent.history.history)
        }

        public func start() {
            self.application.extensions.set(\.fluent.history.enabled, value: true)
            self.application.extensions.set(\.fluent.history.history, value: .init())
        }

        public func stop() {
            self.application.extensions.set(\.fluent.history.enabled, value: false)
        }

        public func clear() {
            self.application.extensions.set(\.fluent.history.history, value: .init())
        }
    }

    public var history: History {
        return .init(application: self.application)
    }
}
