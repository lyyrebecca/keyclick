import AppKit
import Combine
import ServiceManagement
import ApplicationServices
import KeyClickCore

let keyClickShowSettingsNotification = Notification.Name("com.beka.keyclick.showSettings")

struct TargetApplicationChoice: Identifiable {
    let bundleIdentifier: String
    let name: String
    var id: String { bundleIdentifier }
}

@MainActor
final class AppController: NSObject, ObservableObject {
    @Published private(set) var settings: AppSettings
    @Published private(set) var mode: OverlayMode = .standby
    @Published private(set) var statusMessage = "准备就绪"
    @Published private(set) var accessibilityGranted = false
    @Published private(set) var inputMonitoringGranted = false

    private let store: ProfileStore
    private let tracker = WindowTracking()
    private let keyboard = KeyboardCapture()
    private let injector = ClickInjector()
    private let overlay = OverlayController()
    private var state = InteractionState()
    private var currentSnapshot: WindowSnapshot?
    private var editRequested = false
    private var settingsWindow: SettingsWindowController?
    private var statusItem: NSStatusItem?

    override init() {
        store = ProfileStore()
        settings = .empty
        super.init()
        keyboard.onToggle = { [weak self] in self?.toggleArmed() }
        keyboard.onEscape = { [weak self] in
            guard let self else { return }
            if self.mode == .editing { self.finishEditing() }
            else { self.disarm(message: "已退出点击模式") }
        }
        keyboard.onMarker = { [weak self] id in self?.trigger(markerID: id) }
        keyboard.onAvailabilityChanged = { [weak self] available in
            guard let self else { return }
            self.inputMonitoringGranted = available && CGPreflightListenEventAccess()
            if !available { self.statusMessage = "未获得输入监控权限，无法监听按键" }
            self.updateMenu()
        }
        tracker.onWindowChanged = { [weak self] snapshot in self?.received(snapshot: snapshot) }
        tracker.onTargetLost = { [weak self] in self?.targetLost() }
        overlay.setDragHandler { [weak self] id, point in self?.move(markerID: id, to: point) }
    }

