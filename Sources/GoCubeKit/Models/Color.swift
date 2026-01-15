import Foundation

/// Represents a sticker color on the cube
/// Values match the GoCube protocol encoding
public enum CubeColor: UInt8, CaseIterable, Equatable, Hashable, Sendable, CustomStringConvertible {
    case blue = 0x00
    case green = 0x01
    case white = 0x02
    case yellow = 0x03
    case red = 0x04
    case orange = 0x05

    /// Single character representation for compact display
    public var character: Character {
        switch self {
        case .blue: return "B"
        case .green: return "G"
        case .white: return "W"
        case .yellow: return "Y"
        case .red: return "R"
        case .orange: return "O"
        }
    }

    public var description: String {
        switch self {
        case .blue: return "Blue"
        case .green: return "Green"
        case .white: return "White"
        case .yellow: return "Yellow"
        case .red: return "Red"
        case .orange: return "Orange"
        }
    }

    /// Create from raw protocol value with validation
    public init?(protocolValue: UInt8) {
        guard protocolValue <= 5 else { return nil }
        self.init(rawValue: protocolValue)
    }
}
