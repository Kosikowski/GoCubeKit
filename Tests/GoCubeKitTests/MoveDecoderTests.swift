@testable import GoCubeKit
import XCTest

final class MoveDecoderTests: XCTestCase {
    var decoder: MoveDecoder!

    override func setUp() {
        super.setUp()
        decoder = MoveDecoder()
    }

    override func tearDown() {
        decoder = nil
        super.tearDown()
    }

    // MARK: - Single Move Decoding Tests

    func testDecodeMove_BackClockwise() throws {
        let move = try decoder.decodeMove(code: 0x00, centerOrientation: 0x00)

        XCTAssertEqual(move.face, .back)
        XCTAssertEqual(move.direction, .clockwise)
        XCTAssertEqual(move.notation, "B")
    }

    func testDecodeMove_BackCounterClockwise() throws {
        let move = try decoder.decodeMove(code: 0x01, centerOrientation: 0x00)

        XCTAssertEqual(move.face, .back)
        XCTAssertEqual(move.direction, .counterclockwise)
        XCTAssertEqual(move.notation, "B'")
    }

    func testDecodeMove_FrontClockwise() throws {
        let move = try decoder.decodeMove(code: 0x02, centerOrientation: 0x00)

        XCTAssertEqual(move.face, .front)
        XCTAssertEqual(move.direction, .clockwise)
        XCTAssertEqual(move.notation, "F")
    }

    func testDecodeMove_FrontCounterClockwise() throws {
        let move = try decoder.decodeMove(code: 0x03, centerOrientation: 0x00)

        XCTAssertEqual(move.face, .front)
        XCTAssertEqual(move.direction, .counterclockwise)
        XCTAssertEqual(move.notation, "F'")
    }

    func testDecodeMove_UpClockwise() throws {
        let move = try decoder.decodeMove(code: 0x04, centerOrientation: 0x00)

        XCTAssertEqual(move.face, .up)
        XCTAssertEqual(move.direction, .clockwise)
        XCTAssertEqual(move.notation, "U")
    }

    func testDecodeMove_UpCounterClockwise() throws {
        let move = try decoder.decodeMove(code: 0x05, centerOrientation: 0x00)

        XCTAssertEqual(move.face, .up)
        XCTAssertEqual(move.direction, .counterclockwise)
        XCTAssertEqual(move.notation, "U'")
    }

    func testDecodeMove_DownClockwise() throws {
        let move = try decoder.decodeMove(code: 0x06, centerOrientation: 0x00)

        XCTAssertEqual(move.face, .down)
        XCTAssertEqual(move.direction, .clockwise)
        XCTAssertEqual(move.notation, "D")
    }

    func testDecodeMove_DownCounterClockwise() throws {
        let move = try decoder.decodeMove(code: 0x07, centerOrientation: 0x00)

        XCTAssertEqual(move.face, .down)
        XCTAssertEqual(move.direction, .counterclockwise)
        XCTAssertEqual(move.notation, "D'")
    }

    func testDecodeMove_RightClockwise() throws {
        let move = try decoder.decodeMove(code: 0x08, centerOrientation: 0x00)

        XCTAssertEqual(move.face, .right)
        XCTAssertEqual(move.direction, .clockwise)
        XCTAssertEqual(move.notation, "R")
    }

    func testDecodeMove_RightCounterClockwise() throws {
        let move = try decoder.decodeMove(code: 0x09, centerOrientation: 0x00)

        XCTAssertEqual(move.face, .right)
        XCTAssertEqual(move.direction, .counterclockwise)
        XCTAssertEqual(move.notation, "R'")
    }

    func testDecodeMove_LeftClockwise() throws {
        let move = try decoder.decodeMove(code: 0x0A, centerOrientation: 0x00)

        XCTAssertEqual(move.face, .left)
        XCTAssertEqual(move.direction, .clockwise)
        XCTAssertEqual(move.notation, "L")
    }

