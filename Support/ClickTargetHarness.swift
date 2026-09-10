import AppKit

@main
@MainActor
struct ClickTargetHarnessMain {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let delegate = HarnessDelegate()
        app.delegate = delegate
        app.run()
    }
}

@MainActor
final class HarnessDelegate: NSObject, NSApplicationDelegate {
    private var counts = Array(repeating: 0, count: 4)
    private var buttons: [NSButton] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 420),
                              styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "KeyClick 点击测试靶场"
        let content = NSView(frame: window.contentView!.bounds)
        content.wantsLayer = true
        content.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        let heading = NSTextField(labelWithString: "KeyClick 键盘点击验证")
        heading.font = .systemFont(ofSize: 21, weight: .bold)
        heading.frame = NSRect(x: 34, y: 350, width: 410, height: 30)
        content.addSubview(heading)
        let note = NSTextField(labelWithString: "将 1–4 浮标分别拖到下面按钮，然后在点击模式按对应数字。")
        note.textColor = .secondaryLabelColor
        note.frame = NSRect(x: 34, y: 324, width: 410, height: 20)
        content.addSubview(note)
        for index in 0..<4 {
            let button = NSButton(title: title(for: index), target: self, action: #selector(clicked(_:)))
            button.tag = index
            button.bezelStyle = .rounded
            button.font = .systemFont(ofSize: 17, weight: .medium)
            button.frame = NSRect(x: 34, y: 252 - CGFloat(index) * 62, width: 412, height: 46)
            content.addSubview(button)
            buttons.append(button)
        }
        window.contentView = content
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func clicked(_ sender: NSButton) {
        counts[sender.tag] += 1
        sender.title = title(for: sender.tag)
    }

    private func title(for index: Int) -> String { "选项 \(index + 1)  ·  已点击 \(counts[index]) 次" }
}
