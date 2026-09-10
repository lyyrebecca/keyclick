import Foundation

public struct InteractionState: Equatable, Sendable {
    public private(set) var mode: OverlayMode = .standby

    public init() {}

    public mutating func beginEditing() { mode = .editing }
    public mutating func finishEditing() { mode = .standby }
    public mutating func arm(canArm: Bool) { mode = canArm ? .armed : .standby }
    public mutating func disarm() { mode = .standby }
    public mutating func targetLost() { mode = .standby }
}
