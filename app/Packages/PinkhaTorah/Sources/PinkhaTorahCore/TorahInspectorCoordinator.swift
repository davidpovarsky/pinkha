import Foundation
import Observation

@MainActor @Observable
public final class TorahInspectorCoordinator {
    public var selection: TorahInspectorSelection?

    public init(selection: TorahInspectorSelection? = nil) {
        self.selection = selection
    }

    public var isPresented: Bool {
        selection != nil
    }

    public func open(_ selection: TorahInspectorSelection) {
        self.selection = selection
    }

    public func close() {
        selection = nil
    }
}
