import Foundation
import ApplicationServices

final class ClickInjector {
    @discardableResult
    func click(at point: CGPoint) -> Bool {
        guard point.x.isFinite, point.y.isFinite else { return false }
        let original = CGEvent(source: nil)?.location
        guard let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left),
              let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left) else { return false }
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        if let original {
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(30)) {
                CGWarpMouseCursorPosition(original)
            }
        }
        return true
    }
}
