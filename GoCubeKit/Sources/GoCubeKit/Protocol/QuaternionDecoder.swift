import Foundation

/// Decodes orientation quaternion messages from the GoCube protocol
public struct QuaternionDecoder: Sendable {
    /// Expected number of quaternion components
    public static let componentCount = 4

    /// Separator character in the ASCII format
    public static let separator: Character = "#"

    public init() {}

    /// Decode an orientation message payload
    /// - Parameter payload: Raw payload bytes from an orientation message (type 0x03)
    /// - Returns: Decoded quaternion
    /// - Throws: GoCubeError.parsing if decoding fails
    public func decode(_ payload: Data) throws -> Quaternion {
        guard !payload.isEmpty else {
            throw GoCubeError.parsing(.invalidQuaternionFormat(reason: "Empty payload"))
        }

        // Convert payload to string (ASCII format: "x#y#z#w")
        guard let string = String(data: payload, encoding: .utf8) else {
            throw GoCubeError.parsing(.invalidQuaternionFormat(reason: "Not valid UTF-8"))
        }

        return try decode(string: string)
    }

    /// Decode a quaternion from its string representation
    /// - Parameter string: ASCII format string "x#y#z#w"
    /// - Returns: Decoded quaternion
    /// - Throws: GoCubeError.parsing if parsing fails
    public func decode(string: String) throws -> Quaternion {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            throw GoCubeError.parsing(.invalidQuaternionFormat(reason: "Empty string"))
        }

        let components = trimmed.split(separator: Self.separator, omittingEmptySubsequences: false)

        guard components.count == Self.componentCount else {
            throw GoCubeError.parsing(.invalidQuaternionComponentCount(
                expected: Self.componentCount,
                actual: components.count
            ))
        }

        var values: [Double] = []

        for component in components {
            let valueString = String(component).trimmingCharacters(in: .whitespaces)
            guard let value = Double(valueString) else {
                throw GoCubeError.parsing(.invalidQuaternionComponent(component: valueString))
            }
            values.append(value)
        }

        return Quaternion(x: values[0], y: values[1], z: values[2], w: values[3])
    }

    /// Encode a quaternion to protocol format
    /// - Parameter quaternion: The quaternion to encode
    /// - Returns: ASCII-encoded data
    public func encode(_ quaternion: Quaternion) -> Data {
        let string = encode(toString: quaternion)
        return Data(string.utf8)
    }

    /// Encode a quaternion to string format
    /// - Parameter quaternion: The quaternion to encode
    /// - Returns: String in format "x#y#z#w"
    public func encode(toString quaternion: Quaternion) -> String {
        String(format: "%.6f#%.6f#%.6f#%.6f", quaternion.x, quaternion.y, quaternion.z, quaternion.w)
    }
}

// MARK: - Quaternion Smoothing Actor

/// Actor that smooths quaternion updates for display purposes
/// Thread-safe by design using Swift's actor model
public actor QuaternionSmoother {
    private var lastQuaternion: Quaternion?
    private var targetQuaternion: Quaternion?
    private let smoothingFactor: Double

    /// Create a quaternion smoother
    /// - Parameter smoothingFactor: Value between 0 (no smoothing) and 1 (max smoothing). Default 0.5
    public init(smoothingFactor: Double = 0.5) {
        self.smoothingFactor = max(0, min(1, smoothingFactor))
    }

    /// Update with a new quaternion and get smoothed result
    /// - Parameter newQuaternion: The new raw quaternion from the device
    /// - Returns: Smoothed quaternion
    public func update(_ newQuaternion: Quaternion) -> Quaternion {
        guard let last = lastQuaternion else {
            lastQuaternion = newQuaternion
            targetQuaternion = newQuaternion
            return newQuaternion
        }

        targetQuaternion = newQuaternion

        // Use SLERP for smooth interpolation
        let smoothed = Quaternion.slerp(from: last, to: newQuaternion, t: 1.0 - smoothingFactor)
        lastQuaternion = smoothed

        return smoothed
    }

    /// Reset the smoother
    public func reset() {
        lastQuaternion = nil
        targetQuaternion = nil
    }

    /// Get the current smoothed quaternion without updating
    public var current: Quaternion? {
        lastQuaternion
    }
}

// MARK: - Home Orientation Actor

/// Actor that manages a "home" orientation for relative rotation display
/// Thread-safe by design using Swift's actor model
public actor OrientationManager {
    private var homeOrientation: Quaternion?

    public init() {}

    /// Set the current orientation as "home" (identity)
    /// - Parameter current: The current orientation to use as home
    public func setHome(_ current: Quaternion) {
        homeOrientation = current.inverse
    }

    /// Clear the home orientation
    public func clearHome() {
        homeOrientation = nil
    }

    /// Get orientation relative to home
    /// - Parameter current: The current absolute orientation
    /// - Returns: Orientation relative to home, or current if no home set
    public func relativeOrientation(_ current: Quaternion) -> Quaternion {
        guard let home = homeOrientation else {
            return current
        }
        return home * current
    }

    /// Check if home is set
    public var hasHome: Bool {
        homeOrientation != nil
    }
}
