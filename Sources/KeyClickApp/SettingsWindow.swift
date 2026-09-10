import AppKit
import SwiftUI
import KeyClickCore

@MainActor
final class SettingsWindowController: NSWindowController {
    init(controller: AppController) {
        let root = SettingsView(controller: controller)
        let host = NSHostingView(rootView: root)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 500),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.title = "键点 KeyClick 设置"
        window.contentView = host
        window.center()
        super.init(window: window)
        shouldCascadeWindows = true
    }

    required init?(coder: NSCoder) { nil }
}

private struct SettingsView: View {
    @ObservedObject var controller: AppController

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                Text("配置布局").font(.headline)
                List(selection: activeProfileBinding) {
                    ForEach(controller.settings.profiles) { profile in
                        Text(profile.name).tag(profile.id)
                    }
                }
                HStack {
                    targetApplicationMenu
                    Button("复制") { controller.duplicateActiveProfile() }.disabled(controller.activeProfile == nil)
                    Button("删除", role: .destructive) { controller.deleteActiveProfile() }.disabled(controller.activeProfile == nil)
                }
                .buttonStyle(.bordered)
            }
            .frame(width: 205)
            .padding()
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("键点 KeyClick").font(.title2).bold()
                    Text(controller.statusMessage).foregroundStyle(.secondary)
                    permissions
                    if let profile = controller.activeProfile {
                        profileEditor(profile)
                    } else {
                        ContentUnavailableView("尚未绑定应用", systemImage: "scope", description: Text("点击左侧“绑定已运行应用”，直接选择你的背词软件。"))
                    }
                    globalSettings
                }
                .padding(20)
            }
            .frame(maxWidth: .infinity)
        }
        .frame(minWidth: 680, minHeight: 460)
    }

    private var activeProfileBinding: Binding<UUID?> {
        Binding(get: { controller.settings.activeProfileID }, set: { controller.activateProfile($0) })
    }

    @ViewBuilder private var permissions: some View {
        GroupBox("必要权限") {
            VStack(alignment: .leading, spacing: 7) {
                permissionRow("辅助功能：跟踪窗口并执行点击", granted: controller.accessibilityGranted) { controller.openAccessibilitySettings() }
                permissionRow("输入监控：监听并拦截键盘按键", granted: controller.inputMonitoringGranted) { controller.openInputMonitoringSettings() }
                HStack(spacing: 12) {
                    Button("重新检查权限") { controller.refreshPermissions() }
                        .buttonStyle(.link)
                    Button(controller.settings.ignorePermissionStatus ? "停止跳过检测" : "状态不正确？仍然尝试使用") {
                        controller.setIgnorePermissionStatus(!controller.settings.ignorePermissionStatus)
                    }
                    .buttonStyle(.link)
                }
                if controller.settings.ignorePermissionStatus {
                    Label("已跳过授权状态检测：不会把未确认权限显示为已授权，会直接尝试显示浮标、监听按键和执行点击。", systemImage: "exclamationmark.circle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            .padding(.vertical, 3)
        }
    }

    private func permissionRow(_ title: String, granted: Bool, action: @escaping () -> Void) -> some View {
        HStack {
            Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(granted ? .green : .orange)
            Text(title + (!granted && controller.settings.ignorePermissionStatus ? "（未确认，已跳过检测）" : ""))
            Spacer()
            if !granted { Button("前往授权", action: action).buttonStyle(.bordered) }
        }
    }

    @ViewBuilder private var targetApplicationMenu: some View {
        Menu("绑定已运行应用") {
            if controller.availableTargetApplications.isEmpty {
                Text("没有可绑定的已运行应用")
            } else {
                ForEach(controller.availableTargetApplications) { choice in
                    Button(choice.name) {
                        controller.bindApplication(bundleIdentifier: choice.bundleIdentifier, displayName: choice.name)
                    }
                }
            }
        }
        .menuStyle(.borderedButton)
    }

    private func profileEditor(_ profile: ClickProfile) -> some View {
        GroupBox("当前配置") {
            VStack(alignment: .leading, spacing: 10) {
                TextField("名称", text: Binding(get: { controller.activeProfile?.name ?? "" }, set: { controller.updateProfileName($0) }))
                Text("绑定应用：\(profile.targetBundleIdentifier)").font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button(controller.mode == .editing ? "完成编辑" : "显示并拖动浮标") {
                        controller.mode == .editing ? controller.finishEditing() : controller.beginEditing()
                }
                .buttonStyle(.borderedProminent)
                Text("会自动切换到目标应用")
                    .font(.caption).foregroundStyle(.secondary)
                    Button("添加浮标") { controller.addMarker() }.buttonStyle(.bordered)
                }
                Divider()
                ForEach(profile.markers) { marker in
                    HStack(spacing: 10) {
                        Text(marker.label)
                            .font(.system(.body, design: .monospaced).bold())
                            .frame(width: 24, height: 24)
                            .background(Circle().fill(Color(hex: marker.colorHex).opacity(0.8)))
                            .foregroundStyle(.white)
                        Picker("按键", selection: Binding(get: { marker.keyCode }, set: { controller.changeMarkerKey(marker.id, to: $0) })) {
                            ForEach(KeyMap.ordered, id: \.0) { code, label in Text(label).tag(code) }
                        }
                        .labelsHidden().frame(width: 72)
                        Picker("颜色", selection: Binding(get: { marker.colorHex }, set: { controller.changeMarkerColor(marker.id, to: $0) })) {
                            Text("紫").tag("8B5CF6")
                            Text("蓝").tag("2563EB")
                            Text("绿").tag("059669")
                            Text("橙").tag("EA580C")
                            Text("红").tag("DC2626")
                        }
                        .labelsHidden().frame(width: 70)
                        Spacer()
                        Text("x \(Int(marker.position.x * 100))% / y \(Int(marker.position.y * 100))%")
                            .font(.caption).foregroundStyle(.secondary)
                        Button("移除", role: .destructive) { controller.removeMarker(marker.id) }
                            .buttonStyle(.borderless)
                    }
                }
                if profile.markers.isEmpty { Text("至少添加一个浮标后才可进入点击模式。").foregroundStyle(.secondary) }
            }
            .padding(.vertical, 3)
        }
    }

    private var globalSettings: some View {
        GroupBox("全局设置") {
            VStack(alignment: .leading, spacing: 10) {
                Picker("开启/退出点击模式", selection: Binding(get: { controller.settings.toggleShortcut }, set: { controller.setShortcut($0) })) {
                    ForEach(ToggleShortcut.allCases) { shortcut in Text(shortcut.displayName).tag(shortcut) }
                }
                HStack {
                    Text("待机透明度")
                    Slider(value: Binding(get: { controller.settings.markerOpacity }, set: { controller.setOpacity($0) }), in: 0.2...1)
                    Text("\(Int(controller.settings.markerOpacity * 100))%").monospacedDigit().frame(width: 40)
                }
                HStack {
                    Text("浮标大小")
                    Slider(value: Binding(get: { controller.settings.markerSize }, set: { controller.setMarkerSize($0) }), in: 24...56, step: 1)
                    Text("\(Int(controller.settings.markerSize)) pt").monospacedDigit().frame(width: 52)
                }
                Toggle("开机时启动键点", isOn: Binding(get: { controller.settings.launchAtLogin }, set: { controller.setLaunchAtLogin($0) }))
            }
            .padding(.vertical, 3)
        }
    }
}

private extension Color {
    init(hex: String) {
        let value = Int(hex, radix: 16) ?? 0x8B5CF6
        self.init(red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255, blue: Double(value & 0xFF) / 255)
    }
}
