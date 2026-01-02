import Foundation

/// Decodes move messages from the GoCube protocol
public struct MoveDecoder: Sendable {

    public init() {}

    /// Decode a move message payload into an array of moves
    /// - Parameter payload: Raw payload bytes from a rotation message (type 0x01)
    /// - Returns: Array of decoded moves
    /// - Throws: GoCubeError.parsing if decoding fails
    public func decode(_ payload: Data) throws -> [Move] {
        let bytes = Array(payload)

        guard !bytes.isEmpty else {
            throw GoCubeError.parsing(.emptyMovePayload)
        }

        // Each move is encoded as 2 bytes
        guard bytes.count % 2 == 0 else {
            throw GoCubeError.parsing(.oddMovePayloadLength(length: bytes.count))
        }

        var moves: [Move] = []

        for i in stride(from: 0, to: bytes.count, by: 2) {
            let moveCode = bytes[i]
            let centerOrientation = bytes[i + 1]

            let move = try decodeMove(code: moveCode, centerOrientation: centerOrientation)
            moves.append(move)
        }

        return moves
    }

    /// Decode a single move from its protocol code
    /// - Parameters:
    ///   - code: Move code (0x00-0x0B)
    ///   - centerOrientation: Center piece orientation (0x00, 0x03, 0x06, 0x09)
    /// - Returns: Decoded move
    /// - Throws: GoCubeError.parsing if the code is invalid
    public func decodeMove(code: UInt8, centerOrientation: UInt8) throws -> Move {
        guard code <= 0x0B else {
            throw GoCubeError.parsing(.invalidMoveCode(code: code))
        }

        // Face mapping: BFUDRL
        // code >> 1 gives face index (0-5)
        // code & 1 gives direction (0 = CW, 1 = CCW)
        let faceIndex = Int(code >> 1)
        let isCounterClockwise = (code & 1) == 1

        let face = GoCubeProtocol.faceFromProtocolIndex(faceIndex)
        let direction: MoveDirection = isCounterClockwise ? .counterclockwise : .clockwise

        return Move(face: face, direction: direction, centerOrientation: centerOrientation)
    }

    /// Encode a move back to protocol bytes
    /// - Parameter move: The move to encode
    /// - Returns: 2-byte encoding of the move
    public func encode(_ move: Move) -> [UInt8] {
        let faceCode = GoCubeProtocol.protocolIndexFromFace(move.face)
        let directionBit: UInt8 = move.direction == .counterclockwise ? 1 : 0
        let moveCode = UInt8(faceCode << 1) | directionBit
        let centerOrientation = move.centerOrientation ?? 0

        return [moveCode, centerOrientation]
    }
}

// MARK: - Move Code Constants

extension MoveDecoder {
    /// All valid move codes and their meanings
    public enum MoveCode: UInt8, CaseIterable, Sendable {
        case backClockwise = 0x00
        case backCounterClockwise = 0x01
        case frontClockwise = 0x02
        case frontCounterClockwise = 0x03
        case upClockwise = 0x04
        case upCounterClockwise = 0x05
        case downClockwise = 0x06
        case downCounterClockwise = 0x07
        case rightClockwise = 0x08
        case rightCounterClockwise = 0x09
        case leftClockwise = 0x0A
        case leftCounterClockwise = 0x0B

        public var notation: String {
            switch self {
            case .backClockwise: return "B"
            case .backCounterClockwise: return "B'"
            case .frontClockwise: return "F"
            case .frontCounterClockwise: return "F'"
            case .upClockwise: return "U"
            case .upCounterClockwise: return "U'"
            case .downClockwise: return "D"
            case .downCounterClockwise: return "D'"
            case .rightClockwise: return "R"
            case .rightCounterClockwise: return "R'"
            case .leftClockwise: return "L"
            case .leftCounterClockwise: return "L'"
            }
        }
    }
}
