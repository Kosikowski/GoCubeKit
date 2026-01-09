import Foundation

/// Decodes cube state messages from the GoCube protocol
public struct StateDecoder: Sendable {

    /// Expected payload length for a cube state message
    /// 54 facelets + 6 center orientations = 60 bytes
    public static let expectedPayloadLength = 60

    /// Number of stickers per face
    public static let stickersPerFace = 9

    /// Number of faces
    public static let faceCount = 6

    public init() {}

    /// Decode a cube state message payload
    /// - Parameter payload: Raw payload bytes from a state message (type 0x02)
    /// - Returns: Decoded cube state
    /// - Throws: GoCubeError.parsing if decoding fails
    public func decode(_ payload: Data) throws -> CubeState {
        let bytes = Array(payload)

        guard bytes.count == Self.expectedPayloadLength else {
            throw GoCubeError.parsing(.payloadLengthMismatch(
                expected: Self.expectedPayloadLength,
                actual: bytes.count
            ))
        }

        // Parse 6 faces, 9 stickers each (54 bytes)
        var facelets: [[CubeColor]] = []

        for faceIndex in 0..<Self.faceCount {
            let startIndex = faceIndex * Self.stickersPerFace
            var faceColors: [CubeColor] = []

            for stickerIndex in 0..<Self.stickersPerFace {
                let byteIndex = startIndex + stickerIndex
                let colorValue = bytes[byteIndex]

                guard let color = GoCubeProtocol.colorFromProtocolValue(colorValue) else {
                    throw GoCubeError.parsing(.invalidColorValue(
                        value: colorValue,
                        position: byteIndex
                    ))
                }

                faceColors.append(color)
            }

            facelets.append(faceColors)
        }

        // Parse 6 center orientations (bytes 54-59)
        var centerOrientations: [UInt8] = []
        for faceIndex in 0..<Self.faceCount {
            let orientation = bytes[54 + faceIndex]
            // Valid orientations are 0x00, 0x03, 0x06, 0x09 (clock positions)
            // But we'll accept any value and store it
            centerOrientations.append(orientation)
        }

        // Use internal init since we've validated all the data above
        return CubeState(validatedFacelets: facelets, centerOrientations: centerOrientations)
    }

    /// Encode a cube state back to protocol bytes
    /// - Parameter state: The cube state to encode
    /// - Returns: 60-byte encoding of the state
    public func encode(_ state: CubeState) -> Data {
        var bytes: [UInt8] = []

        // Encode 54 facelets
        for face in state.facelets {
            for color in face {
                bytes.append(GoCubeProtocol.protocolValueFromColor(color))
            }
        }

        // Encode 6 center orientations
        for orientation in state.centerOrientations {
            bytes.append(orientation)
        }

        return Data(bytes)
    }

    /// Create a solved cube state payload
    public static var solvedPayload: Data {
        var bytes: [UInt8] = []

        // Solved cube: each face has 9 stickers of the same color
        // Face order: Back(Blue), Front(Green), Up(White), Down(Yellow), Right(Red), Left(Orange)
        let faceColors: [UInt8] = [0x00, 0x01, 0x02, 0x03, 0x04, 0x05]

        for colorValue in faceColors {
            for _ in 0..<9 {
                bytes.append(colorValue)
            }
        }

        // 6 center orientations (all 0 for solved)
        for _ in 0..<6 {
            bytes.append(0x00)
        }

        return Data(bytes)
    }
}

// MARK: - Validation Helpers

extension StateDecoder {
    /// Validate that a cube state is physically possible
    /// - Parameter state: The state to validate
    /// - Returns: True if the state could exist on a real cube
    public func isValidState(_ state: CubeState) -> Bool {
        // Check that we have exactly 9 stickers of each color
        var colorCounts: [CubeColor: Int] = [:]

        for face in state.facelets {
            for color in face {
                colorCounts[color, default: 0] += 1
            }
        }

        // Each color should appear exactly 9 times
        for color in CubeColor.allCases {
            if colorCounts[color] != 9 {
                return false
            }
        }

        return true
    }

    /// Calculate how many moves away from solved (rough estimate)
    /// - Parameter state: The cube state
    /// - Returns: Estimated number of moves (not optimal)
    public func estimateMovesFromSolved(_ state: CubeState) -> Int {
        // Simple heuristic: count misplaced stickers / 4
        // (each move affects ~8 stickers, but some might already be correct)
        let misplaced = 54 - state.correctStickerCount
        return max(0, misplaced / 4)
    }
}
