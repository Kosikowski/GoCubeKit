@testable import GoCubeKit
import XCTest

/// Integration tests that verify the full message processing pipeline
final class IntegrationTests: XCTestCase {
    var messageParser: MessageParser!
    var moveDecoder: MoveDecoder!
    var stateDecoder: StateDecoder!
    var quaternionDecoder: QuaternionDecoder!

    override func setUp() {
        super.setUp()
        messageParser = MessageParser()
        moveDecoder = MoveDecoder()
        stateDecoder = StateDecoder()
        quaternionDecoder = QuaternionDecoder()
    }

    override func tearDown() {
        messageParser = nil
        moveDecoder = nil
        stateDecoder = nil
        quaternionDecoder = nil
        super.tearDown()
    }

    // MARK: - Full Pipeline Tests

    func testFullPipeline_RotationMessage() throws {
        // Simulate receiving a rotation message from the cube
        // Type 0x01, payload: R CW (0x08, 0x00)
        let rawBytes: [UInt8] = [0x2A, 0x03, 0x01, 0x08, 0x00, 0x36, 0x0D, 0x0A]
        let rawData = Data(rawBytes)

        // Step 1: Parse the message
        let message = try messageParser.parse(rawData)
        XCTAssertEqual(message.type, .rotation)

        // Step 2: Decode the moves
        let moves = try moveDecoder.decode(message.payload)
        XCTAssertEqual(moves.count, 1)
        XCTAssertEqual(moves[0].face, .right)
        XCTAssertEqual(moves[0].direction, .clockwise)
        XCTAssertEqual(moves[0].notation, "R")
    }

    func testFullPipeline_MultipleRotations() throws {
        // Simulate a sequence of moves: R U R' U'
        let moves: [(UInt8, UInt8)] = [
            (0x08, 0x00), // R
            (0x04, 0x00), // U
            (0x09, 0x00), // R'
            (0x05, 0x00), // U'
        ]

        var payloadBytes: [UInt8] = []
        for (code, orientation) in moves {
            payloadBytes.append(code)
            payloadBytes.append(orientation)
        }

        // Build the message frame
        var frameBytes: [UInt8] = [0x2A, UInt8(payloadBytes.count + 1), 0x01]
        frameBytes.append(contentsOf: payloadBytes)
        let checksum = messageParser.calculateChecksum(frameBytes)
        frameBytes.append(checksum)
        frameBytes.append(contentsOf: [0x0D, 0x0A])

        // Parse and decode
        let message = try messageParser.parse(Data(frameBytes))
        let decodedMoves = try moveDecoder.decode(message.payload)

        XCTAssertEqual(decodedMoves.count, 4)
        XCTAssertEqual(decodedMoves.map(\.notation), ["R", "U", "R'", "U'"])
    }

    func testFullPipeline_CubeStateMessage() throws {
        // Build a solved cube state message
        let statePayload = Array(StateDecoder.solvedPayload)

        // Build the message frame
        var frameBytes: [UInt8] = [0x2A, UInt8(statePayload.count + 1), 0x02]
        frameBytes.append(contentsOf: statePayload)
        let checksum = messageParser.calculateChecksum(frameBytes)
        frameBytes.append(checksum)
        frameBytes.append(contentsOf: [0x0D, 0x0A])

        // Parse and decode
        let message = try messageParser.parse(Data(frameBytes))
        XCTAssertEqual(message.type, .cubeState)

        let state = try stateDecoder.decode(message.payload)
        XCTAssertTrue(state.isSolved)
    }

    func testFullPipeline_BatteryMessage() throws {
        // Battery at 75%
        let rawBytes: [UInt8] = [0x2A, 0x02, 0x05, 0x4B, 0x7C, 0x0D, 0x0A]
        let rawData = Data(rawBytes)

        let message = try messageParser.parse(rawData)
        XCTAssertEqual(message.type, .battery)
        XCTAssertEqual(message.payload.first, 0x4B) // 75
    }

