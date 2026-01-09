import XCTest
@testable import GoCubeKit

final class MessageParserTests: XCTestCase {

    var parser: MessageParser!

    override func setUp() {
        super.setUp()
        parser = MessageParser()
    }

    override func tearDown() {
        parser = nil
        super.tearDown()
    }

    // MARK: - Checksum Calculation Tests

    func testCalculateChecksum_EmptyArray() {
        let checksum = parser.calculateChecksum([])
        XCTAssertEqual(checksum, 0)
    }

    func testCalculateChecksum_SingleByte() {
        let checksum = parser.calculateChecksum([0x42])
        XCTAssertEqual(checksum, 0x42)
    }

    func testCalculateChecksum_MultipleBytesNoOverflow() {
        let checksum = parser.calculateChecksum([0x10, 0x20, 0x30])
        XCTAssertEqual(checksum, 0x60)
    }

    func testCalculateChecksum_OverflowWraps() {
        // 0xFF + 0x02 = 0x101, should wrap to 0x01
        let checksum = parser.calculateChecksum([0xFF, 0x02])
        XCTAssertEqual(checksum, 0x01)
    }

    func testCalculateChecksum_LargeSum() {
        // Sum = 0x2A + 0x02 + 0x01 + 0x08 + 0x00 = 0x35
        let checksum = parser.calculateChecksum([0x2A, 0x02, 0x01, 0x08, 0x00])
        XCTAssertEqual(checksum, 0x35)
    }

    // MARK: - Valid Message Parsing Tests

    func testParse_ValidRotationMessage() throws {
        // Build a valid rotation message: * + length(2) + type(0x01) + payload(0x08, 0x00) + checksum + CRLF
        // Type 0x01 = rotation, payload = move code 0x08 (R CW), center orientation 0x00
        let bytes: [UInt8] = [
            0x2A,       // Prefix (*)
            0x03,       // Length (type + payload = 3 bytes)
            0x01,       // Type (rotation)
            0x08,       // Move code (R CW)
            0x00,       // Center orientation
            0x36,       // Checksum: (0x2A + 0x03 + 0x01 + 0x08 + 0x00) & 0xFF = 0x36
            0x0D, 0x0A  // Suffix (CRLF)
        ]
        let data = Data(bytes)

        let message = try parser.parse(data)

        XCTAssertEqual(message.type, .rotation)
        XCTAssertEqual(message.payload, Data([0x08, 0x00]))
        XCTAssertEqual(message.rawData, data)
    }

    func testParse_ValidBatteryMessage() throws {
        // Battery message: type 0x05, payload = battery level (e.g., 85%)
        let bytes: [UInt8] = [
            0x2A,       // Prefix
            0x02,       // Length
            0x05,       // Type (battery)
            0x55,       // Battery level (85 = 0x55)
            0x86,       // Checksum: (0x2A + 0x02 + 0x05 + 0x55) & 0xFF = 0x86
            0x0D, 0x0A  // Suffix
        ]
        let data = Data(bytes)

        let message = try parser.parse(data)

        XCTAssertEqual(message.type, .battery)
        XCTAssertEqual(message.payload, Data([0x55]))
    }

    func testParse_ValidCubeStateMessage() throws {
        // State message: type 0x02, payload = 60 bytes (54 facelets + 6 orientations)
        // Length = type (1) + payload (60) = 61 = 0x3D
        var bytes: [UInt8] = [0x2A, 0x3D, 0x02] // Prefix, length (61), type
        // Add 60 bytes of payload (54 facelets + 6 center orientations)
        let payload = Array(repeating: UInt8(0), count: 60)
        bytes.append(contentsOf: payload)
        // Calculate checksum
        let checksumBytes = bytes
        let checksum = parser.calculateChecksum(checksumBytes)
        bytes.append(checksum)
        bytes.append(contentsOf: [0x0D, 0x0A])

        let data = Data(bytes)
        let message = try parser.parse(data)

        XCTAssertEqual(message.type, .cubeState)
        XCTAssertEqual(message.payload.count, 60)
    }

    func testParse_ValidOrientationMessage() throws {
        // Orientation message: type 0x03, payload = quaternion as ASCII
        let quaternionString = "0.1#0.2#0.3#0.4"
        let quaternionBytes = Array(quaternionString.utf8)

        var bytes: [UInt8] = [0x2A, UInt8(quaternionBytes.count + 1), 0x03]
        bytes.append(contentsOf: quaternionBytes)
        let checksum = parser.calculateChecksum(bytes)
        bytes.append(checksum)
        bytes.append(contentsOf: [0x0D, 0x0A])

        let data = Data(bytes)
        let message = try parser.parse(data)

        XCTAssertEqual(message.type, .orientation)
        XCTAssertEqual(String(data: message.payload, encoding: .utf8), quaternionString)
    }

