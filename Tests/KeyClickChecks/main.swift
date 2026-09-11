import Foundation
import KeyClickCore

@main
struct KeyClickChecks {
    static func main() {
        var failures: [String] = []
        func check(_ condition: @autoclosure () -> Bool, _ message: String) {
            if !condition() { failures.append(message) }
        }

        var profile = ClickProfile(name: "题库", targetBundleIdentifier: "com.example.quiz")
        for _ in 0..<10 { check(ProfileLogic.addMarker(to: &profile) != nil, "marker assignment") }
        check(profile.markers.first?.label == "1", "first key is 1")
        check(profile.markers[8].label == "9" && profile.markers[9].label == "A", "key order reaches A after 9")
        check(KeyMap.label(for: 23) == "5" && KeyMap.label(for: 22) == "6", "physical keys 5 and 6")
        check(KeyMap.label(for: 26) == "7" && KeyMap.label(for: 28) == "8" && KeyMap.label(for: 25) == "9", "physical keys 7 through 9")
        check(KeyMap.aliases(for: 23).contains(87) && KeyMap.aliases(for: 25).contains(92), "numeric keypad aliases")
        let duplicate = ClickProfile(name: "重复", targetBundleIdentifier: "com.example", markers: [
            MarkerBinding(keyCode: 18, label: "1", position: .center, order: 0),
            MarkerBinding(keyCode: 18, label: "1", position: .center, order: 1)
        ])
        do { try ProfileLogic.validate(duplicate); failures.append("duplicate keys accepted") } catch { }
        let frame = CGRect(x: 100, y: 200, width: 400, height: 300)
        let point = ProfileLogic.point(in: frame, normalized: NormalizedPoint(x: 0.25, y: 0.75))
        check(point.x == 200 && point.y == 425, "normalized point conversion")
        check(ProfileLogic.normalized(point: point, in: frame) == NormalizedPoint(x: 0.25, y: 0.75), "normalized round-trip")
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let url = root.appendingPathComponent("config.json")
        try! FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try! Data("bad json".utf8).write(to: url)
        let recovered = ProfileStore(fileURL: url).load()
        check(recovered.recoveredFromCorruption && recovered.settings == .empty, "corrupt JSON recovery")
        var state = InteractionState(); state.arm(canArm: true); state.targetLost()
        check(state.mode == .standby, "focus loss disarms")
        if failures.isEmpty { print("✅ KeyClick core checks: 19 assertions passed") }
        else { fputs("❌ \(failures.joined(separator: "; "))\n", stderr); exit(1) }
    }
}
