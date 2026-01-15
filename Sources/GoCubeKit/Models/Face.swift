import Foundation

/// Represents a face of the cube
/// Order matches the GoCube protocol: Back, Front, Up, Down, Right, Left
public enum CubeFace: Int, CaseIterable, Equatable, Hashable, Sendable, CustomStringConvertible {
    case back = 0 // Blue center
    case front = 1 // Green center
    case up = 2 // White center
    case down = 3 // Yellow center
    case right = 4 // Red center
    case left = 5 // Orange center

    /// Single character notation (standard cube notation)
    public var notation: Character {
        switch self {
        case .back: return "B"
        case .front: return "F"
        case .up: return "U"
        case .down: return "D"
        case .right: return "R"
        case .left: return "L"
        }
    }

    public var description: String {
        switch self {
        case .back: return "Back"
        case .front: return "Front"
        case .up: return "Up"
        case .down: return "Down"
        case .right: return "Right"
        case .left: return "Left"
        }
    }

    /// The center color for this face in a solved cube
    public var solvedCenterColor: CubeColor {
        switch self {
        case .back: return .blue
        case .front: return .green
        case .up: return .white
        case .down: return .yellow
        case .right: return .red
        case .left: return .orange
        }
    }

    /// Number of stickers per face (including center)
    public static let stickersPerFace = 9

    /// Create from protocol face index
    public init?(protocolIndex: Int) {
        guard protocolIndex >= 0, protocolIndex < 6 else { return nil }
        self.init(rawValue: protocolIndex)
    }
}
