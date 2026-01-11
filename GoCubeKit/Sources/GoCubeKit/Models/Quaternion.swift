import Foundation
import simd

/// Represents a 3D orientation as a quaternion
/// Used for tracking the physical orientation of the GoCube in space
public struct Quaternion: Equatable, Sendable, CustomStringConvertible {
    public let x: Double
    public let y: Double
    public let z: Double
    public let w: Double

    public var description: String {
        String(format: "Quaternion(x: %.4f, y: %.4f, z: %.4f, w: %.4f)", x, y, z, w)
    }

    public init(x: Double, y: Double, z: Double, w: Double) {
        self.x = x
        self.y = y
        self.z = z
        self.w = w
    }

    /// Identity quaternion (no rotation)
    public static let identity = Quaternion(x: 0, y: 0, z: 0, w: 1)

    /// Calculate the magnitude (length) of the quaternion
    public var magnitude: Double {
        sqrt(x * x + y * y + z * z + w * w)
    }

    /// Check if the quaternion is normalized (magnitude ≈ 1)
    public var isNormalized: Bool {
        abs(magnitude - 1.0) < 0.001
    }

    /// Return a normalized version of this quaternion
    public var normalized: Quaternion {
        let mag = magnitude
        guard mag > 0 else { return .identity }
        return Quaternion(x: x / mag, y: y / mag, z: z / mag, w: w / mag)
    }

    /// Return the conjugate (inverse for unit quaternions)
    public var conjugate: Quaternion {
        Quaternion(x: -x, y: -y, z: -z, w: w)
    }

    /// Return the inverse quaternion
    public var inverse: Quaternion {
        let magSquared = x * x + y * y + z * z + w * w
        guard magSquared > 0 else { return .identity }
        return Quaternion(
            x: -x / magSquared,
            y: -y / magSquared,
            z: -z / magSquared,
            w: w / magSquared
        )
    }

    /// Multiply two quaternions (combine rotations)
    public static func * (lhs: Quaternion, rhs: Quaternion) -> Quaternion {
        Quaternion(
            x: lhs.w * rhs.x + lhs.x * rhs.w + lhs.y * rhs.z - lhs.z * rhs.y,
            y: lhs.w * rhs.y - lhs.x * rhs.z + lhs.y * rhs.w + lhs.z * rhs.x,
            z: lhs.w * rhs.z + lhs.x * rhs.y - lhs.y * rhs.x + lhs.z * rhs.w,
            w: lhs.w * rhs.w - lhs.x * rhs.x - lhs.y * rhs.y - lhs.z * rhs.z
        )
    }

    /// Convert to Euler angles (pitch, yaw, roll) in radians
    public func toEulerAngles() -> (pitch: Double, yaw: Double, roll: Double) {
        // Roll (x-axis rotation)
        let sinrCosp = 2.0 * (w * x + y * z)
        let cosrCosp = 1.0 - 2.0 * (x * x + y * y)
        let roll = atan2(sinrCosp, cosrCosp)

        // Pitch (y-axis rotation)
        let sinp = 2.0 * (w * y - z * x)
        let pitch: Double
        if abs(sinp) >= 1 {
            pitch = copysign(.pi / 2, sinp)
        } else {
            pitch = asin(sinp)
        }

        // Yaw (z-axis rotation)
        let sinyCosp = 2.0 * (w * z + x * y)
        let cosyCosp = 1.0 - 2.0 * (y * y + z * z)
        let yaw = atan2(sinyCosp, cosyCosp)

        return (pitch: pitch, yaw: yaw, roll: roll)
    }

    /// Convert to Euler angles in degrees
    public func toEulerAnglesDegrees() -> (pitch: Double, yaw: Double, roll: Double) {
        let radians = toEulerAngles()
        let toDegrees = 180.0 / .pi
        return (
            pitch: radians.pitch * toDegrees,
            yaw: radians.yaw * toDegrees,
            roll: radians.roll * toDegrees
        )
    }

    /// Convert to a 4x4 rotation matrix (for use with SceneKit, etc.)
    public func toRotationMatrix() -> simd_float4x4 {
        let x = Float(self.x)
        let y = Float(self.y)
        let z = Float(self.z)
        let w = Float(self.w)

        let xx = x * x
        let xy = x * y
        let xz = x * z
        let xw = x * w
        let yy = y * y
        let yz = y * z
        let yw = y * w
        let zz = z * z
        let zw = z * w

        return simd_float4x4(
            SIMD4<Float>(1 - 2 * (yy + zz), 2 * (xy + zw), 2 * (xz - yw), 0),
            SIMD4<Float>(2 * (xy - zw), 1 - 2 * (xx + zz), 2 * (yz + xw), 0),
            SIMD4<Float>(2 * (xz + yw), 2 * (yz - xw), 1 - 2 * (xx + yy), 0),
            SIMD4<Float>(0, 0, 0, 1)
        )
    }

    /// Spherical linear interpolation between two quaternions
    public static func slerp(from q1: Quaternion, to q2: Quaternion, t: Double) -> Quaternion {
        var dot = q1.x * q2.x + q1.y * q2.y + q1.z * q2.z + q1.w * q2.w

        var q2Adjusted = q2
        if dot < 0 {
            q2Adjusted = Quaternion(x: -q2.x, y: -q2.y, z: -q2.z, w: -q2.w)
            dot = -dot
        }

        // If quaternions are very close, use linear interpolation
        if dot > 0.9995 {
            return Quaternion(
                x: q1.x + t * (q2Adjusted.x - q1.x),
                y: q1.y + t * (q2Adjusted.y - q1.y),
                z: q1.z + t * (q2Adjusted.z - q1.z),
                w: q1.w + t * (q2Adjusted.w - q1.w)
            ).normalized
        }

        let theta0 = acos(dot)
        let theta = theta0 * t
        let sinTheta = sin(theta)
        let sinTheta0 = sin(theta0)

        let s0 = cos(theta) - dot * sinTheta / sinTheta0
        let s1 = sinTheta / sinTheta0

        return Quaternion(
            x: s0 * q1.x + s1 * q2Adjusted.x,
            y: s0 * q1.y + s1 * q2Adjusted.y,
            z: s0 * q1.z + s1 * q2Adjusted.z,
            w: s0 * q1.w + s1 * q2Adjusted.w
        )
    }

    /// Create a quaternion from axis-angle representation
    public static func fromAxisAngle(axis: SIMD3<Double>, angle: Double) -> Quaternion {
        let halfAngle = angle / 2
        let sinHalf = sin(halfAngle)
        let normalizedAxis = simd_normalize(axis)

        return Quaternion(
            x: normalizedAxis.x * sinHalf,
            y: normalizedAxis.y * sinHalf,
            z: normalizedAxis.z * sinHalf,
            w: cos(halfAngle)
        )
    }

    /// Angle between this quaternion and another (in radians)
    public func angle(to other: Quaternion) -> Double {
        let dot = abs(x * other.x + y * other.y + z * other.z + w * other.w)
        return 2 * acos(min(dot, 1.0))
    }
}

// MARK: - Hashable

extension Quaternion: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(x)
        hasher.combine(y)
        hasher.combine(z)
        hasher.combine(w)
    }
}

// MARK: - Approximate Equality

public extension Quaternion {
    /// Check if two quaternions are approximately equal within a tolerance
    func isApproximatelyEqual(to other: Quaternion, tolerance: Double = 0.0001) -> Bool {
        abs(x - other.x) < tolerance &&
            abs(y - other.y) < tolerance &&
            abs(z - other.z) < tolerance &&
            abs(w - other.w) < tolerance
    }
}