    func testDecodeMove_LeftCounterClockwise() throws {
        let move = try decoder.decodeMove(code: 0x0B, centerOrientation: 0x00)

        XCTAssertEqual(move.face, .left)
        XCTAssertEqual(move.direction, .counterclockwise)
        XCTAssertEqual(move.notation, "L'")
    }

    // MARK: - Center Orientation Tests

    func testDecodeMove_WithCenterOrientation_0() throws {
        let move = try decoder.decodeMove(code: 0x08, centerOrientation: 0x00)
        XCTAssertEqual(move.centerOrientation, 0x00)
    }

    func testDecodeMove_WithCenterOrientation_3() throws {
        let move = try decoder.decodeMove(code: 0x08, centerOrientation: 0x03)
        XCTAssertEqual(move.centerOrientation, 0x03)
    }

    func testDecodeMove_WithCenterOrientation_6() throws {
        let move = try decoder.decodeMove(code: 0x08, centerOrientation: 0x06)
        XCTAssertEqual(move.centerOrientation, 0x06)
    }

    func testDecodeMove_WithCenterOrientation_9() throws {
        let move = try decoder.decodeMove(code: 0x08, centerOrientation: 0x09)
        XCTAssertEqual(move.centerOrientation, 0x09)
    }

    // MARK: - Invalid Move Code Tests

    func testDecodeMove_InvalidCode_ThrowsError() {
        XCTAssertThrowsError(try decoder.decodeMove(code: 0x0C, centerOrientation: 0x00)) { error in
            guard case let GoCubeError.parsing(.invalidMoveCode(code)) = error else {
                XCTFail("Expected invalidMoveCode error")
                return
            }
            XCTAssertEqual(code, 0x0C)
        }
    }

    func testDecodeMove_MaxInvalidCode_ThrowsError() {
        XCTAssertThrowsError(try decoder.decodeMove(code: 0xFF, centerOrientation: 0x00)) { error in
            guard case let GoCubeError.parsing(.invalidMoveCode(code)) = error else {
                XCTFail("Expected invalidMoveCode error")
                return
            }
            XCTAssertEqual(code, 0xFF)
        }
    }

    // MARK: - Payload Decoding Tests

    func testDecode_SingleMove() throws {
        let payload = Data([0x08, 0x00]) // R CW

        let moves = try decoder.decode(payload)

        XCTAssertEqual(moves.count, 1)
        XCTAssertEqual(moves[0].face, .right)
        XCTAssertEqual(moves[0].direction, .clockwise)
    }

    func testDecode_TwoMoves() throws {
        let payload = Data([0x08, 0x00, 0x04, 0x00]) // R, U

        let moves = try decoder.decode(payload)

        XCTAssertEqual(moves.count, 2)
        XCTAssertEqual(moves[0].notation, "R")
        XCTAssertEqual(moves[1].notation, "U")
    }

    func testDecode_MultipleMoves() throws {
        let payload = Data([
            0x08, 0x00, // R
            0x04, 0x00, // U
            0x09, 0x00, // R'
            0x05, 0x00, // U'
        ])

        let moves = try decoder.decode(payload)

        XCTAssertEqual(moves.count, 4)
        XCTAssertEqual(moves.map(\.notation), ["R", "U", "R'", "U'"])
    }

    func testDecode_EmptyPayload_ThrowsError() {
        let payload = Data()

        XCTAssertThrowsError(try decoder.decode(payload)) { error in
            guard case GoCubeError.parsing(.emptyMovePayload) = error else {
                XCTFail("Expected emptyMovePayload error")
                return
            }
        }
    }

    func testDecode_OddLengthPayload_ThrowsError() {
        let payload = Data([0x08, 0x00, 0x04]) // 3 bytes (odd)

        XCTAssertThrowsError(try decoder.decode(payload)) { error in
            guard case let GoCubeError.parsing(.oddMovePayloadLength(length)) = error else {
                XCTFail("Expected oddMovePayloadLength error")
                return
            }
            XCTAssertEqual(length, 3)
        }
    }

