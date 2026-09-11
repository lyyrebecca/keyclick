import Foundation
import AppKit
import ApplicationServices
import KeyClickCore

final class KeyboardCapture: @unchecked Sendable {
    var onToggle: (() -> Void)?
    var onEscape: (() -> Void)?
    var onMarker: ((UUID) -> Void)?
    var onAvailabilityChanged: ((Bool) -> Void)?
    /// A global monitor cannot swallow mapped keys, but allows users with a
    /// stale event-tap permission result to attempt the feature instead of
    /// being blocked by the setup screen.
    var onCompatibilityMonitorChanged: ((Bool) -> Void)?

    private let lock = NSLock()
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var compatibilityMonitor: Any?
    /// A second, observe-only stream runs alongside an intercepting tap.  This
    /// is intentional redundancy: some target apps consume a key before a
    /// Quartz tap has been re-enabled after an input-source transition.  The
    /// short deduplicator below makes the two streams behave as one key press.
    private var redundancyMonitor: Any?
    /// A listen-only Quartz tap is a last-resort capture path.  It can still
    /// trigger a marker, but macOS will deliver the original keystroke to the
    /// target app because this tap is not allowed to suppress it.
    private var tapIsListenOnly = false
    private var armed = false
    private var escapeEnabled = false
    private var shortcut: ToggleShortcut = .controlOptionK
    private var markerByCode: [UInt16: UUID] = [:]
    private var lastDeliveredMarkerPress: (code: UInt16, uptime: TimeInterval)?

    func start() {
        guard tap == nil, compatibilityMonitor == nil else { return }
        let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let capture = Unmanaged<KeyboardCapture>.fromOpaque(refcon).takeUnretainedValue()
            return capture.handle(type: type, event: event)
        }
        let userInfo = Unmanaged.passUnretained(self).toOpaque()
        tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                eventsOfInterest: CGEventMask(mask), callback: callback, userInfo: userInfo)
        if tap == nil {
            tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly,
                                    eventsOfInterest: CGEventMask(mask), callback: callback, userInfo: userInfo)
            tapIsListenOnly = tap != nil
        }
        guard let tap else {
            installCompatibilityMonitor()
            DispatchQueue.main.async { self.onAvailabilityChanged?(false) }
            return
        }
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        installRedundancyMonitor()
        DispatchQueue.main.async { self.onCompatibilityMonitorChanged?(self.tapIsListenOnly) }
        DispatchQueue.main.async { self.onAvailabilityChanged?(true) }
    }

    func stop() {
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        source = nil
        tap = nil
        tapIsListenOnly = false
        if let compatibilityMonitor { NSEvent.removeMonitor(compatibilityMonitor) }
        compatibilityMonitor = nil
        if let redundancyMonitor { NSEvent.removeMonitor(redundancyMonitor) }
        redundancyMonitor = nil
        lock.lock(); lastDeliveredMarkerPress = nil; lock.unlock()
    }

    /// A grant made in System Settings while the app is running is only
    /// reflected reliably after recreating the actual CGEvent tap.
    func restart() {
        stop()
        start()
    }

    func configure(armed: Bool, escapeEnabled: Bool, shortcut: ToggleShortcut, markers: [MarkerBinding]) {
        lock.lock(); defer { lock.unlock() }
        self.armed = armed
        self.escapeEnabled = escapeEnabled
        self.shortcut = shortcut
        markerByCode.removeAll()
        for marker in markers {
            for code in KeyMap.aliases(for: marker.keyCode) {
                markerByCode[code] = marker.id
            }
        }
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        guard type == .keyDown || type == .keyUp else { return Unmanaged.passUnretained(event) }
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let repeatPress = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
        let state = state(for: keyCode)

        let mustPassThrough = tapIsListenOnly
        if matchesToggle(keyCode: keyCode, flags: event.flags, shortcut: state.shortcut) {
            if type == .keyDown && !repeatPress { DispatchQueue.main.async { self.onToggle?() } }
            return mustPassThrough ? Unmanaged.passUnretained(event) : nil
        }
        if state.escapeEnabled && keyCode == 53 {
            if type == .keyDown && !repeatPress { DispatchQueue.main.async { self.onEscape?() } }
            return mustPassThrough ? Unmanaged.passUnretained(event) : nil
        }
        if state.armed, let markerID = state.markerID {
            deliver(markerID: markerID, keyCode: keyCode, keyDown: type == .keyDown, repeatPress: repeatPress)
            return mustPassThrough ? Unmanaged.passUnretained(event) : nil
        }
        return Unmanaged.passUnretained(event)
    }

    private func installCompatibilityMonitor() {
        compatibilityMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            self?.handleMonitor(event)
        }
        DispatchQueue.main.async { self.onCompatibilityMonitorChanged?(self.compatibilityMonitor != nil) }
    }

    private func installRedundancyMonitor() {
        guard redundancyMonitor == nil else { return }
        redundancyMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            self?.handleMonitor(event)
        }
    }

    private func handleMonitor(_ event: NSEvent) {
        let keyCode = UInt16(event.keyCode)
        let repeatPress = event.isARepeat
        let state = state(for: keyCode)
        let flags = CGEventFlags(rawValue: UInt64(event.modifierFlags.rawValue))
        if matchesToggle(keyCode: keyCode, flags: flags, shortcut: state.shortcut) {
            if !repeatPress { DispatchQueue.main.async { self.onToggle?() } }
        } else if state.escapeEnabled && keyCode == 53 {
            if !repeatPress { DispatchQueue.main.async { self.onEscape?() } }
        } else if state.armed, let markerID = state.markerID {
            deliver(markerID: markerID, keyCode: keyCode, keyDown: true, repeatPress: repeatPress)
        }
    }

    private func state(for keyCode: UInt16) -> (armed: Bool, escapeEnabled: Bool, shortcut: ToggleShortcut, markerID: UUID?) {
        lock.lock(); defer { lock.unlock() }
        return (armed, escapeEnabled, shortcut, markerByCode[keyCode])
    }

    private func deliver(markerID: UUID, keyCode: UInt16, keyDown: Bool, repeatPress: Bool) {
        guard keyDown, !repeatPress, claimMarkerPress(keyCode) else { return }
        DispatchQueue.main.async { self.onMarker?(markerID) }
    }

    /// The event-tap and NSEvent monitor can both see a single physical press.
    /// Keep only one delivery, while allowing deliberately repeated presses.
    private func claimMarkerPress(_ keyCode: UInt16) -> Bool {
        let now = ProcessInfo.processInfo.systemUptime
        lock.lock(); defer { lock.unlock() }
        if let last = lastDeliveredMarkerPress, last.code == keyCode, now - last.uptime < 0.075 {
            return false
        }
        lastDeliveredMarkerPress = (keyCode, now)
        return true
    }

    private func matchesToggle(keyCode: UInt16, flags: CGEventFlags, shortcut: ToggleShortcut) -> Bool {
        guard keyCode == shortcut.keyCode else { return false }
        let required: CGEventFlags = [.maskControl, .maskAlternate]
        return flags.contains(required) && !flags.contains(.maskCommand)
    }
}
