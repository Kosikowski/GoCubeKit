import Foundation

/// Configuration options for GoCubeKit
public struct GoCubeConfiguration: Sendable {

    // MARK: - Timeouts

    /// Timeout for command responses (battery, state, cube type requests)
    public var commandTimeout: Duration = .seconds(5)

    /// Timeout for device scanning when using connectToFirstAvailable
    public var scanTimeout: Duration = .seconds(10)

    // MARK: - Quaternion Smoothing

    /// Smoothing factor for quaternion interpolation (0.0 = no smoothing, 1.0 = maximum smoothing)
    public var quaternionSmoothingFactor: Double = 0.5

    // MARK: - Tolerances

    /// Tolerance for quaternion normalization check
    public var quaternionNormalizedTolerance: Double = 0.001

    /// Tolerance for quaternion approximate equality comparisons
    public var quaternionEqualityTolerance: Double = 0.0001

    /// Threshold for SLERP to switch to linear interpolation (when quaternions are very close)
    public var slerpLinearThreshold: Double = 0.9995

    // MARK: - Connection

    /// Whether to automatically reconnect when disconnected
    public var autoReconnect: Bool = false

    /// Maximum reconnection attempts (0 = unlimited)
    public var maxReconnectAttempts: Int = 3

    /// Delay between reconnection attempts
    public var reconnectDelay: Duration = .seconds(1)

    // MARK: - Logging

    /// Enable debug logging
    public var debugLoggingEnabled: Bool = false

    // MARK: - Initialization

    public init() {}

    /// Create configuration with custom values using builder pattern
    public static func configure(_ configure: (inout GoCubeConfiguration) -> Void) -> GoCubeConfiguration {
        var config = GoCubeConfiguration()
        configure(&config)
        return config
    }
}

// MARK: - Default Configurations

extension GoCubeConfiguration {
    /// Default configuration
    public static let `default` = GoCubeConfiguration()

    /// Configuration optimized for responsive UI (less smoothing, shorter timeouts)
    public static var responsive: GoCubeConfiguration {
        .configure { config in
            config.commandTimeout = .seconds(3)
            config.scanTimeout = .seconds(5)
            config.quaternionSmoothingFactor = 0.3
        }
    }

    /// Configuration optimized for stability (more smoothing, longer timeouts)
    public static var stable: GoCubeConfiguration {
        .configure { config in
            config.commandTimeout = .seconds(10)
            config.scanTimeout = .seconds(20)
            config.quaternionSmoothingFactor = 0.7
            config.autoReconnect = true
        }
    }
}