    func testFullPipeline_OrientationMessage() throws {
        // Build an orientation message
        let quaternionString = "0.123#0.456#0.789#0.321"
        let quaternionBytes = Array(quaternionString.utf8)

        var frameBytes: [UInt8] = [0x2A, UInt8(quaternionBytes.count + 1), 0x03]
        frameBytes.append(contentsOf: quaternionBytes)
        let checksum = messageParser.calculateChecksum(frameBytes)
        frameBytes.append(checksum)
        frameBytes.append(contentsOf: [0x0D, 0x0A])

        // Parse and decode
        let message = try messageParser.parse(Data(frameBytes))
        XCTAssertEqual(message.type, .orientation)

        let quaternion = try quaternionDecoder.decode(message.payload)
        XCTAssertEqual(quaternion.x, 0.123, accuracy: 0.001)
        XCTAssertEqual(quaternion.y, 0.456, accuracy: 0.001)
        XCTAssertEqual(quaternion.z, 0.789, accuracy: 0.001)
        XCTAssertEqual(quaternion.w, 0.321, accuracy: 0.001)
    }

    // MARK: - Message Buffer Integration Tests

    func testMessageBuffer_FragmentedMessages() async throws {
        let buffer = MessageBuffer()

        // Build two complete messages
        let msg1Bytes: [UInt8] = [0x2A, 0x02, 0x05, 0x55, 0x86, 0x0D, 0x0A]
        let msg2Bytes: [UInt8] = [0x2A, 0x02, 0x05, 0x64, 0x95, 0x0D, 0x0A]

        // Split them into fragments
        let fragment1 = Data(msg1Bytes[0 ..< 3])
        let fragment2 = Data(msg1Bytes[3...] + msg2Bytes[0 ..< 4])
        let fragment3 = Data(msg2Bytes[4...])

        // Process fragments
        let result1 = await buffer.append(fragment1)
        XCTAssertEqual(result1.count, 0)

        let result2 = await buffer.append(fragment2)
        XCTAssertEqual(result2.count, 1)

        let result3 = await buffer.append(fragment3)
        XCTAssertEqual(result3.count, 1)

        // Verify messages can be parsed
        let message1 = try messageParser.parse(result2[0])
        let message2 = try messageParser.parse(result3[0])

        XCTAssertEqual(message1.type, .battery)
        XCTAssertEqual(message2.type, .battery)
    }

    func testMessageBuffer_RapidFireMessages() async throws {
        let buffer = MessageBuffer()

        // Simulate rapid-fire rotation events
        var allData = Data()
        for code: UInt8 in [0x08, 0x04, 0x09, 0x05] { // R U R' U'
            let msg = buildRotationMessage(code: code, orientation: 0x00)
            allData.append(msg)
        }

        // Process all at once
        let messages = await buffer.append(allData)

        XCTAssertEqual(messages.count, 4)

        // Verify each message
        for (_, msgData) in messages.enumerated() {
            let message = try messageParser.parse(msgData)
            XCTAssertEqual(message.type, .rotation)

            let moves = try moveDecoder.decode(message.payload)
            XCTAssertEqual(moves.count, 1)
        }
    }

    // MARK: - Error Recovery Tests

    func testErrorRecovery_CorruptedMessageFollowedByValid() async throws {
        let buffer = MessageBuffer()

        // Corrupted message (bad suffix) followed by valid message
        let corrupted = Data([0x2A, 0x02, 0x05, 0x55, 0x86, 0xFF, 0xFF])
        let valid: [UInt8] = [0x2A, 0x02, 0x05, 0x64, 0x95, 0x0D, 0x0A]

        var combined = corrupted
        combined.append(contentsOf: valid)

        let messages = await buffer.append(combined)

        // Should recover and find the valid message
        XCTAssertGreaterThanOrEqual(messages.count, 1)

        // Find a parseable message
        var foundValid = false
        for msgData in messages {
            if let message = try? messageParser.parse(msgData) {
                XCTAssertEqual(message.type, .battery)
                foundValid = true
            }
        }
        XCTAssertTrue(foundValid, "Should have recovered and found valid message")
    }

    // MARK: - Command Building Tests

    func testBuildAllCommands() {
        let commands: [GoCubeCommand] = [
            .getBattery,
            .getCubeState,
            .reboot,
            .resetToSolved,
            .disableOrientation,
            .enableOrientation,
            .getOfflineStats,
            .flashLEDNormal,
            .toggleAnimatedBacklight,
            .flashLEDSlow,
            .toggleBacklight,
            .getCubeType,
            .calibrateOrientation,
        ]

        for command in commands {
            let frame = messageParser.buildCommandFrame(command)
            XCTAssertGreaterThan(frame.count, 0, "Command \(command) should produce non-empty frame")
            XCTAssertEqual(frame[0], command.rawValue, "Command byte should match")
        }
    }

    // MARK: - Realistic Scenario Tests

