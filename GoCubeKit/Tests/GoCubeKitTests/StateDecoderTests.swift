import XCTest
@testable import GoCubeKit

final class StateDecoderTests: XCTestCase {

    var decoder: StateDecoder!

    override func setUp() {
        super.setUp()
        decoder = StateDecoder()
    }

    override func tearDown() {
        decoder = nil
        super.tearDown()
    }

    // MARK: - Helper Functions

    /// Create a solved cube payload (60 bytes)
    private func createSolvedPayload() -> Data {
        var bytes: [UInt8] = []

        // Face order: Back(0x00=Blue), Front(0x01=Green), Up(0x02=White),
        //             Down(0x03=Yellow), Right(0x04=Red), Left(0x05=Orange)
        let faceColors: [UInt8] = [0x00, 0x01, 0x02, 0x03, 0x04, 0x05]

        for color in faceColors {
            for _ in 0..<9 {
                bytes.append(color)
            }
        }

        // 6 center orientations (all 0)
        for _ in 0..<6 {
            bytes.append(0x00)
        }

        return Data(bytes)
    }

    /// Create a custom payload with specified face colors
    private func createPayload(faceColors: [[UInt8]], orientations: [UInt8] = [0, 0, 0, 0, 0, 0]) -> Data {
        var bytes: [UInt8] = []

        for face in faceColors {
            bytes.append(contentsOf: face)
        }

        bytes.append(contentsOf: orientations)

        return Data(bytes)
    }

    // MARK: - Valid Payload Tests

    func testDecode_SolvedCube() throws {
        let payload = createSolvedPayload()

        let state = try decoder.decode(payload)

        XCTAssertTrue(state.isSolved)
        XCTAssertEqual(state.correctStickerCount, 54)
        XCTAssertEqual(state.solvedPercentage, 100.0)
    }

    func testDecode_SolvedCubeFromStaticPayload() throws {
        let payload = StateDecoder.solvedPayload

        let state = try decoder.decode(payload)

        XCTAssertTrue(state.isSolved)
    }

    func testDecode_AllBlue() throws {
        var bytes = Array(repeating: UInt8(0x00), count: 54) // All blue
        bytes.append(contentsOf: Array(repeating: UInt8(0x00), count: 6))
        let payload = Data(bytes)

        let state = try decoder.decode(payload)

        // All stickers are blue
        for face in CubeFace.allCases {
            let colors = state.colors(for: face)
            XCTAssertTrue(colors.allSatisfy { $0 == .blue })
        }
    }

    func testDecode_MixedColors() throws {
        var bytes: [UInt8] = []

        // Face 0 (Back): alternating blue/green
        for i in 0..<9 {
            bytes.append(UInt8(i % 2))
        }
        // Face 1 (Front): all green
        for _ in 0..<9 {
            bytes.append(0x01)
        }
        // Face 2 (Up): all white
        for _ in 0..<9 {
            bytes.append(0x02)
        }
        // Face 3 (Down): all yellow
        for _ in 0..<9 {
            bytes.append(0x03)
        }
        // Face 4 (Right): all red
        for _ in 0..<9 {
            bytes.append(0x04)
        }
        // Face 5 (Left): all orange
        for _ in 0..<9 {
            bytes.append(0x05)
        }
        // Orientations
        bytes.append(contentsOf: [0x00, 0x00, 0x00, 0x00, 0x00, 0x00])

        let payload = Data(bytes)
        let state = try decoder.decode(payload)

        // Back face should have alternating colors
        let backColors = state.colors(for: .back)
        XCTAssertEqual(backColors[0], .blue)
        XCTAssertEqual(backColors[1], .green)
        XCTAssertEqual(backColors[2], .blue)

        // Other faces should be uniform
        XCTAssertTrue(state.colors(for: .front).allSatisfy { $0 == .green })
        XCTAssertTrue(state.colors(for: .up).allSatisfy { $0 == .white })
        XCTAssertTrue(state.colors(for: .down).allSatisfy { $0 == .yellow })
        XCTAssertTrue(state.colors(for: .right).allSatisfy { $0 == .red })
        XCTAssertTrue(state.colors(for: .left).allSatisfy { $0 == .orange })
    }

