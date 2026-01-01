import Foundation

/// Errors specific to GoCube operations
public enum GoCubeError: Error, LocalizedError {
    case notConnected
    case connectionFailed(String)
    case communicationError(String)
    case invalidResponse(String)
    case timeout
    case bluetoothUnavailable
    case bluetoothUnauthorized
    case bluetoothPoweredOff

    public var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Not connected to a GoCube"
        case .connectionFailed(let reason):
            return "Connection failed: \(reason)"
        case .communicationError(let reason):
            return "Communication error: \(reason)"
        case .invalidResponse(let reason):
            return "Invalid response: \(reason)"
        case .timeout:
            return "Operation timed out"
        case .bluetoothUnavailable:
            return "Bluetooth is not available on this device"
        case .bluetoothUnauthorized:
            return "Bluetooth access not authorized"
        case .bluetoothPoweredOff:
            return "Bluetooth is powered off"
        }
    }
}
