import Foundation

/// Direction of a cube move
public enum MoveDirection: Int, Equatable, Hashable, Sendable {
    case clockwise = 1
    case counterclockwise = -1

    /// Invert the direction
    public var inverted: MoveDirection {
        self == .clockwise ? .counterclockwise : .clockwise
    }

    /// Notation suffix for the direction
    public var notationSuffix: String {
        self == .clockwise ? "" : "'"
    }
}

/// Represents a single move on the cube
public struct Move: Equatable, Hashable, Sendable, CustomStringConvertible {
    /// The face being rotated
    public let face: CubeFace

    /// Direction of rotation
    public let direction: MoveDirection

    /// Center orientation after the move (clock position: 0, 3, 6, 9)
    public let centerOrientation: UInt8?

    /// Standard notation (e.g., "R", "U'", "F")
    public var notation: String {
        "\(face.notation)\(direction.notationSuffix)"
    }

    public var description: String {
        notation
    }

    public init(face: CubeFace, direction: MoveDirection, centerOrientation: UInt8? = nil) {
        self.face = face
        self.direction = direction
        self.centerOrientation = centerOrientation
    }

    /// Create a clockwise move for the given face
    public static func clockwise(_ face: CubeFace) -> Move {
        Move(face: face, direction: .clockwise)
    }

    /// Create a counterclockwise move for the given face
    public static func counterclockwise(_ face: CubeFace) -> Move {
        Move(face: face, direction: .counterclockwise)
    }

    /// Invert this move (reverse direction)
    public var inverted: Move {
        Move(face: face, direction: direction.inverted, centerOrientation: centerOrientation)
    }

    // MARK: - Standard Move Constants

    public static let R = Move(face: .right, direction: .clockwise)
    public static let RPrime = Move(face: .right, direction: .counterclockwise)
    public static let L = Move(face: .left, direction: .clockwise)
    public static let LPrime = Move(face: .left, direction: .counterclockwise)
    public static let U = Move(face: .up, direction: .clockwise)
    public static let UPrime = Move(face: .up, direction: .counterclockwise)
    public static let D = Move(face: .down, direction: .clockwise)
    public static let DPrime = Move(face: .down, direction: .counterclockwise)
    public static let F = Move(face: .front, direction: .clockwise)
    public static let FPrime = Move(face: .front, direction: .counterclockwise)
    public static let B = Move(face: .back, direction: .clockwise)
    public static let BPrime = Move(face: .back, direction: .counterclockwise)
}

/// A sequence of moves (algorithm)
public struct MoveSequence: Equatable, Hashable, Sendable, CustomStringConvertible {
    public private(set) var moves: [Move]

    public var description: String {
        moves.map(\.notation).joined(separator: " ")
    }

    public var count: Int {
        moves.count
    }

    public var isEmpty: Bool {
        moves.isEmpty
    }

    public init(_ moves: [Move] = []) {
        self.moves = moves
    }

    public mutating func append(_ move: Move) {
        moves.append(move)
    }

    public mutating func clear() {
        moves.removeAll()
    }

    /// Create inverted sequence (reverse order, each move inverted)
    public var inverted: MoveSequence {
        MoveSequence(moves.reversed().map(\.inverted))
    }

    /// Parse a move sequence from standard notation
    /// Supports: R, R', R2, U, U', U2, etc.
    public static func parse(_ notation: String) -> MoveSequence? {
        var moves: [Move] = []
        let tokens = notation.split(separator: " ")

        for token in tokens {
            let parsedMoves = parseMoves(String(token))
            guard !parsedMoves.isEmpty else {
                return nil
            }
            moves.append(contentsOf: parsedMoves)
        }

        return MoveSequence(moves)
    }

    /// Parse a single token into one or more moves (handles double moves like "R2")
    private static func parseMoves(_ token: String) -> [Move] {
        guard let faceChar = token.first else { return [] }

        let face: CubeFace
        switch faceChar {
        case "R": face = .right
        case "L": face = .left
        case "U": face = .up
        case "D": face = .down
        case "F": face = .front
        case "B": face = .back
        default: return []
        }

        if token.hasSuffix("'") || token.hasSuffix("'") {
            return [Move(face: face, direction: .counterclockwise)]
        } else if token.hasSuffix("2") {
            // Double move - return two clockwise moves
            let move = Move(face: face, direction: .clockwise)
            return [move, move]
        } else {
            return [Move(face: face, direction: .clockwise)]
        }
    }
}