    func testDecode_CenterOrientations() throws {
        var bytes = Array(repeating: UInt8(0x00), count: 54)
        // Different orientations for each face
        bytes.append(contentsOf: [0x00, 0x03, 0x06, 0x09, 0x00, 0x03])

        let payload = Data(bytes)
        let state = try decoder.decode(payload)

        XCTAssertEqual(state.centerOrientations[0], 0x00)
        XCTAssertEqual(state.centerOrientations[1], 0x03)
        XCTAssertEqual(state.centerOrientations[2], 0x06)
        XCTAssertEqual(state.centerOrientations[3], 0x09)
        XCTAssertEqual(state.centerOrientations[4], 0x00)
        XCTAssertEqual(state.centerOrientations[5], 0x03)
    }

    // MARK: - Invalid Payload Tests

    func testDecode_TooShortPayload_ThrowsError() {
        let payload = Data(Array(repeating: UInt8(0x00), count: 59))

        XCTAssertThrowsError(try decoder.decode(payload)) { error in
            guard case StateDecoderError.invalidPayloadLength(let expected, let actual) = error else {
                XCTFail("Expected invalidPayloadLength error")
                return
            }
            XCTAssertEqual(expected, 60)
            XCTAssertEqual(actual, 59)
        }
    }

    func testDecode_TooLongPayload_ThrowsError() {
        let payload = Data(Array(repeating: UInt8(0x00), count: 61))

        XCTAssertThrowsError(try decoder.decode(payload)) { error in
            guard case StateDecoderError.invalidPayloadLength(let expected, let actual) = error else {
                XCTFail("Expected invalidPayloadLength error")
                return
            }
            XCTAssertEqual(expected, 60)
            XCTAssertEqual(actual, 61)
        }
    }

    func testDecode_EmptyPayload_ThrowsError() {
        let payload = Data()

        XCTAssertThrowsError(try decoder.decode(payload)) { error in
            guard case StateDecoderError.invalidPayloadLength(let expected, let actual) = error else {
                XCTFail("Expected invalidPayloadLength error")
                return
            }
            XCTAssertEqual(expected, 60)
            XCTAssertEqual(actual, 0)
        }
    }

    func testDecode_InvalidColorValue_ThrowsError() {
        var bytes = Array(repeating: UInt8(0x00), count: 60)
        bytes[10] = 0x06 // Invalid color (valid range is 0-5)

        let payload = Data(bytes)

        XCTAssertThrowsError(try decoder.decode(payload)) { error in
            guard case StateDecoderError.invalidColorValue(let value, let position) = error else {
                XCTFail("Expected invalidColorValue error")
                return
            }
            XCTAssertEqual(value, 0x06)
            XCTAssertEqual(position, 10)
        }
    }

    func testDecode_InvalidColorValueMax_ThrowsError() {
        var bytes = Array(repeating: UInt8(0x00), count: 60)
        bytes[0] = 0xFF // Max invalid value

        let payload = Data(bytes)

        XCTAssertThrowsError(try decoder.decode(payload)) { error in
            guard case StateDecoderError.invalidColorValue(let value, let position) = error else {
                XCTFail("Expected invalidColorValue error")
                return
            }
            XCTAssertEqual(value, 0xFF)
            XCTAssertEqual(position, 0)
        }
    }

    // MARK: - Encoding Tests

    func testEncode_SolvedCube() {
        let state = CubeState.solved

        let encoded = decoder.encode(state)

        XCTAssertEqual(encoded.count, 60)
        XCTAssertEqual(encoded, StateDecoder.solvedPayload)
    }

    func testEncode_CustomState() throws {
        let payload = createSolvedPayload()
        let state = try decoder.decode(payload)

        let encoded = decoder.encode(state)

        XCTAssertEqual(encoded, payload)
    }

    // MARK: - Round-trip Tests

    func testRoundTrip_SolvedCube() throws {
        let original = CubeState.solved

        let encoded = decoder.encode(original)
        let decoded = try decoder.decode(encoded)

        XCTAssertEqual(decoded, original)
    }

    func testRoundTrip_MixedState() throws {
        var bytes: [UInt8] = []
        for i in 0..<54 {
            bytes.append(UInt8(i % 6))
        }
        bytes.append(contentsOf: [0x00, 0x03, 0x06, 0x09, 0x00, 0x03])

        let originalPayload = Data(bytes)
        let decoded = try decoder.decode(originalPayload)
        let encoded = decoder.encode(decoded)

        XCTAssertEqual(encoded, originalPayload)
    }