    func testScenario_SolvingSequence() throws {
        // Simulate a typical solving sequence
        let solvingMoves: [(String, UInt8)] = [
            ("R", 0x08), ("U", 0x04), ("R'", 0x09), ("U'", 0x05),
            ("F", 0x02), ("R", 0x08), ("U", 0x04), ("R'", 0x09),
            ("U'", 0x05), ("F'", 0x03),
        ]

        var sequence = MoveSequence()

        for (expectedNotation, code) in solvingMoves {
            let msgData = buildRotationMessage(code: code, orientation: 0x00)
            let message = try messageParser.parse(msgData)
            let moves = try moveDecoder.decode(message.payload)

            XCTAssertEqual(moves.count, 1)
            XCTAssertEqual(moves[0].notation, expectedNotation)

            sequence.append(moves[0])
        }

        XCTAssertEqual(sequence.count, 10)
    }

    func testScenario_OrientationTracking() async throws {
        // Simulate orientation updates coming in at 15 Hz
        let smoother = QuaternionSmoother(smoothingFactor: 0.5)

        let orientations = [
            (0.0, 0.0, 0.0, 1.0),
            (0.01, 0.01, 0.0, 0.9999),
            (0.02, 0.02, 0.0, 0.9996),
            (0.03, 0.03, 0.0, 0.9991),
        ]

        var lastSmoothed: Quaternion?

        for (x, y, z, w) in orientations {
            let quaternionString = "\(x)#\(y)#\(z)#\(w)"
            let msgData = buildOrientationMessage(quaternionString: quaternionString)
            let message = try messageParser.parse(msgData)
            let quaternion = try quaternionDecoder.decode(message.payload)

            let smoothed = await smoother.update(quaternion)
            lastSmoothed = smoothed
        }

        XCTAssertNotNil(lastSmoothed)
        XCTAssertTrue(lastSmoothed!.isNormalized || lastSmoothed!.magnitude < 1.1)
    }

    // MARK: - Helper Methods

    private func buildRotationMessage(code: UInt8, orientation: UInt8) -> Data {
        var frameBytes: [UInt8] = [0x2A, 0x03, 0x01, code, orientation]
        let checksum = messageParser.calculateChecksum(frameBytes)
        frameBytes.append(checksum)
        frameBytes.append(contentsOf: [0x0D, 0x0A])
        return Data(frameBytes)
    }

    private func buildOrientationMessage(quaternionString: String) -> Data {
        let quaternionBytes = Array(quaternionString.utf8)
        var frameBytes: [UInt8] = [0x2A, UInt8(quaternionBytes.count + 1), 0x03]
        frameBytes.append(contentsOf: quaternionBytes)
        let checksum = messageParser.calculateChecksum(frameBytes)
        frameBytes.append(checksum)
        frameBytes.append(contentsOf: [0x0D, 0x0A])
        return Data(frameBytes)
    }
}

// MARK: - BLE Constants Tests

final class BLEConstantsTests: XCTestCase {
    func testServiceUUID() {
        let uuid = GoCubeBLE.serviceUUID
        XCTAssertEqual(uuid.uuidString.lowercased(), "6e400001-b5a3-f393-e0a9-e50e24dcca9e")
    }

    func testWriteCharacteristicUUID() {
        let uuid = GoCubeBLE.writeCharacteristicUUID
        XCTAssertEqual(uuid.uuidString.lowercased(), "6e400002-b5a3-f393-e0a9-e50e24dcca9e")
    }

    func testNotifyCharacteristicUUID() {
        let uuid = GoCubeBLE.notifyCharacteristicUUID
        XCTAssertEqual(uuid.uuidString.lowercased(), "6e400003-b5a3-f393-e0a9-e50e24dcca9e")
    }

    func testDeviceNamePrefix() {
        XCTAssertEqual(GoCubeBLE.deviceNamePrefix, "GoCube")
    }

    func testFrameConstants() {
        XCTAssertEqual(GoCubeFrame.prefix, 0x2A)
        XCTAssertEqual(GoCubeFrame.suffix, [0x0D, 0x0A])
        XCTAssertEqual(GoCubeFrame.minimumLength, 5)
    }

    func testGoCubeType() {
        XCTAssertEqual(GoCubeType.standard.rawValue, 0x00)
        XCTAssertEqual(GoCubeType.edge.rawValue, 0x01)
        XCTAssertEqual(GoCubeType(rawValue: 0x00), .standard)
        XCTAssertEqual(GoCubeType(rawValue: 0x01), .edge)
        XCTAssertEqual(GoCubeType(rawValue: 0xFF), .unknown)
    }

