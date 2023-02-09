//===----------------------------------------------------------------------===//
//
// This source file is part of the Hummingbird server framework project
//
// Copyright (c) 2022 the Hummingbird authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See hummingbird/CONTRIBUTORS.txt for the list of Hummingbird authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

#if compiler(>=5.5.2) && canImport(_Concurrency)

import Hummingbird

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

#endif // compiler(>=5.5.2) && canImport(_Concurrency)
