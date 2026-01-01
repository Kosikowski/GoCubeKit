import CoreBluetooth
import Foundation

/// BLE Service and Characteristic UUIDs for GoCube communication
public enum GoCubeBLE {
    /// The primary GATT service UUID for GoCube devices
    /// This is a Nordic UART-like service
    public static let serviceUUID = CBUUID(string: "6e400001-b5a3-f393-e0a9-e50e24dcca9e")

    /// Write characteristic UUID (RX from cube's perspective)
    /// Used to send commands TO the cube
    public static let writeCharacteristicUUID = CBUUID(string: "6e400002-b5a3-f393-e0a9-e50e24dcca9e")

    /// Notify characteristic UUID (TX from cube's perspective)
    /// Used to receive data FROM the cube via notifications
    public static let notifyCharacteristicUUID = CBUUID(string: "6e400003-b5a3-f393-e0a9-e50e24dcca9e")

    /// Device name prefix used for filtering during BLE scanning
    public static let deviceNamePrefix = "GoCube"

    /// Alternative device name for Rubik's Connected (same protocol)
    public static let rubikConnectedPrefix = "Rubiks"
}

/// Commands that can be sent to the GoCube via the write characteristic
public enum GoCubeCommand: UInt8 {
    /// Request battery level (response: MessageType.battery)
    case getBattery = 0x32          // 50

    /// Request current cube state (response: MessageType.cubeState)
    case getCubeState = 0x33        // 51

    /// Reboot the cube
    case reboot = 0x34              // 52

    /// Reset cube tracking to solved state
    case resetToSolved = 0x35       // 53

    /// Disable 3D orientation updates
    case disableOrientation = 0x37  // 55

    /// Enable 3D orientation updates (~15 Hz)
    case enableOrientation = 0x38   // 56

    /// Request offline statistics (response: MessageType.offlineStats)
    case getOfflineStats = 0x39     // 57

    /// Flash LEDs at normal speed
    case flashLEDNormal = 0x41      // 65 'A'

    /// Toggle animated LED backlight
    case toggleAnimatedBacklight = 0x42  // 66 'B'

    /// Flash LEDs slowly
    case flashLEDSlow = 0x43        // 67 'C'

    /// Toggle backlight on/off
    case toggleBacklight = 0x44     // 68 'D'

    /// Request cube type (response: MessageType.cubeType)
    case getCubeType = 0x56         // 86 'V'

    /// Calibrate gyroscope/orientation sensor
    case calibrateOrientation = 0x57 // 87 'W'
}

/// Message types received from the GoCube via notifications
public enum GoCubeMessageType: UInt8, Sendable {
    /// Face rotation event - contains move data
    case rotation = 0x01

    /// Complete cube state - 54 facelets + orientation
    case cubeState = 0x02

    /// 3D orientation quaternion (ASCII format)
    case orientation = 0x03

    /// Battery level (0-100%)
    case battery = 0x05

    /// Offline statistics (moves, time, solves)
    case offlineStats = 0x07

    /// Cube type identifier
    case cubeType = 0x08
}

/// Message frame constants for GoCube protocol
public enum GoCubeFrame {
    /// Message prefix byte (asterisk '*')
    public static let prefix: UInt8 = 0x2A

    /// Message suffix bytes (CRLF)
    public static let suffix: [UInt8] = [0x0D, 0x0A]

    /// Minimum valid message length (prefix + length + type + checksum + suffix)
    public static let minimumLength = 5

    /// Position of the length byte in the frame
    public static let lengthOffset = 1

    /// Position of the type byte in the frame
    public static let typeOffset = 2

    /// Position of the payload start in the frame
    public static let payloadOffset = 3
}

/// Cube type identifiers
public enum GoCubeType: UInt8, Equatable, Sendable {
    /// Standard GoCube (original, Edge, etc.)
    case standard = 0x00

    /// Edge variant with different characteristics
    case edge = 0x01

    /// Unknown cube type
    case unknown = 0xFF

    public init(rawValue: UInt8) {
        switch rawValue {
        case 0x00: self = .standard
        case 0x01: self = .edge
        default: self = .unknown
        }
    }
}
