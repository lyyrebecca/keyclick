import Foundation
import XCTest
@testable import KeyClickCore

final class KeyClickCoreTests: XCTestCase {
    func testMarkerAssignmentStartsAtDigitsThenLetters() {
        var profile = ClickProfile(name: "题库", targetBundleIdentifier: "com.example.quiz")
        for _ in 0..<10 { XCTAssertNotNil(ProfileLogic.addMarker(to: &profile)) }
        XCTAssertEqual(profile.markers.first?.label, "1")
        XCTAssertEqual(profile.markers[8].label, "9")
        XCTAssertEqual(profile.markers[9].label, "A")
    }

    func testDuplicateKeysAreRejected() {
        let first = MarkerBinding(keyCode: 18, label: "1", position: .center, order: 0)
        let second = MarkerBinding(keyCode: 18, label: "1", position: .center, order: 1)
        let profile = ClickProfile(name: "重复", targetBundleIdentifier: "com.example", markers: [first, second])
        XCTAssertThrowsError(try ProfileLogic.validate(profile)) { error in
            XCTAssertEqual(error as? ProfileValidationError, .duplicateKey("1"))
        }
    }

    func testNormalizedPositionRoundTrip() {
        let frame = CGRect(x: 100, y: 200, width: 400, height: 300)
        let p = NormalizedPoint(x: 0.25, y: 0.75)
        let screen = ProfileLogic.point(in: frame, normalized: p)
        XCTAssertEqual(screen.x, 200)
        XCTAssertEqual(screen.y, 425)
        XCTAssertEqual(ProfileLogic.normalized(point: screen, in: frame), p)
    }

    func testStoreRecoversFromInvalidJSON() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let url = root.appendingPathComponent("config.json")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: url)
        let result = ProfileStore(fileURL: url).load()
        XCTAssertTrue(result.recoveredFromCorruption)
        XCTAssertEqual(result.settings, .empty)
    }

    func testFocusLossAlwaysDisarms() {
        var state = InteractionState(); state.arm(canArm: true); state.targetLost()
        XCTAssertEqual(state.mode, .standby)
    }
}
