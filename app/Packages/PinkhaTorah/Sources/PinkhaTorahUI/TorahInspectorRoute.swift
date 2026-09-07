import Foundation
import PinkhaTorahCore

public enum TorahInspectorRoute: Hashable, Sendable {
    case segment(TorahTextSegment)
    case source(TorahInspectorSelection)
}
