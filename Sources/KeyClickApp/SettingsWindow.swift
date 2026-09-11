import AppKit
import SwiftUI
import KeyClickCore

@MainActor
final class SettingsWindowController: NSWindowController {
    init(controller: AppController) {
        let root = SettingsView(controller: controller)
        let host = NSHostingView(rootView: root)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 560),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.title = "键点 KeyClick"
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = NSColor(red: 32 / 255, green: 32 / 255, blue: 32 / 255, alpha: 1)
        window.contentView = host
        window.center()
        super.init(window: window)
        shouldCascadeWindows = true
    }

    required init?(coder: NSCoder) { nil }
}

private enum ToolPalette {
    static let canvas = Color(red: 32 / 255, green: 32 / 255, blue: 32 / 255)
    static let panel = Color(red: 43 / 255, green: 43 / 255, blue: 43 / 255)
    static let accent = Color(red: 93 / 255, green: 89 / 255, blue: 214 / 255)
    static let muted = Color(red: 202 / 255, green: 202 / 255, blue: 202 / 255)
    static let border = Color.white.opacity(0.62)
}

private struct ToolPanel<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            Text(title).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
            content
        }
        .padding(14)
        .background(ToolPalette.panel)
        .overlay(RoundedRectangle(cornerRadius: 3).stroke(ToolPalette.border, lineWidth: 1))
    }
}