    // MARK: - Validation Tests

    func testIsValidState_SolvedCube() {
        let state = CubeState.solved

        XCTAssertTrue(decoder.isValidState(state))
    }

    func testIsValidState_AllOneColor_Invalid() throws {
        var bytes = Array(repeating: UInt8(0x00), count: 54) // All blue (54 blue stickers)
        bytes.append(contentsOf: Array(repeating: UInt8(0x00), count: 6))

        let payload = Data(bytes)
        let state = try decoder.decode(payload)

        // This is invalid because we should have exactly 9 of each color
        XCTAssertFalse(decoder.isValidState(state))
    }

    // MARK: - Estimate Moves Tests

    func testEstimateMovesFromSolved_SolvedCube() {
        let state = CubeState.solved

        let estimate = decoder.estimateMovesFromSolved(state)

        XCTAssertEqual(estimate, 0)
    }

    func testEstimateMovesFromSolved_ScrambledCube() throws {
        // Create a state where only half the stickers are correct
        var bytes: [UInt8] = []
        for faceIndex in 0..<6 {
            for stickerIndex in 0..<9 {
                if stickerIndex < 5 {
                    bytes.append(UInt8(faceIndex)) // Correct color
                } else {
                    bytes.append(UInt8((faceIndex + 1) % 6)) // Wrong color
                }
            }
        }
        bytes.append(contentsOf: Array(repeating: UInt8(0x00), count: 6))

        let payload = Data(bytes)
        let state = try decoder.decode(payload)

        let estimate = decoder.estimateMovesFromSolved(state)

        XCTAssertGreaterThan(estimate, 0)
    }

    // MARK: - CubeState Model Tests

    func testCubeState_Color() {
        let state = CubeState.solved

        XCTAssertEqual(state.color(at: .back, position: 0), .blue)
        XCTAssertEqual(state.color(at: .front, position: 0), .green)
        XCTAssertEqual(state.color(at: .up, position: 0), .white)
        XCTAssertEqual(state.color(at: .down, position: 0), .yellow)
        XCTAssertEqual(state.color(at: .right, position: 0), .red)
        XCTAssertEqual(state.color(at: .left, position: 0), .orange)
    }

    func testCubeState_CenterColor() {
        let state = CubeState.solved

        XCTAssertEqual(state.centerColor(for: .back), .blue)
        XCTAssertEqual(state.centerColor(for: .front), .green)
        XCTAssertEqual(state.centerColor(for: .up), .white)
        XCTAssertEqual(state.centerColor(for: .down), .yellow)
        XCTAssertEqual(state.centerColor(for: .right), .red)
        XCTAssertEqual(state.centerColor(for: .left), .orange)
    }

    func testCubeState_ColorsForFace() {
        let state = CubeState.solved

        let upColors = state.colors(for: .up)

        XCTAssertEqual(upColors.count, 9)
        XCTAssertTrue(upColors.allSatisfy { $0 == .white })
    }

    func testCubeState_Description() {
        let state = CubeState.solved

        let description = state.description

        XCTAssertTrue(description.contains("B: BBBBBBBBB"))
        XCTAssertTrue(description.contains("F: GGGGGGGGG"))
        XCTAssertTrue(description.contains("U: WWWWWWWWW"))
    }

    func testCubeState_Builder() {
        var builder = CubeState.Builder()
        builder.setColor(.red, at: .up, position: 0)
        builder.setCenterOrientation(0x03, for: .up)

        let state = builder.build()

        XCTAssertEqual(state.color(at: .up, position: 0), .red)
        XCTAssertEqual(state.centerOrientations[CubeFace.up.rawValue], 0x03)
    }

    func testCubeState_BuilderSetFace() {
        var builder = CubeState.Builder()
        let redFace = Array(repeating: CubeColor.red, count: 9)
        builder.setFace(.front, colors: redFace)

        let state = builder.build()

        XCTAssertTrue(state.colors(for: .front).allSatisfy { $0 == .red })
    }

    func testCubeState_Equatable() {
        let state1 = CubeState.solved
        let state2 = CubeState.solved

        XCTAssertEqual(state1, state2)
    }

