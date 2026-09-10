import Foundation
import ApplicationServices

final class ClickInjector {
    func click(at point: CGPoint) {
        guard point.x.isFinite, point.y.isFinite else { return }
        let original = CGEvent(source: nil)?.location
        guard let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left),
              let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left) else { return }
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        guard let original else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(30)) {
            CGWarpMouseCursorPosition(original)
        }
    }
}
