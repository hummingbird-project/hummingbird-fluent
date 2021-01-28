import FluentKit
import Hummingbird

extension HBApplication.Fluent {
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