    func testCubeState_Hashable() {
        var set = Set<CubeState>()
        set.insert(CubeState.solved)
        set.insert(CubeState.solved)

        XCTAssertEqual(set.count, 1)
    }
}

// MARK: - Face and Color Model Tests

final class FaceColorModelTests: XCTestCase {

    func testCubeFace_Notation() {
        XCTAssertEqual(CubeFace.back.notation, "B")
        XCTAssertEqual(CubeFace.front.notation, "F")
        XCTAssertEqual(CubeFace.up.notation, "U")
        XCTAssertEqual(CubeFace.down.notation, "D")
        XCTAssertEqual(CubeFace.right.notation, "R")
        XCTAssertEqual(CubeFace.left.notation, "L")
    }

    func testCubeFace_SolvedCenterColor() {
        XCTAssertEqual(CubeFace.back.solvedCenterColor, .blue)
        XCTAssertEqual(CubeFace.front.solvedCenterColor, .green)
        XCTAssertEqual(CubeFace.up.solvedCenterColor, .white)
        XCTAssertEqual(CubeFace.down.solvedCenterColor, .yellow)
        XCTAssertEqual(CubeFace.right.solvedCenterColor, .red)
        XCTAssertEqual(CubeFace.left.solvedCenterColor, .orange)
    }

    func testCubeFace_ProtocolIndex() {
        XCTAssertEqual(CubeFace(protocolIndex: 0), .back)
        XCTAssertEqual(CubeFace(protocolIndex: 1), .front)
        XCTAssertEqual(CubeFace(protocolIndex: 2), .up)
        XCTAssertEqual(CubeFace(protocolIndex: 3), .down)
        XCTAssertEqual(CubeFace(protocolIndex: 4), .right)
        XCTAssertEqual(CubeFace(protocolIndex: 5), .left)
        XCTAssertNil(CubeFace(protocolIndex: 6))
        XCTAssertNil(CubeFace(protocolIndex: -1))
    }

    func testCubeFace_AllCases() {
        XCTAssertEqual(CubeFace.allCases.count, 6)
    }

    func testCubeColor_Character() {
        XCTAssertEqual(CubeColor.blue.character, "B")
        XCTAssertEqual(CubeColor.green.character, "G")
        XCTAssertEqual(CubeColor.white.character, "W")
        XCTAssertEqual(CubeColor.yellow.character, "Y")
        XCTAssertEqual(CubeColor.red.character, "R")
        XCTAssertEqual(CubeColor.orange.character, "O")
    }

    func testCubeColor_Description() {
        XCTAssertEqual(CubeColor.blue.description, "Blue")
        XCTAssertEqual(CubeColor.green.description, "Green")
        XCTAssertEqual(CubeColor.white.description, "White")
        XCTAssertEqual(CubeColor.yellow.description, "Yellow")
        XCTAssertEqual(CubeColor.red.description, "Red")
        XCTAssertEqual(CubeColor.orange.description, "Orange")
    }

    func testCubeColor_ProtocolValue() {
        XCTAssertEqual(CubeColor(protocolValue: 0), .blue)
        XCTAssertEqual(CubeColor(protocolValue: 1), .green)
        XCTAssertEqual(CubeColor(protocolValue: 2), .white)
        XCTAssertEqual(CubeColor(protocolValue: 3), .yellow)
        XCTAssertEqual(CubeColor(protocolValue: 4), .red)
        XCTAssertEqual(CubeColor(protocolValue: 5), .orange)
        XCTAssertNil(CubeColor(protocolValue: 6))
        XCTAssertNil(CubeColor(protocolValue: 255))
    }

    func testCubeColor_RawValue() {
        XCTAssertEqual(CubeColor.blue.rawValue, 0x00)
        XCTAssertEqual(CubeColor.green.rawValue, 0x01)
        XCTAssertEqual(CubeColor.white.rawValue, 0x02)
        XCTAssertEqual(CubeColor.yellow.rawValue, 0x03)
        XCTAssertEqual(CubeColor.red.rawValue, 0x04)
        XCTAssertEqual(CubeColor.orange.rawValue, 0x05)
    }

    func testCubeColor_AllCases() {
        XCTAssertEqual(CubeColor.allCases.count, 6)
    }
}
