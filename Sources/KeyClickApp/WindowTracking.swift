import AppKit
import ApplicationServices
import KeyClickCore

struct WindowSnapshot {
    let bundleIdentifier: String
    let pid: pid_t
    /// Quartz/Accessibility coordinates (upper-left origin), used for clicks.
    let frame: CGRect
    /// AppKit coordinates (lower-left origin), used for the overlay panel.
    let overlayFrame: CGRect
    let title: String
}

@MainActor
final class WindowTracking: NSObject {
    var onWindowChanged: ((WindowSnapshot) -> Void)?
    var onTargetLost: (() -> Void)?

    private var bundleIdentifier: String?
    private var observer: AXObserver?
    private var workspaceObserver: NSObjectProtocol?
    private var observedPID: pid_t = 0
    private var observedWindow: AXUIElement?

    func track(profile: ClickProfile) {
        stop()
        bundleIdentifier = profile.targetBundleIdentifier
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        refresh()
    }

    func stop() {
        if let workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(workspaceObserver)
        }
        workspaceObserver = nil
        if let observer {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        }
        observer = nil
        observedPID = 0
        observedWindow = nil
    }

    func refresh() {
        guard AXIsProcessTrusted(),
              let bundleIdentifier,
              let app = NSWorkspace.shared.frontmostApplication,
              app.bundleIdentifier == bundleIdentifier,
              !app.isTerminated else {
            onTargetLost?()
            return
        }
        guard let (snapshot, window) = snapshot(for: app) else {
            onTargetLost?()
            return
        }
        installObserverIfNeeded(for: app.processIdentifier, window: window)
        onWindowChanged?(snapshot)
    }

    private func snapshot(for app: NSRunningApplication) -> (WindowSnapshot, AXUIElement)? {
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &raw) == .success,
              let window = raw else { return nil }
        let windowElement = window as! AXUIElement

        var minimizedRaw: CFTypeRef?
        if AXUIElementCopyAttributeValue(windowElement, kAXMinimizedAttribute as CFString, &minimizedRaw) == .success,
           let minimized = minimizedRaw as? Bool, minimized {
            return nil
        }

        var position = CGPoint.zero
        var size = CGSize.zero
        var positionRaw: CFTypeRef?
        var sizeRaw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(windowElement, kAXPositionAttribute as CFString, &positionRaw) == .success,
              AXUIElementCopyAttributeValue(windowElement, kAXSizeAttribute as CFString, &sizeRaw) == .success,
              let positionRaw, let sizeRaw else {
            return nil
        }
        let positionValue = positionRaw as! AXValue
        let sizeValue = sizeRaw as! AXValue
        guard AXValueGetValue(positionValue, .cgPoint, &position),
              AXValueGetValue(sizeValue, .cgSize, &size), size.width > 1, size.height > 1 else { return nil }
        let frame = CGRect(origin: position, size: size)
        let overlayFrame = appKitFrame(forAccessibilityFrame: frame)

        var title = app.localizedName ?? app.bundleIdentifier ?? "目标窗口"
        var titleRaw: CFTypeRef?
        if AXUIElementCopyAttributeValue(windowElement, kAXTitleAttribute as CFString, &titleRaw) == .success,
           let windowTitle = titleRaw as? String, !windowTitle.isEmpty {
            title = windowTitle
        }
        return (WindowSnapshot(bundleIdentifier: app.bundleIdentifier ?? "", pid: app.processIdentifier, frame: frame, overlayFrame: overlayFrame, title: title), windowElement)
    }

    /// AX/CG positions grow downward while AppKit positions grow upward.
    /// Resolving both coordinate spaces on the current display also supports
    /// an external display with a non-zero desktop origin.
    private func appKitFrame(forAccessibilityFrame frame: CGRect) -> CGRect {
        let center = CGPoint(x: frame.midX, y: frame.midY)
        let screen = NSScreen.screens.first { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return false }
            return CGDisplayBounds(CGDirectDisplayID(number.uint32Value)).contains(center)
        } ?? NSScreen.main
        guard let screen,
              let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            let height = NSScreen.main?.frame.height ?? 0
            return CGRect(x: frame.minX, y: height - frame.maxY, width: frame.width, height: frame.height)
        }
        let display = CGDisplayBounds(CGDirectDisplayID(number.uint32Value))
        return CGRect(x: screen.frame.minX + (frame.minX - display.minX),
                      y: screen.frame.minY + (display.maxY - frame.maxY),
                      width: frame.width, height: frame.height)
    }

    private func installObserverIfNeeded(for pid: pid_t, window: AXUIElement) {
        let isSameWindow = observedWindow.map { CFEqual($0, window) } ?? false
        guard pid != observedPID || !isSameWindow else { return }
        if let observer {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        }
        var newObserver: AXObserver?
        let result = AXObserverCreate(pid, { _, _, _, refcon in
            guard let refcon else { return }
            let tracker = Unmanaged<WindowTracking>.fromOpaque(refcon).takeUnretainedValue()
            DispatchQueue.main.async { tracker.refresh() }
        }, &newObserver)
        guard result == .success, let newObserver else { return }
        let appElement = AXUIElementCreateApplication(pid)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        [kAXFocusedWindowChangedNotification].forEach { notification in
            _ = AXObserverAddNotification(newObserver, appElement, notification as CFString, refcon)
        }
        [kAXMovedNotification, kAXResizedNotification, kAXWindowMiniaturizedNotification,
         kAXWindowDeminiaturizedNotification, kAXUIElementDestroyedNotification].forEach { notification in
            _ = AXObserverAddNotification(newObserver, window, notification as CFString, refcon)
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(newObserver), .defaultMode)
        observer = newObserver
        observedPID = pid
        observedWindow = window
    }
}
