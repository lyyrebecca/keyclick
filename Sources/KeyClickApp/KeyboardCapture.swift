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
    /// A listen-only Quartz tap is a last-resort capture path.  It can still
    /// trigger a marker, but macOS will deliver the original keystroke to the
    /// target app because this tap is not allowed to suppress it.
    private var tapIsListenOnly = false
    private var armed = false
    private var escapeEnabled = false
    private var shortcut: ToggleShortcut = .controlOptionK
    private var markerByCode: [UInt16: UUID] = [:]

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
            // Some macOS/TCC combinations reject an intercepting tap although
            // they permit observing the exact same session event stream.
            // Prefer this to losing every mapping (including letter keys such
            // as R) just because interception is unavailable.
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

        lock.lock()
        let state = (armed, escapeEnabled, shortcut, markerByCode[keyCode])
        lock.unlock()

        let mustPassThrough = tapIsListenOnly
        if matchesToggle(keyCode: keyCode, flags: event.flags, shortcut: state.2) {
            if type == .keyDown && !repeatPress { DispatchQueue.main.async { self.onToggle?() } }
            return mustPassThrough ? Unmanaged.passUnretained(event) : nil
        }
        if state.1 && keyCode == 53 { // Escape
            if type == .keyDown && !repeatPress { DispatchQueue.main.async { self.onEscape?() } }
            return mustPassThrough ? Unmanaged.passUnretained(event) : nil
        }
        if state.0, let markerID = state.3 {
            if type == .keyDown && !repeatPress {
                DispatchQueue.main.async { self.onMarker?(markerID) }
            }
            return mustPassThrough ? Unmanaged.passUnretained(event) : nil
        }
        return Unmanaged.passUnretained(event)
    }

    private func installCompatibilityMonitor() {
        compatibilityMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            self?.handleCompatibility(event)
        }
        DispatchQueue.main.async { self.onCompatibilityMonitorChanged?(self.compatibilityMonitor != nil) }
    }

    private func handleCompatibility(_ event: NSEvent) {
        let keyCode = UInt16(event.keyCode)
        let repeatPress = event.isARepeat
        lock.lock()
        let state = (armed, escapeEnabled, shortcut, markerByCode[keyCode])
        lock.unlock()

        let flags = CGEventFlags(rawValue: UInt64(event.modifierFlags.rawValue))
        if matchesToggle(keyCode: keyCode, flags: flags, shortcut: state.2) {
            if !repeatPress { DispatchQueue.main.async { self.onToggle?() } }
        } else if state.1 && keyCode == 53 {
            if !repeatPress { DispatchQueue.main.async { self.onEscape?() } }
        } else if state.0, let markerID = state.3, !repeatPress {
            DispatchQueue.main.async { self.onMarker?(markerID) }
        }
    }

    private func matchesToggle(keyCode: UInt16, flags: CGEventFlags, shortcut: ToggleShortcut) -> Bool {
        guard keyCode == shortcut.keyCode else { return false }
        let required: CGEventFlags = [.maskControl, .maskAlternate]
        return flags.contains(required) && !flags.contains(.maskCommand)
    }
}