    func testDecode_SingleBytePayload_ThrowsError() {
        let payload = Data([0x08])

        XCTAssertThrowsError(try decoder.decode(payload)) { error in
            guard case GoCubeError.parsing(.oddMovePayloadLength) = error else {
                XCTFail("Expected oddMovePayloadLength error")
                return
            }
        }
    }

    // MARK: - Encoding Tests

    func testEncode_RightClockwise() {
        let move = Move(face: .right, direction: .clockwise)

        let encoded = decoder.encode(move)

        XCTAssertEqual(encoded, [0x08, 0x00])
    }

    func testEncode_RightCounterClockwise() {
        let move = Move(face: .right, direction: .counterclockwise)

        let encoded = decoder.encode(move)

        XCTAssertEqual(encoded, [0x09, 0x00])
    }

    func testEncode_AllMoves() {
        let moves: [(Move, [UInt8])] = [
            (Move(face: .back, direction: .clockwise), [0x00, 0x00]),
            (Move(face: .back, direction: .counterclockwise), [0x01, 0x00]),
            (Move(face: .front, direction: .clockwise), [0x02, 0x00]),
            (Move(face: .front, direction: .counterclockwise), [0x03, 0x00]),
            (Move(face: .up, direction: .clockwise), [0x04, 0x00]),
            (Move(face: .up, direction: .counterclockwise), [0x05, 0x00]),
            (Move(face: .down, direction: .clockwise), [0x06, 0x00]),
            (Move(face: .down, direction: .counterclockwise), [0x07, 0x00]),
            (Move(face: .right, direction: .clockwise), [0x08, 0x00]),
            (Move(face: .right, direction: .counterclockwise), [0x09, 0x00]),
            (Move(face: .left, direction: .clockwise), [0x0A, 0x00]),
            (Move(face: .left, direction: .counterclockwise), [0x0B, 0x00]),
        ]

        for (move, expected) in moves {
            let encoded = decoder.encode(move)
            XCTAssertEqual(encoded, expected, "Encoding \(move) should produce \(expected)")
        }
    }

    func testEncode_WithCenterOrientation() {
        let move = Move(face: .right, direction: .clockwise, centerOrientation: 0x06)

        let encoded = decoder.encode(move)

        XCTAssertEqual(encoded, [0x08, 0x06])
    }

    // MARK: - Round-trip Tests

    func testRoundTrip_AllMoves() throws {
        for code: UInt8 in 0x00 ... 0x0B {
            let originalMove = try decoder.decodeMove(code: code, centerOrientation: 0x03)
            let encoded = decoder.encode(originalMove)
            let decodedMove = try decoder.decodeMove(code: encoded[0], centerOrientation: encoded[1])

            XCTAssertEqual(originalMove.face, decodedMove.face)
            XCTAssertEqual(originalMove.direction, decodedMove.direction)
            XCTAssertEqual(originalMove.centerOrientation, decodedMove.centerOrientation)
        }
    }

    // MARK: - MoveCode Enum Tests

    func testMoveCode_AllCases() {
        let expectedNotations = [
            "B", "B'", "F", "F'", "U", "U'", "D", "D'", "R", "R'", "L", "L'",
        ]

        for (index, moveCode) in MoveDecoder.MoveCode.allCases.enumerated() {
            XCTAssertEqual(moveCode.notation, expectedNotations[index])
            XCTAssertEqual(moveCode.rawValue, UInt8(index))
        }
    }
}

// MARK: - Move Model Tests

final class MoveModelTests: XCTestCase {
    func testMove_Notation() {
        XCTAssertEqual(Move.R.notation, "R")
        XCTAssertEqual(Move.RPrime.notation, "R'")
        XCTAssertEqual(Move.L.notation, "L")
        XCTAssertEqual(Move.LPrime.notation, "L'")
        XCTAssertEqual(Move.U.notation, "U")
        XCTAssertEqual(Move.UPrime.notation, "U'")
        XCTAssertEqual(Move.D.notation, "D")
        XCTAssertEqual(Move.DPrime.notation, "D'")
        XCTAssertEqual(Move.F.notation, "F")
        XCTAssertEqual(Move.FPrime.notation, "F'")
        XCTAssertEqual(Move.B.notation, "B")
        XCTAssertEqual(Move.BPrime.notation, "B'")
    }