    func testParse_ValidOfflineStatsMessage() throws {
        // Offline stats: type 0x07
        let statsString = "100#3600#5"
        let statsBytes = Array(statsString.utf8)

        var bytes: [UInt8] = [0x2A, UInt8(statsBytes.count + 1), 0x07]
        bytes.append(contentsOf: statsBytes)
        let checksum = parser.calculateChecksum(bytes)
        bytes.append(checksum)
        bytes.append(contentsOf: [0x0D, 0x0A])

        let data = Data(bytes)
        let message = try parser.parse(data)

        XCTAssertEqual(message.type, .offlineStats)
    }

    func testParse_ValidCubeTypeMessage() throws {
        // Cube type: type 0x08, payload = 0x00 (standard) or 0x01 (edge)
        let bytes: [UInt8] = [
            0x2A, 0x02, 0x08, 0x01,
            0x35, // Checksum
            0x0D, 0x0A
        ]
        let data = Data(bytes)

        let message = try parser.parse(data)

        XCTAssertEqual(message.type, .cubeType)
        XCTAssertEqual(message.payload, Data([0x01]))
    }

    // MARK: - Invalid Message Tests

    func testParse_MessageTooShort_ThrowsError() {
        let data = Data([0x2A, 0x01, 0x01]) // Only 3 bytes, minimum is 5

        XCTAssertThrowsError(try parser.parse(data)) { error in
            guard case GoCubeError.parsing(.messageTooShort(let length)) = error else {
                XCTFail("Expected messageTooShort error")
                return
            }
            XCTAssertEqual(length, 3)
        }
    }

    func testParse_EmptyData_ThrowsError() {
        let data = Data()

        XCTAssertThrowsError(try parser.parse(data)) { error in
            guard case GoCubeError.parsing(.messageTooShort(let length)) = error else {
                XCTFail("Expected messageTooShort error")
                return
            }
            XCTAssertEqual(length, 0)
        }
    }

    func testParse_InvalidPrefix_ThrowsError() {
        let bytes: [UInt8] = [0x00, 0x02, 0x05, 0x55, 0x5C, 0x0D, 0x0A] // Wrong prefix
        let data = Data(bytes)

        XCTAssertThrowsError(try parser.parse(data)) { error in
            guard case GoCubeError.parsing(.invalidPrefix(let received)) = error else {
                XCTFail("Expected invalidPrefix error")
                return
            }
            XCTAssertEqual(received, 0x00)
        }
    }

    func testParse_InvalidSuffix_ThrowsError() {
        let bytes: [UInt8] = [0x2A, 0x02, 0x05, 0x55, 0x86, 0x00, 0x00] // Wrong suffix
        let data = Data(bytes)

        XCTAssertThrowsError(try parser.parse(data)) { error in
            guard case GoCubeError.parsing(.invalidSuffix(let received)) = error else {
                XCTFail("Expected invalidSuffix error")
                return
            }
            _ = received // Received value may vary based on implementation
        }
    }

    func testParse_WrongSuffixFirstByte_ThrowsError() {
        let bytes: [UInt8] = [0x2A, 0x02, 0x05, 0x55, 0x86, 0x0E, 0x0A] // 0x0E instead of 0x0D
        let data = Data(bytes)

        XCTAssertThrowsError(try parser.parse(data)) { error in
            guard case GoCubeError.parsing(.invalidSuffix) = error else {
                XCTFail("Expected invalidSuffix error")
                return
            }
        }
    }

    func testParse_WrongSuffixSecondByte_ThrowsError() {
        let bytes: [UInt8] = [0x2A, 0x02, 0x05, 0x55, 0x86, 0x0D, 0x0B] // 0x0B instead of 0x0A
        let data = Data(bytes)

        XCTAssertThrowsError(try parser.parse(data)) { error in
            guard case GoCubeError.parsing(.invalidSuffix) = error else {
                XCTFail("Expected invalidSuffix error")
                return
            }
        }
    }

