import Foundation
import CoreGraphics

public enum OverlayMode: String, Codable, Sendable {
    case standby, editing, armed
}

public enum WindowMatchingRule: String, Codable, Sendable {
    case focusedWindow
}

public struct NormalizedPoint: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x.clamped(to: 0...1)
        self.y = y.clamped(to: 0...1)
    }

    public static let center = NormalizedPoint(x: 0.5, y: 0.5)
}

public struct MarkerBinding: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var keyCode: UInt16
    public var label: String
    public var position: NormalizedPoint
    public var colorHex: String
    public var order: Int

    public init(id: UUID = UUID(), keyCode: UInt16, label: String, position: NormalizedPoint, colorHex: String = "8B5CF6", order: Int) {
        self.id = id
        self.keyCode = keyCode
        self.label = label
        self.position = position
        self.colorHex = colorHex
        self.order = order
    }
}

public struct ClickProfile: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var targetBundleIdentifier: String
    public var windowMatchingRule: WindowMatchingRule
    public var markers: [MarkerBinding]
    public var createdAt: Date
    public var updatedAt: Date

    public init(id: UUID = UUID(), name: String, targetBundleIdentifier: String, windowMatchingRule: WindowMatchingRule = .focusedWindow, markers: [MarkerBinding] = [], createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id
        self.name = name
        self.targetBundleIdentifier = targetBundleIdentifier
        self.windowMatchingRule = windowMatchingRule
        self.markers = markers
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public enum ToggleShortcut: String, Codable, CaseIterable, Identifiable, Sendable {
    case controlOptionK
    case controlOptionJ
    case controlOptionSpace

    public var id: String { rawValue }
    public var displayName: String {
        switch self {
        case .controlOptionK: "⌃⌥K"
        case .controlOptionJ: "⌃⌥J"
        case .controlOptionSpace: "⌃⌥Space"
        }
    }

    public var keyCode: UInt16 {
        switch self {
        case .controlOptionK: 40
        case .controlOptionJ: 38
        case .controlOptionSpace: 49
        }
    }
}

public struct AppSettings: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var profiles: [ClickProfile]
    public var activeProfileID: UUID?
    public var toggleShortcut: ToggleShortcut
    public var launchAtLogin: Bool
    public var markerOpacity: Double
    public var markerSize: Double

    public init(schemaVersion: Int = 1, profiles: [ClickProfile] = [], activeProfileID: UUID? = nil, toggleShortcut: ToggleShortcut = .controlOptionK, launchAtLogin: Bool = false, markerOpacity: Double = 0.56, markerSize: Double = 32) {
        self.schemaVersion = schemaVersion
        self.profiles = profiles
        self.activeProfileID = activeProfileID
        self.toggleShortcut = toggleShortcut
        self.launchAtLogin = launchAtLogin
        self.markerOpacity = markerOpacity.clamped(to: 0.2...1)
        self.markerSize = markerSize.clamped(to: 24...56)
    }

    public static let empty = AppSettings()
}

public enum ProfileValidationError: LocalizedError, Equatable {
    case duplicateKey(String)
    case emptyName
    case noMarkers

    public var errorDescription: String? {
        switch self {
        case .duplicateKey(let key): "快捷键 \(key) 已被本配置中的其他浮标使用。"
        case .emptyName: "配置名称不能为空。"
        case .noMarkers: "请至少保留一个浮标。"
        }
    }
}

