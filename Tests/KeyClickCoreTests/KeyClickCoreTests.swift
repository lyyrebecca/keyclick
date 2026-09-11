import Foundation
import Testing
@testable import KeyClickCore

@Test func markerAssignmentStartsAtDigitsThenLetters() {
    var profile = ClickProfile(name: "题库", targetBundleIdentifier: "com.example.quiz")
    for _ in 0..<10 { #expect(ProfileLogic.addMarker(to: &profile) != nil) }
    #expect(profile.markers.first?.label == "1")
    #expect(profile.markers[8].label == "9")
    #expect(profile.markers[9].label == "A")
}

@Test func duplicateKeysAreRejected() {
    let first = MarkerBinding(keyCode: 18, label: "1", position: .center, order: 0)
    let second = MarkerBinding(keyCode: 18, label: "1", position: .center, order: 1)
    let profile = ClickProfile(name: "重复", targetBundleIdentifier: "com.example", markers: [first, second])
    #expect(throws: ProfileValidationError.duplicateKey("1")) { try ProfileLogic.validate(profile) }
}

@Test func normalizedPositionRoundTrip() {
    let frame = CGRect(x: 100, y: 200, width: 400, height: 300)
    let p = NormalizedPoint(x: 0.25, y: 0.75)
    let screen = ProfileLogic.point(in: frame, normalized: p)
    #expect(screen.x == 200)
    #expect(screen.y == 425)
    #expect(ProfileLogic.normalized(point: screen, in: frame) == p)
}

@Test func storeRecoversFromInvalidJSON() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let url = root.appendingPathComponent("config.json")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try Data("not json".utf8).write(to: url)
    let result = ProfileStore(fileURL: url).load()
    #expect(result.recoveredFromCorruption)
    #expect(result.settings == .empty)
}

@Test func v1SettingsMigrateWithoutDiscardingLayouts() throws {
    let source = """
    {"schemaVersion":1,"profiles":[],"activeProfileID":null,"toggleShortcut":"controlOptionK","launchAtLogin":false,"markerOpacity":0.56,"markerSize":32}
    """
    let decoded = try JSONDecoder().decode(AppSettings.self, from: Data(source.utf8))
    #expect(decoded.schemaVersion == 1)
    #expect(!decoded.ignorePermissionStatus)
}

@Test func focusLossAlwaysDisarms() {
    var state = InteractionState(); state.arm(canArm: true); state.targetLost()
    #expect(state.mode == .standby)
}

@Test func digitBindingsUseActualMacVirtualKeyCodes() {
    #expect(KeyMap.label(for: 18) == "1")
    #expect(KeyMap.label(for: 21) == "4")
    #expect(KeyMap.label(for: 23) == "5")
    #expect(KeyMap.label(for: 22) == "6")
    #expect(KeyMap.label(for: 26) == "7")
    #expect(KeyMap.label(for: 28) == "8")
    #expect(KeyMap.label(for: 25) == "9")
    #expect(KeyMap.aliases(for: 23).contains(87)) // numeric keypad 5
    #expect(KeyMap.aliases(for: 25).contains(92)) // numeric keypad 9
}
