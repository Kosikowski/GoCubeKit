import Foundation

/// Unified error type for all GoCubeKit errors
public enum GoCubeError: Error, Equatable, Sendable {
    // MARK: - Bluetooth Errors

    case bluetooth(BluetoothError)

    // MARK: - Connection Errors

    case connection(ConnectionError)

    // MARK: - Protocol Errors

    case parsing(ProtocolError)

    // MARK: - Convenience Accessors

    public static var bluetoothUnavailable: GoCubeError {
        .bluetooth(.unavailable)
    }

    public static var bluetoothUnauthorized: GoCubeError {
        .bluetooth(.unauthorized)
    }

    public static var bluetoothPoweredOff: GoCubeError {
        .bluetooth(.poweredOff)
    }

    public static var notConnected: GoCubeError {
        .connection(.notConnected)
    }

    public static var timeout: GoCubeError {
        .connection(.timeout)
    }

    public static func connectionFailed(_ reason: String) -> GoCubeError {
        .connection(.failed(reason))
    }
}

// MARK: - Bluetooth Errors

public extension GoCubeError {
    /// Errors related to Bluetooth hardware and permissions
    enum BluetoothError: Error, Equatable, Sendable {
        /// Bluetooth hardware is not available on this device
        case unavailable

        /// App is not authorized to use Bluetooth
        case unauthorized

        /// Bluetooth is powered off
        case poweredOff

        /// Bluetooth is in an unsupported state
        case unsupportedState(String)
    }
}

// MARK: - Connection Errors

public extension GoCubeError {
    /// Errors related to device connection
    enum ConnectionError: Error, Equatable, Sendable {
        /// No device is currently connected
        case notConnected

        /// Device was not found during scanning
        case deviceNotFound

        /// Connection attempt failed
        case failed(String)

        /// Device disconnected unexpectedly
        case disconnected

        /// Required BLE service was not found on device
        case serviceNotFound

        /// Required BLE characteristic was not found
        case characteristicNotFound

        /// Operation timed out
        case timeout

        /// Failed to write data to device
        case writeFailed(String)
    }
}

// MARK: - Protocol Errors

public extension GoCubeError {
    /// Errors related to message parsing and protocol handling
    enum ProtocolError: Error, Equatable, Sendable {
        // MARK: - Message Parsing

        /// Message is too short to be valid
        case messageTooShort(length: Int)

        /// Invalid message prefix byte
        case invalidPrefix(received: UInt8)

        /// Invalid message suffix bytes
        case invalidSuffix(received: [UInt8])

        /// Checksum validation failed
        case checksumMismatch(expected: UInt8, received: UInt8)

        /// Unknown message type received
        case unknownMessageType(type: UInt8)

        /// Payload length doesn't match declared length
        case payloadLengthMismatch(expected: Int, actual: Int)

        /// Generic invalid payload
        case invalidPayload(reason: String)

        // MARK: - Move Decoding

        /// Move payload was empty
        case emptyMovePayload

        /// Invalid move code received
        case invalidMoveCode(code: UInt8)

        /// Move payload has odd length (should be pairs)
        case oddMovePayloadLength(length: Int)

        // MARK: - State Decoding

        /// Invalid color value in cube state
        case invalidColorValue(value: UInt8, position: Int)

        /// Invalid center orientation value
        case invalidOrientationValue(value: UInt8, face: Int)

        // MARK: - Quaternion Decoding

        /// Failed to decode quaternion string
        case invalidQuaternionFormat(reason: String)

        /// Quaternion doesn't have expected component count
        case invalidQuaternionComponentCount(expected: Int, actual: Int)

        /// Failed to parse quaternion component as number
        case invalidQuaternionComponent(component: String)
    }
}

// MARK: - LocalizedError

extension GoCubeError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case let .bluetooth(error):
            return error.errorDescription
        case let .connection(error):
            return error.errorDescription
        case let .parsing(error):
            return error.errorDescription
        }
    }
}

extension GoCubeError.BluetoothError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .unavailable:
            return "Bluetooth is not available on this device"
        case .unauthorized:
            return "Bluetooth access is not authorized. Please enable Bluetooth permission in Settings."
        case .poweredOff:
            return "Bluetooth is powered off. Please enable Bluetooth to connect to GoCube."
        case let .unsupportedState(state):
            return "Bluetooth is in an unsupported state: \(state)"
        }
    }
}

extension GoCubeError.ConnectionError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .notConnected:
            return "No GoCube is currently connected"
        case .deviceNotFound:
            return "GoCube device was not found"
        case let .failed(reason):
            return "Connection failed: \(reason)"
        case .disconnected:
            return "GoCube disconnected unexpectedly"
        case .serviceNotFound:
            return "Required BLE service not found on device"
        case .characteristicNotFound:
            return "Required BLE characteristic not found"
        case .timeout:
            return "Operation timed out"
        case let .writeFailed(reason):
            return "Failed to write to device: \(reason)"
        }
    }
}

extension GoCubeError.ProtocolError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case let .messageTooShort(length):
            return "Message too short: \(length) bytes"
        case let .invalidPrefix(received):
            return "Invalid message prefix: 0x\(String(format: "%02X", received))"
        case let .invalidSuffix(received):
            return "Invalid message suffix: \(received.map { String(format: "0x%02X", $0) }.joined(separator: " "))"
        case let .checksumMismatch(expected, received):
            return "Checksum mismatch: expected 0x\(String(format: "%02X", expected)), got 0x\(String(format: "%02X", received))"
        case let .unknownMessageType(type):
            return "Unknown message type: 0x\(String(format: "%02X", type))"
        case let .payloadLengthMismatch(expected, actual):
            return "Payload length mismatch: expected \(expected), got \(actual)"
        case let .invalidPayload(reason):
            return "Invalid payload: \(reason)"
        case .emptyMovePayload:
            return "Empty move payload"
        case let .invalidMoveCode(code):
            return "Invalid move code: 0x\(String(format: "%02X", code))"
        case let .oddMovePayloadLength(length):
            return "Odd move payload length: \(length) (expected even)"
        case let .invalidColorValue(value, position):
            return "Invalid color value 0x\(String(format: "%02X", value)) at position \(position)"
        case let .invalidOrientationValue(value, face):
            return "Invalid orientation value 0x\(String(format: "%02X", value)) for face \(face)"
        case let .invalidQuaternionFormat(reason):
            return "Invalid quaternion format: \(reason)"
        case let .invalidQuaternionComponentCount(expected, actual):
            return "Invalid quaternion component count: expected \(expected), got \(actual)"
        case let .invalidQuaternionComponent(component):
            return "Invalid quaternion component: '\(component)'"
        }
    }
}