    func testParse_ChecksumMismatch_ThrowsError() {
        let bytes: [UInt8] = [0x2A, 0x02, 0x05, 0x55, 0xFF, 0x0D, 0x0A] // Wrong checksum (0xFF)
        let data = Data(bytes)

        XCTAssertThrowsError(try parser.parse(data)) { error in
            guard case GoCubeError.parsing(.checksumMismatch(let expected, let received)) = error else {
                XCTFail("Expected checksumMismatch error")
                return
            }
            XCTAssertEqual(expected, 0x86)
            XCTAssertEqual(received, 0xFF)
        }
    }

    func testParse_UnknownMessageType_ThrowsError() {
        // Valid frame structure but unknown type 0xFF
        let bytes: [UInt8] = [0x2A, 0x01, 0xFF, 0x2A, 0x0D, 0x0A]
        let data = Data(bytes)

        XCTAssertThrowsError(try parser.parse(data)) { error in
            guard case GoCubeError.parsing(.unknownMessageType(let type)) = error else {
                XCTFail("Expected unknownMessageType error")
                return
            }
            XCTAssertEqual(type, 0xFF)
        }
    }

    func testParse_LengthMismatch_ThrowsError() {
        // Length says 5 bytes (type + 4 payload), but only 2 payload bytes provided
        let bytes: [UInt8] = [0x2A, 0x05, 0x05, 0x55, 0x00, 0x0D, 0x0A]
        let data = Data(bytes)

        XCTAssertThrowsError(try parser.parse(data)) { error in
            guard case GoCubeError.parsing(.payloadLengthMismatch) = error else {
                XCTFail("Expected payloadLengthMismatch error")
                return
            }
        }
    }

    // MARK: - Build Command Frame Tests

    func testBuildCommandFrame_GetBattery() {
        let frame = parser.buildCommandFrame(.getBattery)

        XCTAssertEqual(frame.count, 1)
        XCTAssertEqual(frame[0], 0x32) // getBattery command
    }

    func testBuildCommandFrame_GetCubeState() {
        let frame = parser.buildCommandFrame(.getCubeState)

        XCTAssertEqual(frame.count, 1)
        XCTAssertEqual(frame[0], 0x33)
    }

    func testBuildCommandFrame_ResetToSolved() {
        let frame = parser.buildCommandFrame(.resetToSolved)

        XCTAssertEqual(frame.count, 1)
        XCTAssertEqual(frame[0], 0x35)
    }

    func testBuildCommandFrame_EnableOrientation() {
        let frame = parser.buildCommandFrame(.enableOrientation)

        XCTAssertEqual(frame.count, 1)
        XCTAssertEqual(frame[0], 0x38)
    }

    func testBuildCommandFrame_DisableOrientation() {
        let frame = parser.buildCommandFrame(.disableOrientation)

        XCTAssertEqual(frame.count, 1)
        XCTAssertEqual(frame[0], 0x37)
    }

    func testBuildCommandFrame_AllCommands() {
        // Verify all commands produce single-byte frames with correct values
        let expectedValues: [(GoCubeCommand, UInt8)] = [
            (.getBattery, 0x32),
            (.getCubeState, 0x33),
            (.reboot, 0x34),
            (.resetToSolved, 0x35),
            (.disableOrientation, 0x37),
            (.enableOrientation, 0x38),
            (.getOfflineStats, 0x39),
            (.flashLEDNormal, 0x41),
            (.toggleAnimatedBacklight, 0x42),
            (.flashLEDSlow, 0x43),
            (.toggleBacklight, 0x44),
            (.getCubeType, 0x56),
            (.calibrateOrientation, 0x57)
        ]

        for (command, expected) in expectedValues {
            let frame = parser.buildCommandFrame(command)
            XCTAssertEqual(frame[0], expected, "Command \(command) should produce byte \(expected)")
        }
    }

    // MARK: - Edge Cases

    func testParse_MinimumValidMessage() throws {
        // Minimum valid message: prefix + length(1) + type + checksum + suffix
        // Type with no payload
        let bytes: [UInt8] = [
            0x2A,       // Prefix
            0x01,       // Length (just type)
            0x05,       // Type (battery - though no payload is unusual)
            0x30,       // Checksum
            0x0D, 0x0A  // Suffix
        ]
        let data = Data(bytes)

        let message = try parser.parse(data)

        XCTAssertEqual(message.type, .battery)
        XCTAssertEqual(message.payload.count, 0)
    }

    func testParse_MaxLengthByte() throws {
        // Test with length = 255 (max uint8)
        var bytes: [UInt8] = [0x2A, 0xFF, 0x05]
        let payload = Array(repeating: UInt8(0x42), count: 254)
        bytes.append(contentsOf: payload)
        let checksum = parser.calculateChecksum(bytes)
        bytes.append(checksum)
        bytes.append(contentsOf: [0x0D, 0x0A])

        let data = Data(bytes)
        let message = try parser.parse(data)

        XCTAssertEqual(message.type, .battery)
        XCTAssertEqual(message.payload.count, 254)
    }
}

