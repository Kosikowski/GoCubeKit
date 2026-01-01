import Foundation

/// Errors that can occur during move decoding
public enum MoveDecoderError: Error, Equatable {
    case emptyPayload
    case invalidMoveCode(code: UInt8)
    case oddPayloadLength(length: Int)
}

/// Decodes move messages from the GoCube protocol
public struct MoveDecoder: Sendable {

    public init() {}

    /// Decode a move message payload into an array of moves
    /// - Parameter payload: Raw payload bytes from a rotation message (type 0x01)
    /// - Returns: Array of decoded moves
    /// - Throws: MoveDecoderError if decoding fails
    public func decode(_ payload: Data) throws -> [Move] {
        let bytes = Array(payload)

        guard !bytes.isEmpty else {
            throw MoveDecoderError.emptyPayload
        }

        // Each move is encoded as 2 bytes
        guard bytes.count % 2 == 0 else {
            throw MoveDecoderError.oddPayloadLength(length: bytes.count)
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
    /// - Throws: MoveDecoderError if the code is invalid
    public func decodeMove(code: UInt8, centerOrientation: UInt8) throws -> Move {
        guard code <= 0x0B else {
            throw MoveDecoderError.invalidMoveCode(code: code)
        }

        // Face mapping: BFUDRL
        // code >> 1 gives face index (0-5)
        // code & 1 gives direction (0 = CW, 1 = CCW)
        let faceIndex = Int(code >> 1)
        let isCounterClockwise = (code & 1) == 1

        let face = faceFromProtocolIndex(faceIndex)
        let direction: MoveDirection = isCounterClockwise ? .counterclockwise : .clockwise

        return Move(face: face, direction: direction, centerOrientation: centerOrientation)
    }

    /// Convert protocol face index to CubeFace
    /// Protocol order: Back(0), Front(1), Up(2), Down(3), Right(4), Left(5)
    private func faceFromProtocolIndex(_ index: Int) -> CubeFace {
        switch index {
        case 0: return .back
        case 1: return .front
        case 2: return .up
        case 3: return .down
        case 4: return .right
        case 5: return .left
        default: return .front // Should never happen due to validation
        }
    }

    /// Encode a move back to protocol bytes
    /// - Parameter move: The move to encode
    /// - Returns: 2-byte encoding of the move
    public func encode(_ move: Move) -> [UInt8] {
        let faceCode = protocolIndexFromFace(move.face)
        let directionBit: UInt8 = move.direction == .counterclockwise ? 1 : 0
        let moveCode = UInt8(faceCode << 1) | directionBit
        let centerOrientation = move.centerOrientation ?? 0

        return [moveCode, centerOrientation]
    }

    private func protocolIndexFromFace(_ face: CubeFace) -> Int {
        switch face {
        case .back: return 0
        case .front: return 1
        case .up: return 2
        case .down: return 3
        case .right: return 4
        case .left: return 5
        }
    }
}

// MARK: - Move Code Constants

extension MoveDecoder {
    /// All valid move codes and their meanings
    public enum MoveCode: UInt8, CaseIterable {
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