public enum KeyMap {
    // ANSI physical key codes. Digit keys also recognize their numeric keypad
    // equivalents.  Modifiers and Escape are deliberately excluded: modifiers
    // are reserved for the global toggle and Escape always leaves the mode.
    public static let ordered: [(UInt16, String)] = [
        (18, "1"), (19, "2"), (20, "3"), (21, "4"), (22, "5"), (23, "6"), (24, "7"), (25, "8"), (26, "9"),
        (0, "A"), (11, "B"), (8, "C"), (2, "D"), (14, "E"), (3, "F"), (5, "G"), (4, "H"), (34, "I"), (38, "J"), (40, "K"), (37, "L"), (46, "M"), (45, "N"), (31, "O"), (35, "P"), (12, "Q"), (15, "R"), (1, "S"), (17, "T"), (32, "U"), (9, "V"), (13, "W"), (7, "X"), (16, "Y"), (6, "Z"),
        (49, "Space"), (36, "Return"), (48, "Tab"), (51, "Delete"),
        (123, "←"), (124, "→"), (125, "↓"), (126, "↑"),
        (122, "F1"), (120, "F2"), (99, "F3"), (118, "F4"), (96, "F5"), (97, "F6"),
        (98, "F7"), (100, "F8"), (101, "F9"), (109, "F10"), (103, "F11"), (111, "F12")
    ]

    public static func label(for keyCode: UInt16) -> String? {
        ordered.first(where: { $0.0 == keyCode })?.1
    }

    public static func aliases(for keyCode: UInt16) -> Set<UInt16> {
        let keypad: [UInt16: UInt16] = [18: 83, 19: 84, 20: 85, 21: 86, 22: 87, 23: 88, 24: 89, 25: 91, 26: 92]
        if let alias = keypad[keyCode] { return [keyCode, alias] }
        return [keyCode]
    }

    public static func nextUnused(after markers: [MarkerBinding]) -> (UInt16, String)? {
        let used = Set(markers.map(\.keyCode))
        return ordered.first(where: { !used.contains($0.0) })
    }
}

public enum ProfileLogic {
    public static func validate(_ profile: ClickProfile) throws {
        guard !profile.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ProfileValidationError.emptyName
        }
        guard !profile.markers.isEmpty else { throw ProfileValidationError.noMarkers }
        var seen = Set<UInt16>()
        for marker in profile.markers {
            if !seen.insert(marker.keyCode).inserted {
                throw ProfileValidationError.duplicateKey(marker.label)
            }
        }
    }

    public static func addMarker(to profile: inout ClickProfile, at position: NormalizedPoint? = nil) -> MarkerBinding? {
        guard let next = KeyMap.nextUnused(after: profile.markers) else { return nil }
        // Never stack new dots invisibly at the centre.  Four starter dots are
        // vertically obvious; remaining dots receive a compact grid position.
        let index = profile.markers.count
        let starter = [
            NormalizedPoint(x: 0.50, y: 0.30),
            NormalizedPoint(x: 0.50, y: 0.45),
            NormalizedPoint(x: 0.50, y: 0.60),
            NormalizedPoint(x: 0.50, y: 0.75)
        ]
        let generated: NormalizedPoint
        if index < starter.count {
            generated = starter[index]
        } else {
            let grid = index - starter.count
            generated = NormalizedPoint(x: 0.20 + Double(grid % 4) * 0.20,
                                        y: 0.20 + Double((grid / 4) % 4) * 0.18)
        }
        let marker = MarkerBinding(keyCode: next.0, label: next.1, position: position ?? generated, order: index)
        profile.markers.append(marker)
        profile.updatedAt = Date()
        return marker
    }

    public static func point(in frame: CGRect, normalized: NormalizedPoint) -> CGPoint {
        CGPoint(x: frame.minX + frame.width * normalized.x,
                y: frame.minY + frame.height * normalized.y)
    }

    public static func normalized(point: CGPoint, in frame: CGRect) -> NormalizedPoint? {
        guard frame.width > 0, frame.height > 0, frame.contains(point) else { return nil }
        return NormalizedPoint(x: (point.x - frame.minX) / frame.width,
                               y: (point.y - frame.minY) / frame.height)
    }
}

extension Comparable {
    fileprivate func clamped(to range: ClosedRange<Self>) -> Self { min(max(self, range.lowerBound), range.upperBound) }
}