    func launch() {
        let loaded = store.load()
        settings = loaded.settings
        unstackLegacyMarkersIfNeeded()
        if loaded.settings != settings { persist() }
        accessibilityGranted = AXIsProcessTrusted()
        inputMonitoringGranted = CGPreflightListenEventAccess()
        if loaded.recoveredFromCorruption { statusMessage = "已备份损坏配置，并创建新的空配置" }
        installStatusItem()
        keyboard.start()
        applyLaunchAtLoginIfNeeded()
        configureTracking()
        updateMenu()
        if settings.profiles.isEmpty { statusMessage = "首次使用：先授予权限，再从菜单栏绑定前台背词软件" }
        DistributedNotificationCenter.default().addObserver(
            forName: keyClickShowSettingsNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.openSettings() }
        }
        updateMenu()
        DispatchQueue.main.async { [weak self] in self?.openSettings() }
    }

    var activeProfile: ClickProfile? {
        guard let id = settings.activeProfileID else { return nil }
        return settings.profiles.first(where: { $0.id == id })
    }

    var availableTargetApplications: [TargetApplicationChoice] {
        NSWorkspace.shared.runningApplications.compactMap { app in
            guard !app.isTerminated,
                  let bundle = app.bundleIdentifier,
                  bundle != Bundle.main.bundleIdentifier,
                  bundle != "com.openai.codex" else { return nil }
            return TargetApplicationChoice(bundleIdentifier: bundle, name: app.localizedName ?? bundle)
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func requestAccessibility() {
        let options = ["AXTrustedCheckOptionPrompt" as CFString: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        statusMessage = "请在系统设置中允许“键点 KeyClick”控制电脑"
        refreshPermissions()
    }

    func openAccessibilitySettings() {
        requestAccessibility()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
        statusMessage = "已打开“辅助功能”设置：打开 KeyClick 开关后，返回这里重新检查权限"
    }

    func requestInputMonitoring() {
        _ = CGRequestListenEventAccess()
        statusMessage = "请在系统设置中允许“键点 KeyClick”监听输入"
        refreshPermissions()
    }

    func openInputMonitoringSettings() {
        requestInputMonitoring()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
            NSWorkspace.shared.open(url)
        }
        statusMessage = "已打开“输入监控”设置：打开 KeyClick 开关后，返回这里重新检查权限"
    }

    func refreshPermissions() {
        accessibilityGranted = AXIsProcessTrusted()
        // Test the permission by recreating the same event tap used to catch
        // keys, not solely by a preflight query which can lag behind TCC.
        keyboard.restart()
        inputMonitoringGranted = CGPreflightListenEventAccess()
        configureTracking()
        if accessibilityGranted && inputMonitoringGranted {
            statusMessage = "权限已可用：现在可显示并拖动浮标"
        } else if !accessibilityGranted && !inputMonitoringGranted {
            statusMessage = "仍未检测到两项权限；关闭并重新打开 KeyClick 后再检查"
        } else if !accessibilityGranted {
            statusMessage = "输入监控已可用；仍需开启辅助功能权限"
        } else {
            statusMessage = "辅助功能已可用；仍需开启输入监控权限"
        }
        updateMenu()
    }

    func bindCurrentFrontApplication() {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.bundleIdentifier != Bundle.main.bundleIdentifier,
              let bundle = app.bundleIdentifier else {
            statusMessage = "请先切换到要绑定的背词软件窗口"
            updateMenu(); return
        }
        bindApplication(bundleIdentifier: bundle, displayName: app.localizedName ?? "目标应用")
    }

    func bindApplication(bundleIdentifier: String, displayName: String) {
        let existingCount = settings.profiles.filter { $0.targetBundleIdentifier == bundleIdentifier }.count
        var profile = ClickProfile(name: existingCount == 0 ? displayName : "\(displayName) 布局 \(existingCount + 1)", targetBundleIdentifier: bundleIdentifier)
        for _ in 0..<4 { _ = ProfileLogic.addMarker(to: &profile) }
        settings.profiles.append(profile)
        settings.activeProfileID = profile.id
        persist()
        configureTracking()
        statusMessage = "已保存 \(displayName) 的配置；切回该应用后即可编辑并拖动浮标"
        updateMenu()
    }

    func duplicateActiveProfile() {
        guard var profile = activeProfile else { return }
        profile.id = UUID()
        profile.name += " 副本"
        profile.createdAt = Date(); profile.updatedAt = Date()
        settings.profiles.append(profile)
        settings.activeProfileID = profile.id
        persist(); configureTracking(); updateMenu()
    }

    func deleteActiveProfile() {
        guard let id = settings.activeProfileID else { return }
        disarm(message: "已删除配置")
        settings.profiles.removeAll { $0.id == id }
        settings.activeProfileID = settings.profiles.first?.id
        persist(); configureTracking(); updateMenu()
    }

    func activateProfile(_ id: UUID?) {
        disarm(message: "已切换配置")
        settings.activeProfileID = id
        persist(); configureTracking(); updateMenu()
    }

    func updateProfileName(_ name: String) {
        mutateActiveProfile { $0.name = name }
    }

    func addMarker() {
        mutateActiveProfile { profile in
            if ProfileLogic.addMarker(to: &profile) == nil { self.statusMessage = "已用完 \(KeyMap.ordered.count) 个可用浮标按键" }
        }
    }

    func removeMarker(_ id: UUID) {
        mutateActiveProfile { profile in
            profile.markers.removeAll { $0.id == id }
            for index in profile.markers.indices { profile.markers[index].order = index }
        }
    }

    func changeMarkerKey(_ id: UUID, to keyCode: UInt16) {
        guard var profile = activeProfile,
              let index = profile.markers.firstIndex(where: { $0.id == id }),
              !profile.markers.contains(where: { $0.id != id && $0.keyCode == keyCode }),
              let label = KeyMap.label(for: keyCode) else {
            statusMessage = "该按键已被此配置中的其他浮标使用"
            updateMenu(); return
        }
        profile.markers[index].keyCode = keyCode
        profile.markers[index].label = label
        replaceActive(profile)
    }

    func changeMarkerColor(_ id: UUID, to hex: String) {
        mutateActiveProfile { profile in
            guard let index = profile.markers.firstIndex(where: { $0.id == id }) else { return }
            profile.markers[index].colorHex = hex
        }
    }

    func setOpacity(_ opacity: Double) {
        settings.markerOpacity = opacity
        persist(); refreshOverlay(); updateMenu()
    }

    func setMarkerSize(_ size: Double) {
        settings.markerSize = size
        persist(); refreshOverlay(); updateMenu()
    }

    func setShortcut(_ shortcut: ToggleShortcut) {
        settings.toggleShortcut = shortcut
        reconfigureKeyboard(); persist(); updateMenu()
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        settings.launchAtLogin = enabled
        if #available(macOS 13.0, *) {
            do {
                if enabled { try SMAppService.mainApp.register() }
                else { try SMAppService.mainApp.unregister() }
                statusMessage = enabled ? "已开启开机启动" : "已关闭开机启动"
            } catch {
                settings.launchAtLogin = false
                statusMessage = "开机启动设置失败：\(error.localizedDescription)"
            }
        }
        persist(); updateMenu()
    }

    func beginEditing() {
        guard let profile = activeProfile else { statusMessage = "请先绑定一个目标应用"; updateMenu(); return }
        guard accessibilityGranted else {
            statusMessage = "浮标需要“辅助功能”权限；请先点“前往授权”打开 KeyClick 开关"
            updateMenu(); return
        }
        guard currentSnapshot != nil else {
            guard let target = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == profile.targetBundleIdentifier }) else {
                statusMessage = "目标应用未运行，请先打开 \(profile.name)"
                updateMenu(); return
            }
            editRequested = true
            statusMessage = "正在切换到 \(profile.name)，随后自动显示可拖动浮标"
            updateMenu()
            target.activate(options: [])
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(250)) { [weak self] in self?.tracker.refresh() }
            return
        }
        enterEditing()
    }

    private func enterEditing() {
        disarm(message: "编辑浮标")
        state.beginEditing(); mode = state.mode
        refreshOverlay(); updateMenu()
    }

    func finishEditing() {
        guard mode == .editing else { return }
        state.finishEditing(); mode = state.mode
        reconfigureKeyboard()
        // The old implementation merely changed the panel to a translucent
        // state.  It left the settings window in front, which looked like the
        // completion button had done nothing.  Completion now returns focus to
        // the configured target and only then redraws the standby overlay.
        overlay.hide()
        currentSnapshot = nil
        guard let profile = activeProfile,
              let target = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == profile.targetBundleIdentifier }) else {
            statusMessage = "已完成编辑；目标应用未运行"
            updateMenu()
            return
        }
        statusMessage = "已完成编辑，正在返回 \(profile.name)"
        updateMenu()
        target.activate(options: [])
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(250)) { [weak self] in self?.tracker.refresh() }
    }

    func toggleArmed() {
        if mode == .armed { disarm(message: "已退出点击模式"); return }
        guard accessibilityGranted, inputMonitoringGranted,
              let profile = activeProfile, !profile.markers.isEmpty, currentSnapshot != nil else {
            statusMessage = "需先授予权限、绑定并打开目标窗口"; updateMenu(); return
        }
        state.arm(canArm: true); mode = state.mode
        reconfigureKeyboard(); refreshOverlay()
        statusMessage = "点击模式已开启：直接按浮标数字或字母；Esc 退出"
        updateMenu()
    }

    func disarm(message: String? = nil) {
        state.disarm(); mode = state.mode
        reconfigureKeyboard(); refreshOverlay()
        if let message { statusMessage = message }
        updateMenu()
    }

    func openSettings() {
        if settingsWindow == nil { settingsWindow = SettingsWindowController(controller: self) }
        settingsWindow?.showWindow(nil)
        settingsWindow?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// NSWorkspace activation notifications are best-effort.  AppKit's own
    /// activation callback is the authoritative backstop when the user opens
    /// KeyClick from the Dock: stop interception and remove the target overlay
    /// before the settings window is made visible.
    func hostApplicationBecameActive() {
        // Editing is intentionally left intact here: the user may bring the
        // control panel forward specifically to press “完成编辑”.  Armed mode,
        // by contrast, must always be stopped before settings takes focus.
        guard mode == .armed else { return }
        state.disarm()
        mode = state.mode
        currentSnapshot = nil
        reconfigureKeyboard()
        overlay.hide()
        statusMessage = "已回到键点设置，点击模式已退出"
        updateMenu()
    }

    /// Repair only the old-build pattern in which every marker was created at
    /// 50/50.  Layouts that the user has moved are left untouched.
    private func unstackLegacyMarkersIfNeeded() {
        for index in settings.profiles.indices {
            let markers = settings.profiles[index].markers
            guard markers.count > 1, markers.allSatisfy({ $0.position == .center }) else { continue }
            var profile = settings.profiles[index]
            let original = profile.markers
            profile.markers.removeAll()
            for marker in original {
                guard var replacement = ProfileLogic.addMarker(to: &profile) else { continue }
                replacement.id = marker.id
                replacement.keyCode = marker.keyCode
                replacement.label = marker.label
                replacement.colorHex = marker.colorHex
                replacement.order = marker.order
                profile.markers[profile.markers.count - 1] = replacement
            }
            settings.profiles[index] = profile
        }
    }

    private func received(snapshot: WindowSnapshot) {
        currentSnapshot = snapshot
        if editRequested {
            editRequested = false
            enterEditing()
            return
        }
        refreshOverlay()
        updateMenu()
    }

    private func targetLost() {
        currentSnapshot = nil
        state.targetLost(); mode = state.mode
        reconfigureKeyboard()
        overlay.hide()
        updateMenu()
    }

    private func trigger(markerID: UUID) {
        guard mode == .armed, let profile = activeProfile, let snapshot = currentSnapshot,
              let marker = profile.markers.first(where: { $0.id == markerID }) else { return }
        injector.click(at: ProfileLogic.point(in: snapshot.frame, normalized: marker.position))
    }

    private func move(markerID: UUID, to point: NormalizedPoint) {
        mutateActiveProfile { profile in
            guard let index = profile.markers.firstIndex(where: { $0.id == markerID }) else { return }
            profile.markers[index].position = point
        }
    }

    private func configureTracking() {
        guard let profile = activeProfile else { tracker.stop(); targetLost(); return }
        tracker.track(profile: profile)
    }

    private func refreshOverlay() {
        guard let snapshot = currentSnapshot, let profile = activeProfile else { overlay.hide(); return }
        overlay.show(snapshot: snapshot, profile: profile, mode: mode, settings: settings)
    }

    private func reconfigureKeyboard() {
        keyboard.configure(armed: mode == .armed,
                           escapeEnabled: mode == .armed || mode == .editing,
                           shortcut: settings.toggleShortcut,
                           markers: activeProfile?.markers ?? [])
    }

    private func mutateActiveProfile(_ mutate: (inout ClickProfile) -> Void) {
        guard var profile = activeProfile else { return }
        mutate(&profile)
        profile.updatedAt = Date()
        replaceActive(profile)
    }

    private func replaceActive(_ profile: ClickProfile) {
        guard let index = settings.profiles.firstIndex(where: { $0.id == profile.id }) else { return }
        settings.profiles[index] = profile
        persist(); reconfigureKeyboard(); refreshOverlay(); updateMenu()
    }

    private func persist() {
        do { try store.save(settings) }
        catch { statusMessage = "保存配置失败：\(error.localizedDescription)" }
    }

    private func applyLaunchAtLoginIfNeeded() {
        guard settings.launchAtLogin, #available(macOS 13.0, *) else { return }
        try? SMAppService.mainApp.register()
    }

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "⌁"
        item.button?.toolTip = "键点 KeyClick"
        statusItem = item
    }

    private func updateMenu() {
        guard let statusItem else { return }
        statusItem.button?.image = nil
        statusItem.button?.title = mode == .armed ? "⚡︎" : (mode == .editing ? "✥" : "⌁")
        let menu = NSMenu()
        menu.addItem(withTitle: "键点 KeyClick — \(modeTitle)", action: nil, keyEquivalent: "")
        let status = menu.addItem(withTitle: statusMessage, action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(.separator())
        menu.addItem(withTitle: mode == .armed ? "退出点击模式" : "开启点击模式 (\(settings.toggleShortcut.displayName))", action: #selector(statusToggle), keyEquivalent: "")
        menu.addItem(withTitle: mode == .editing ? "完成浮标编辑" : "编辑浮标", action: #selector(statusEdit), keyEquivalent: "")
        menu.addItem(withTitle: "绑定当前前台应用为新配置", action: #selector(statusBind), keyEquivalent: "")
        let profilesMenu = NSMenu(title: "配置")
        for profile in settings.profiles {
            let item = NSMenuItem(title: profile.name, action: #selector(statusSelectProfile(_:)), keyEquivalent: "")
            item.representedObject = profile.id.uuidString
            item.state = profile.id == settings.activeProfileID ? .on : .off
            profilesMenu.addItem(item)
        }
        let profilesItem = NSMenuItem(title: "切换配置", action: nil, keyEquivalent: "")
        profilesItem.submenu = profilesMenu
        menu.addItem(profilesItem)
        menu.addItem(.separator())
        menu.addItem(withTitle: "打开设置…", action: #selector(statusSettings), keyEquivalent: ",")
        menu.addItem(withTitle: "检查辅助功能权限", action: #selector(statusAccessibility), keyEquivalent: "")
        menu.addItem(withTitle: "检查输入监控权限", action: #selector(statusInput), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出键点", action: #selector(statusQuit), keyEquivalent: "q")
        for item in menu.items { item.target = self }
        statusItem.menu = menu
    }

    private var modeTitle: String {
        switch mode { case .standby: "待机"; case .editing: "编辑中"; case .armed: "点击模式" }
    }

    @objc private func statusToggle() { toggleArmed() }
    @objc private func statusEdit() { mode == .editing ? finishEditing() : beginEditing() }
    @objc private func statusBind() { bindCurrentFrontApplication() }
    @objc private func statusSettings() { openSettings() }
    @objc private func statusAccessibility() { requestAccessibility() }
    @objc private func statusInput() { requestInputMonitoring() }
    @objc private func statusQuit() { NSApp.terminate(nil) }
    @objc private func statusSelectProfile(_ sender: NSMenuItem) {
        guard let text = sender.representedObject as? String, let id = UUID(uuidString: text) else { return }
        activateProfile(id)
    }
}
