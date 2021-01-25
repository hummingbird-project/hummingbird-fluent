import FluentKit
import Hummingbird

extension HBApplication.Fluent {
    public struct History {
        let application: HBApplication

        public var enabled: Bool {
            application.extensions.get(\.fluent.history.enabled) ?? false
        }

        public var history: QueryHistory? {
            application.extensions.get(\.fluent.history.history)
        }

        public func start() {
            application.extensions.set(\.fluent.history.enabled, value: true)
            application.extensions.set(\.fluent.history.history, value: .init())
        }

        public func stop() {
            application.extensions.set(\.fluent.history.enabled, value: false)
        }

        public func clear() {
            application.extensions.set(\.fluent.history.history, value: .init())
        }
    }

    public var history: History {
        return .init(application: self.application)
    }
}