    func testMove_Inverted() {
        XCTAssertEqual(Move.R.inverted.notation, "R'")
        XCTAssertEqual(Move.RPrime.inverted.notation, "R")
        XCTAssertEqual(Move.U.inverted.notation, "U'")
        XCTAssertEqual(Move.UPrime.inverted.notation, "U")
    }

    func testMove_ClockwiseFactory() {
        let move = Move.clockwise(.right)
        XCTAssertEqual(move.face, .right)
        XCTAssertEqual(move.direction, .clockwise)
    }

    func testMove_CounterclockwiseFactory() {
        let move = Move.counterclockwise(.up)
        XCTAssertEqual(move.face, .up)
        XCTAssertEqual(move.direction, .counterclockwise)
    }

    func testMove_Description() {
        XCTAssertEqual(Move.R.description, "R")
        XCTAssertEqual(Move.UPrime.description, "U'")
    }

    func testMove_Equatable() {
        let move1 = Move(face: .right, direction: .clockwise)
        let move2 = Move(face: .right, direction: .clockwise)
        let move3 = Move(face: .right, direction: .counterclockwise)

        XCTAssertEqual(move1, move2)
        XCTAssertNotEqual(move1, move3)
    }

    func testMove_Hashable() {
        var set = Set<Move>()
        set.insert(Move.R)
        set.insert(Move.R) // Duplicate
        set.insert(Move.U)

        XCTAssertEqual(set.count, 2)
    }

    func testMoveDirection_Inverted() {
        XCTAssertEqual(MoveDirection.clockwise.inverted, .counterclockwise)
        XCTAssertEqual(MoveDirection.counterclockwise.inverted, .clockwise)
    }

    func testMoveDirection_NotationSuffix() {
        XCTAssertEqual(MoveDirection.clockwise.notationSuffix, "")
        XCTAssertEqual(MoveDirection.counterclockwise.notationSuffix, "'")
    }
}

// MARK: - MoveSequence Tests

final class MoveSequenceTests: XCTestCase {
    func testMoveSequence_Empty() {
        let sequence = MoveSequence()
        XCTAssertTrue(sequence.isEmpty)
        XCTAssertEqual(sequence.count, 0)
        XCTAssertEqual(sequence.description, "")
    }

    func testMoveSequence_Append() {
        var sequence = MoveSequence()
        sequence.append(Move.R)
        sequence.append(Move.U)

        XCTAssertEqual(sequence.count, 2)
        XCTAssertEqual(sequence.description, "R U")
    }

    func testMoveSequence_Clear() {
        var sequence = MoveSequence([Move.R, Move.U, Move.RPrime])
        sequence.clear()

        XCTAssertTrue(sequence.isEmpty)
    }

    func testMoveSequence_Inverted() {
        let sequence = MoveSequence([Move.R, Move.U, Move.F])
        let inverted = sequence.inverted

        XCTAssertEqual(inverted.description, "F' U' R'")
    }

    func testMoveSequence_Parse_SingleMove() {
        let sequence = MoveSequence.parse("R")

        XCTAssertNotNil(sequence)
        XCTAssertEqual(sequence?.count, 1)
        XCTAssertEqual(sequence?.moves[0].notation, "R")
    }

    func testMoveSequence_Parse_MultipleMoves() {
        let sequence = MoveSequence.parse("R U R' U'")

        XCTAssertNotNil(sequence)
        XCTAssertEqual(sequence?.count, 4)
        XCTAssertEqual(sequence?.description, "R U R' U'")
    }

    func testMoveSequence_Parse_InvalidMove() {
        let sequence = MoveSequence.parse("R X U")

        XCTAssertNil(sequence) // X is not a valid move
    }

    func testMoveSequence_Parse_Empty() {
        let sequence = MoveSequence.parse("")

        XCTAssertNotNil(sequence)
        XCTAssertEqual(sequence?.count, 0)
    }
}