private struct SettingsView: View {
    @ObservedObject var controller: AppController

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle().fill(ToolPalette.border).frame(width: 1)
            ScrollView {
                VStack(alignment: .leading, spacing: 13) {
                    header
                    permissions
                    if let profile = controller.activeProfile {
                        profileEditor(profile)
                    } else {
                        ToolPanel(title: "当前配置") {
                            Text("尚未绑定应用。请在左侧选择已运行的背词软件。")
                                .foregroundStyle(ToolPalette.muted)
                        }
                    }
                    globalSettings
                }
                .padding(18)
            }
            .background(ToolPalette.canvas)
        }
        .frame(minWidth: 720, minHeight: 500)
        .background(ToolPalette.canvas)
        .tint(ToolPalette.accent)
        .preferredColorScheme(.dark)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 11) {
            Text("配置布局").font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
            List(selection: activeProfileBinding) {
                ForEach(controller.settings.profiles) { profile in
                    Text(profile.name).foregroundStyle(.white).tag(profile.id)
                }
            }
            .scrollContentBackground(.hidden)
            .background(ToolPalette.canvas)
            .overlay(Rectangle().stroke(ToolPalette.border, lineWidth: 1))
            HStack(spacing: 7) {
                targetApplicationMenu
                Button("复制") { controller.duplicateActiveProfile() }.disabled(controller.activeProfile == nil)
                Button("删除", role: .destructive) { controller.deleteActiveProfile() }.disabled(controller.activeProfile == nil)
            }
            .buttonStyle(.bordered)
        }
        .padding(15)
        .frame(width: 224)
        .background(ToolPalette.canvas)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("键点 KeyClick").font(.system(size: 23, weight: .bold)).foregroundStyle(.white)
            Text(controller.statusMessage).font(.system(size: 12)).foregroundStyle(ToolPalette.muted)
            Text(controller.lastClickDiagnostic).font(.system(size: 12, design: .monospaced)).foregroundStyle(.cyan)
                .textSelection(.enabled)
        }
    }

    private var activeProfileBinding: Binding<UUID?> {
        Binding(get: { controller.settings.activeProfileID }, set: { controller.activateProfile($0) })
    }

    private var permissions: some View {
        ToolPanel(title: "必要权限") {
            VStack(alignment: .leading, spacing: 8) {
                permissionRow("辅助功能：跟踪窗口并执行点击", granted: controller.accessibilityGranted) { controller.openAccessibilitySettings() }
                permissionRow("输入监控：监听并拦截键盘按键", granted: controller.inputMonitoringGranted) { controller.openInputMonitoringSettings() }
                HStack(spacing: 12) {
                    Button("重新检查权限") { controller.refreshPermissions() }
                    Button(controller.settings.ignorePermissionStatus ? "停止跳过检测" : "状态不正确？仍然尝试使用") {
                        controller.setIgnorePermissionStatus(!controller.settings.ignorePermissionStatus)
                    }
                }
                .buttonStyle(.bordered)
                if controller.settings.ignorePermissionStatus {
                    Text("已跳过授权状态检测：会直接尝试显示浮标、监听按键和执行点击。")
                        .font(.caption).foregroundStyle(.orange)
                }
            }
        }
    }

    private func permissionRow(_ title: String, granted: Bool, action: @escaping () -> Void) -> some View {
        HStack {
            Circle().fill(granted ? .green : .orange).frame(width: 9, height: 9)
            Text(title + (!granted && controller.settings.ignorePermissionStatus ? "（未确认，已跳过检测）" : ""))
                .font(.system(size: 12)).foregroundStyle(.white)
            Spacer()
            if !granted { Button("前往授权", action: action).buttonStyle(.bordered) }
        }
    }

    @ViewBuilder private var targetApplicationMenu: some View {
        Menu("绑定应用") {
            if controller.availableTargetApplications.isEmpty {
                Text("没有可绑定的已运行应用")
            } else {
                ForEach(controller.availableTargetApplications) { choice in
                    Button(choice.name) { controller.bindApplication(bundleIdentifier: choice.bundleIdentifier, displayName: choice.name) }
                }
            }
        }
        .menuStyle(.borderedButton)
    }

    private func profileEditor(_ profile: ClickProfile) -> some View {
        ToolPanel(title: "当前配置") {
            VStack(alignment: .leading, spacing: 10) {
                TextField("名称", text: Binding(get: { controller.activeProfile?.name ?? "" }, set: { controller.updateProfileName($0) }))
                    .textFieldStyle(.roundedBorder)
                Text("绑定应用：\(profile.targetBundleIdentifier)").font(.caption).foregroundStyle(ToolPalette.muted)
                HStack {
                    Button(controller.mode == .editing ? "完成编辑" : "显示并拖动浮标") {
                        controller.mode == .editing ? controller.finishEditing() : controller.beginEditing()
                    }
                    .buttonStyle(.borderedProminent).tint(ToolPalette.accent)
                    Text("会自动切换到目标应用").font(.caption).foregroundStyle(ToolPalette.muted)
                    Button("添加浮标") { controller.addMarker() }.buttonStyle(.bordered)
                }
                Rectangle().fill(ToolPalette.border).frame(height: 1)
                ForEach(profile.markers) { marker in
                    HStack(spacing: 9) {
                        Text(marker.label)
                            .font(.system(.body, design: .monospaced).bold())
                            .frame(width: 25, height: 25)
                            .background(Circle().fill(Color(hex: marker.colorHex).opacity(0.9)))
                            .foregroundStyle(.white)
                        Picker("按键", selection: Binding(get: { marker.keyCode }, set: { controller.changeMarkerKey(marker.id, to: $0) })) {
                            ForEach(KeyMap.ordered, id: \.0) { code, label in Text(label).tag(code) }
                        }
                        .labelsHidden().frame(width: 76)
                        Picker("颜色", selection: Binding(get: { marker.colorHex }, set: { controller.changeMarkerColor(marker.id, to: $0) })) {
                            Text("紫").tag("8B5CF6"); Text("蓝").tag("2563EB"); Text("绿").tag("059669"); Text("橙").tag("EA580C"); Text("红").tag("DC2626")
                        }
                        .labelsHidden().frame(width: 66)
                        Text("x \(Int(marker.position.x * 100))% / y \(Int(marker.position.y * 100))%")
                            .font(.caption).foregroundStyle(ToolPalette.muted)
                        Spacer(minLength: 0)
                        Button("试点") { controller.testMarker(marker.id) }.buttonStyle(.bordered)
                        Button("移除", role: .destructive) { controller.removeMarker(marker.id) }.buttonStyle(.bordered)
                    }
                }
                Text("“试点”会回到目标窗口，并使用与键盘完全相同的坐标和单击方式执行一次点击。")
                    .font(.caption).foregroundStyle(ToolPalette.muted)
                if profile.markers.isEmpty { Text("至少添加一个浮标后才可进入点击模式。").foregroundStyle(ToolPalette.muted) }
            }
        }
    }

    private var globalSettings: some View {
        ToolPanel(title: "全局设置") {
            VStack(alignment: .leading, spacing: 10) {
                Picker("开启/退出点击模式", selection: Binding(get: { controller.settings.toggleShortcut }, set: { controller.setShortcut($0) })) {
                    ForEach(ToggleShortcut.allCases) { shortcut in Text(shortcut.displayName).tag(shortcut) }
                }
                HStack {
                    Text("待机透明度").foregroundStyle(.white)
                    Slider(value: Binding(get: { controller.settings.markerOpacity }, set: { controller.setOpacity($0) }), in: 0.2...1)
                    Text("\(Int(controller.settings.markerOpacity * 100))%").monospacedDigit().frame(width: 42).foregroundStyle(ToolPalette.muted)
                }
                HStack {
                    Text("浮标大小").foregroundStyle(.white)
                    Slider(value: Binding(get: { controller.settings.markerSize }, set: { controller.setMarkerSize($0) }), in: 24...56, step: 1)
                    Text("\(Int(controller.settings.markerSize)) pt").monospacedDigit().frame(width: 53).foregroundStyle(ToolPalette.muted)
                }
                Toggle("开机时启动键点", isOn: Binding(get: { controller.settings.launchAtLogin }, set: { controller.setLaunchAtLogin($0) }))
                    .foregroundStyle(.white)
            }
        }
    }
}

private extension Color {
    init(hex: String) {
        let value = Int(hex, radix: 16) ?? 0x8B5CF6
        self.init(red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255, blue: Double(value & 0xFF) / 255)
    }
}