// MARK: - MessageBuffer Tests

final class MessageBufferTests: XCTestCase {

    var buffer: MessageBuffer!

    override func setUp() {
        super.setUp()
        buffer = MessageBuffer()
    }

    override func tearDown() {
        buffer = nil
        super.tearDown()
    }

    func testAppend_CompleteMessage_ReturnsMessage() async {
        let bytes: [UInt8] = [0x2A, 0x02, 0x05, 0x55, 0x86, 0x0D, 0x0A]
        let data = Data(bytes)

        let messages = await buffer.append(data)

        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages[0], data)
    }

    func testAppend_PartialMessage_ReturnsEmpty() async {
        let partialData = Data([0x2A, 0x02, 0x05])

        let messages = await buffer.append(partialData)

        XCTAssertEqual(messages.count, 0)
    }

    func testAppend_TwoPartialMessages_ReturnsMerged() async {
        let part1 = Data([0x2A, 0x02, 0x05])
        let part2 = Data([0x55, 0x86, 0x0D, 0x0A])

        let messages1 = await buffer.append(part1)
        XCTAssertEqual(messages1.count, 0)

        let messages2 = await buffer.append(part2)
        XCTAssertEqual(messages2.count, 1)
    }

    func testAppend_TwoCompleteMessages_ReturnsBoth() async {
        let msg1: [UInt8] = [0x2A, 0x02, 0x05, 0x55, 0x86, 0x0D, 0x0A]
        let msg2: [UInt8] = [0x2A, 0x02, 0x05, 0x64, 0x95, 0x0D, 0x0A]
        var combined = msg1
        combined.append(contentsOf: msg2)

        let messages = await buffer.append(Data(combined))

        XCTAssertEqual(messages.count, 2)
    }

    func testAppend_GarbageBeforeMessage_SkipsGarbage() async {
        let garbage: [UInt8] = [0xFF, 0xFE, 0xFD]
        let validMessage: [UInt8] = [0x2A, 0x02, 0x05, 0x55, 0x86, 0x0D, 0x0A]
        var combined = garbage
        combined.append(contentsOf: validMessage)

        let messages = await buffer.append(Data(combined))

        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages[0], Data(validMessage))
    }

    func testAppend_GarbageBetweenMessages_SkipsGarbage() async {
        let msg1: [UInt8] = [0x2A, 0x02, 0x05, 0x55, 0x86, 0x0D, 0x0A]
        let garbage: [UInt8] = [0xFF, 0xFE]
        let msg2: [UInt8] = [0x2A, 0x02, 0x05, 0x64, 0x95, 0x0D, 0x0A]
        var combined = msg1
        combined.append(contentsOf: garbage)
        combined.append(contentsOf: msg2)

        let messages = await buffer.append(Data(combined))

        XCTAssertEqual(messages.count, 2)
    }

    func testClear_EmptiesBuffer() async {
        let partialData = Data([0x2A, 0x02, 0x05])
        _ = await buffer.append(partialData)

        await buffer.clear()

        // After clear, adding more data shouldn't complete the previous message
        let moreData = Data([0x55, 0x86, 0x0D, 0x0A])
        let messages = await buffer.append(moreData)

        XCTAssertEqual(messages.count, 0)
    }

    func testAppend_ByteByByte_EventuallyReturnsMessage() async {
        let bytes: [UInt8] = [0x2A, 0x02, 0x05, 0x55, 0x86, 0x0D, 0x0A]

        var allMessages: [Data] = []
        for byte in bytes {
            let messages = await buffer.append(Data([byte]))
            allMessages.append(contentsOf: messages)
        }

        XCTAssertEqual(allMessages.count, 1)
    }

    func testAppend_InvalidSuffix_SkipsInvalidFrame() async {
        // Message with wrong suffix followed by valid message
        let invalid: [UInt8] = [0x2A, 0x02, 0x05, 0x55, 0x86, 0x00, 0x00]
        let valid: [UInt8] = [0x2A, 0x02, 0x05, 0x64, 0x95, 0x0D, 0x0A]
        var combined = invalid
        combined.append(contentsOf: valid)

        let messages = await buffer.append(Data(combined))

        // Should eventually find the valid message
        XCTAssertGreaterThanOrEqual(messages.count, 1)
    }
}