    func testCommandRawValues() {
        XCTAssertEqual(GoCubeCommand.getBattery.rawValue, 0x32)
        XCTAssertEqual(GoCubeCommand.getCubeState.rawValue, 0x33)
        XCTAssertEqual(GoCubeCommand.reboot.rawValue, 0x34)
        XCTAssertEqual(GoCubeCommand.resetToSolved.rawValue, 0x35)
        XCTAssertEqual(GoCubeCommand.disableOrientation.rawValue, 0x37)
        XCTAssertEqual(GoCubeCommand.enableOrientation.rawValue, 0x38)
        XCTAssertEqual(GoCubeCommand.getOfflineStats.rawValue, 0x39)
        XCTAssertEqual(GoCubeCommand.flashLEDNormal.rawValue, 0x41)
        XCTAssertEqual(GoCubeCommand.toggleAnimatedBacklight.rawValue, 0x42)
        XCTAssertEqual(GoCubeCommand.flashLEDSlow.rawValue, 0x43)
        XCTAssertEqual(GoCubeCommand.toggleBacklight.rawValue, 0x44)
        XCTAssertEqual(GoCubeCommand.getCubeType.rawValue, 0x56)
        XCTAssertEqual(GoCubeCommand.calibrateOrientation.rawValue, 0x57)
    }

    func testMessageTypeRawValues() {
        XCTAssertEqual(GoCubeMessageType.rotation.rawValue, 0x01)
        XCTAssertEqual(GoCubeMessageType.cubeState.rawValue, 0x02)
        XCTAssertEqual(GoCubeMessageType.orientation.rawValue, 0x03)
        XCTAssertEqual(GoCubeMessageType.battery.rawValue, 0x05)
        XCTAssertEqual(GoCubeMessageType.offlineStats.rawValue, 0x07)
        XCTAssertEqual(GoCubeMessageType.cubeType.rawValue, 0x08)
    }
}

// MARK: - Error Type Tests

final class ErrorTypeTests: XCTestCase {
    func testGoCubeParsingError_MessageTooShort_Equatable() {
        let error1 = GoCubeError.parsing(.messageTooShort(length: 3))
        let error2 = GoCubeError.parsing(.messageTooShort(length: 3))
        let error3 = GoCubeError.parsing(.messageTooShort(length: 4))

        XCTAssertEqual(error1, error2)
        XCTAssertNotEqual(error1, error3)
    }

    func testGoCubeParsingError_InvalidMoveCode_Equatable() {
        let error1 = GoCubeError.parsing(.invalidMoveCode(code: 0x0C))
        let error2 = GoCubeError.parsing(.invalidMoveCode(code: 0x0C))
        let error3 = GoCubeError.parsing(.invalidMoveCode(code: 0x0D))

        XCTAssertEqual(error1, error2)
        XCTAssertNotEqual(error1, error3)
    }

    func testGoCubeParsingError_PayloadLengthMismatch_Equatable() {
        let error1 = GoCubeError.parsing(.payloadLengthMismatch(expected: 60, actual: 59))
        let error2 = GoCubeError.parsing(.payloadLengthMismatch(expected: 60, actual: 59))
        let error3 = GoCubeError.parsing(.payloadLengthMismatch(expected: 60, actual: 58))

        XCTAssertEqual(error1, error2)
        XCTAssertNotEqual(error1, error3)
    }

    func testGoCubeParsingError_InvalidQuaternionComponentCount_Equatable() {
        let error1 = GoCubeError.parsing(.invalidQuaternionComponentCount(expected: 4, actual: 3))
        let error2 = GoCubeError.parsing(.invalidQuaternionComponentCount(expected: 4, actual: 3))
        let error3 = GoCubeError.parsing(.invalidQuaternionComponentCount(expected: 4, actual: 5))

        XCTAssertEqual(error1, error2)
        XCTAssertNotEqual(error1, error3)
    }

    func testGoCubeError_LocalizedDescription() {
        XCTAssertNotNil(GoCubeError.notConnected.errorDescription)
        XCTAssertNotNil(GoCubeError.timeout.errorDescription)
        XCTAssertNotNil(GoCubeError.bluetoothPoweredOff.errorDescription)
        XCTAssertNotNil(GoCubeError.connectionFailed("test").errorDescription)
    }
}
