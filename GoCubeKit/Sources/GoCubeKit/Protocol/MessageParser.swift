import Foundation

/// Represents a parsed message from the GoCube
public struct GoCubeMessage: Equatable, Sendable {
    /// The type of message
    public let type: GoCubeMessageType

    /// The raw payload bytes (excluding header and footer)
    public let payload: Data

    /// The raw bytes of the entire message
    public let rawData: Data

    public init(type: GoCubeMessageType, payload: Data, rawData: Data) {
        self.type = type
        self.payload = payload
        self.rawData = rawData
    }
}

/// Parses raw BLE data into GoCube messages
public struct MessageParser: Sendable {
    public init() {}

    /// Parse a raw data buffer into a GoCube message
    /// - Parameter data: Raw bytes received from BLE notification
    /// - Returns: Parsed message
    /// - Throws: GoCubeError.protocol if parsing fails
    public func parse(_ data: Data) throws -> GoCubeMessage {
        let bytes = Array(data)

        // Check minimum length
        guard bytes.count >= GoCubeFrame.minimumLength else {
            throw GoCubeError.parsing(.messageTooShort(length: bytes.count))
        }

        // Validate prefix
        guard bytes[0] == GoCubeFrame.prefix else {
            throw GoCubeError.parsing(.invalidPrefix(received: bytes[0]))
        }

        // Validate suffix
        let suffixStart = bytes.count - 2
        let receivedSuffix = Array(bytes[suffixStart...])
        guard receivedSuffix == GoCubeFrame.suffix else {
            throw GoCubeError.parsing(.invalidSuffix(received: receivedSuffix))
        }

        // Extract length and validate
        let declaredLength = Int(bytes[GoCubeFrame.lengthOffset])
        let expectedTotalLength = 1 + 1 + declaredLength + 1 + 2 // prefix + length + payload(incl type) + checksum + suffix
        guard bytes.count == expectedTotalLength else {
            throw GoCubeError.parsing(.payloadLengthMismatch(
                expected: expectedTotalLength,
                actual: bytes.count
            ))
        }

        // Validate checksum (sum of all bytes before checksum, mod 256)
        let checksumIndex = bytes.count - 3
        let expectedChecksum = bytes[checksumIndex]
        let calculatedChecksum = calculateChecksum(Array(bytes[0 ..< checksumIndex]))
        guard expectedChecksum == calculatedChecksum else {
            throw GoCubeError.parsing(.checksumMismatch(
                expected: calculatedChecksum,
                received: expectedChecksum
            ))
        }

        // Extract message type
        let typeRaw = bytes[GoCubeFrame.typeOffset]
        guard let messageType = GoCubeMessageType(rawValue: typeRaw) else {
            throw GoCubeError.parsing(.unknownMessageType(type: typeRaw))
        }

        // Extract payload (everything between type and checksum)
        let payloadStart = GoCubeFrame.payloadOffset
        let payloadEnd = checksumIndex
        let payload = Data(bytes[payloadStart ..< payloadEnd])

        return GoCubeMessage(type: messageType, payload: payload, rawData: data)
    }

    /// Calculate checksum for a byte array
    /// - Parameter bytes: Bytes to calculate checksum for
    /// - Returns: Checksum value (sum mod 256)
    public func calculateChecksum(_ bytes: [UInt8]) -> UInt8 {
        var sum: UInt32 = 0
        for byte in bytes {
            sum += UInt32(byte)
        }
        return UInt8(sum & 0xFF)
    }

    /// Build a command frame to send to the cube
    /// - Parameter command: The command to send
    /// - Returns: Complete frame data ready to write to BLE characteristic
    public func buildCommandFrame(_ command: GoCubeCommand) -> Data {
        buildCommandFrame(commandByte: command.rawValue, payload: [])
    }

    /// Build a command frame with custom payload
    /// - Parameters:
    ///   - commandByte: The command byte
    ///   - payload: Additional payload bytes
    /// - Returns: Complete frame data
    public func buildCommandFrame(commandByte: UInt8, payload: [UInt8]) -> Data {
        var frame: [UInt8] = []

        // For simple commands, we just send the command byte directly
        // The GoCube protocol for commands is simpler than responses
        frame.append(commandByte)
        frame.append(contentsOf: payload)

        return Data(frame)
    }
}

// MARK: - Message Buffer Actor

/// Actor that accumulates partial BLE messages and extracts complete frames
/// Thread-safe by design using Swift's actor model
public actor MessageBuffer {
    private var buffer: [UInt8] = []

    public init() {}

    /// Add data to the buffer and extract any complete messages
    /// - Parameter data: New data received from BLE
    /// - Returns: Array of complete raw message data
    public func append(_ data: Data) -> [Data] {
        buffer.append(contentsOf: data)
        return extractCompleteMessages()
    }

    /// Clear the buffer
    public func clear() {
        buffer.removeAll()
    }

    /// Current buffer size (for debugging)
    public var count: Int {
        buffer.count
    }

    private func extractCompleteMessages() -> [Data] {
        var messages: [Data] = []

        while let messageData = extractOneMessage() {
            messages.append(messageData)
        }

        return messages
    }

    private func extractOneMessage() -> Data? {
        // Find the start marker
        guard let startIndex = buffer.firstIndex(of: GoCubeFrame.prefix) else {
            buffer.removeAll()
            return nil
        }

        // Remove any garbage before start marker
        if startIndex > 0 {
            buffer.removeFirst(startIndex)
        }

        // Need at least minimum length
        guard buffer.count >= GoCubeFrame.minimumLength else {
            return nil
        }

        // Get declared length
        let declaredLength = Int(buffer[GoCubeFrame.lengthOffset])
        let expectedTotalLength = 1 + 1 + declaredLength + 1 + 2 // prefix + length + payload + checksum + suffix

        // Wait for complete message
        guard buffer.count >= expectedTotalLength else {
            return nil
        }

        // Verify suffix
        let suffixStart = expectedTotalLength - 2
        guard buffer[suffixStart] == GoCubeFrame.suffix[0],
              buffer[suffixStart + 1] == GoCubeFrame.suffix[1]
        else {
            // Invalid frame, skip this start marker and try again
            buffer.removeFirst()
            return extractOneMessage()
        }

        // Extract the complete message
        let messageBytes = Array(buffer.prefix(expectedTotalLength))
        buffer.removeFirst(expectedTotalLength)

        return Data(messageBytes)
    }
}
