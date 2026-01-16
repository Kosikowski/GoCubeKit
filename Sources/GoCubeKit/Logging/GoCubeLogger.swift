import Foundation
import os.log

/// Centralized logging for GoCubeKit
/// Configure via GoCubeLogger.setEnabled(_:)
public enum GoCubeLogger {
    /// Whether debug logging is enabled
    /// Using nonisolated(unsafe) as logging state doesn't require strict synchronization
    public nonisolated(unsafe) static var isEnabled: Bool = false

    /// Internal logger instance
    private static let logger = Logger(subsystem: "com.gocubekit", category: "Debug")

    /// Enable or disable debug logging
    /// Call this before connecting to a cube
    public static func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
    }

    /// Log a debug message (only when logging is enabled)
    static func debug(_ message: String) {
        guard isEnabled else { return }
        logger.debug("\(message, privacy: .public)")
    }

    /// Log an info message (only when logging is enabled)
    static func info(_ message: String) {
        guard isEnabled else { return }
        logger.info("\(message, privacy: .public)")
    }

    /// Log a warning message (always logged)
    static func warning(_ message: String) {
        logger.warning("\(message, privacy: .public)")
    }

    /// Log an error message (always logged)
    static func error(_ message: String) {
        logger.error("\(message, privacy: .public)")
    }

    /// Log raw BLE data (only when logging is enabled)
    static func logData(_ data: Data, prefix: String) {
        guard isEnabled else { return }
        let hex = data.map { String(format: "%02X", $0) }.joined(separator: " ")
        logger.debug("\(prefix, privacy: .public) \(data.count) bytes: \(hex, privacy: .public)")
    }
}
