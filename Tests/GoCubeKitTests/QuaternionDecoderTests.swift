@testable import GoCubeKit
import XCTest

final class QuaternionDecoderTests: XCTestCase {
    var decoder: QuaternionDecoder!

    override func setUp() {
        super.setUp()
        decoder = QuaternionDecoder()
    }

    override func tearDown() {
        decoder = nil
        super.tearDown()
    }

    // MARK: - Valid String Decoding Tests

    func testDecodeString_ValidQuaternion() throws {
        let quaternion = try decoder.decode(string: "0.1#0.2#0.3#0.4")

        XCTAssertEqual(quaternion.x, 0.1, accuracy: 0.0001)
        XCTAssertEqual(quaternion.y, 0.2, accuracy: 0.0001)
        XCTAssertEqual(quaternion.z, 0.3, accuracy: 0.0001)
        XCTAssertEqual(quaternion.w, 0.4, accuracy: 0.0001)
    }

    func testDecodeString_Identity() throws {
        let quaternion = try decoder.decode(string: "0#0#0#1")

        XCTAssertEqual(quaternion.x, 0.0, accuracy: 0.0001)
        XCTAssertEqual(quaternion.y, 0.0, accuracy: 0.0001)
        XCTAssertEqual(quaternion.z, 0.0, accuracy: 0.0001)
        XCTAssertEqual(quaternion.w, 1.0, accuracy: 0.0001)
    }

    func testDecodeString_NegativeValues() throws {
        let quaternion = try decoder.decode(string: "-0.5#-0.5#0.5#0.5")

        XCTAssertEqual(quaternion.x, -0.5, accuracy: 0.0001)
        XCTAssertEqual(quaternion.y, -0.5, accuracy: 0.0001)
        XCTAssertEqual(quaternion.z, 0.5, accuracy: 0.0001)
        XCTAssertEqual(quaternion.w, 0.5, accuracy: 0.0001)
    }

    func testDecodeString_ScientificNotation() throws {
        let quaternion = try decoder.decode(string: "1e-5#2e-5#3e-5#0.99999")

        XCTAssertEqual(quaternion.x, 0.00001, accuracy: 0.000001)
        XCTAssertEqual(quaternion.y, 0.00002, accuracy: 0.000001)
        XCTAssertEqual(quaternion.z, 0.00003, accuracy: 0.000001)
        XCTAssertEqual(quaternion.w, 0.99999, accuracy: 0.000001)
    }

    func testDecodeString_HighPrecision() throws {
        let quaternion = try decoder.decode(string: "0.123456789#0.234567891#0.345678912#0.456789123")

        XCTAssertEqual(quaternion.x, 0.123456789, accuracy: 0.000000001)
        XCTAssertEqual(quaternion.y, 0.234567891, accuracy: 0.000000001)
        XCTAssertEqual(quaternion.z, 0.345678912, accuracy: 0.000000001)
        XCTAssertEqual(quaternion.w, 0.456789123, accuracy: 0.000000001)
    }

    func testDecodeString_WhitespaceAroundValues() throws {
        let quaternion = try decoder.decode(string: " 0.1 # 0.2 # 0.3 # 0.4 ")

        XCTAssertEqual(quaternion.x, 0.1, accuracy: 0.0001)
        XCTAssertEqual(quaternion.y, 0.2, accuracy: 0.0001)
        XCTAssertEqual(quaternion.z, 0.3, accuracy: 0.0001)
        XCTAssertEqual(quaternion.w, 0.4, accuracy: 0.0001)
    }

    func testDecodeString_IntegerValues() throws {
        let quaternion = try decoder.decode(string: "0#0#0#1")

        XCTAssertEqual(quaternion.x, 0.0, accuracy: 0.0001)
        XCTAssertEqual(quaternion.y, 0.0, accuracy: 0.0001)
        XCTAssertEqual(quaternion.z, 0.0, accuracy: 0.0001)
        XCTAssertEqual(quaternion.w, 1.0, accuracy: 0.0001)
    }

    // MARK: - Valid Data Decoding Tests

    func testDecodeData_ValidQuaternion() throws {
        let string = "0.1#0.2#0.3#0.4"
        let data = Data(string.utf8)

        let quaternion = try decoder.decode(data)

        XCTAssertEqual(quaternion.x, 0.1, accuracy: 0.0001)
        XCTAssertEqual(quaternion.y, 0.2, accuracy: 0.0001)
        XCTAssertEqual(quaternion.z, 0.3, accuracy: 0.0001)
        XCTAssertEqual(quaternion.w, 0.4, accuracy: 0.0001)
    }

    // MARK: - Invalid Input Tests

    func testDecodeString_Empty_ThrowsError() {
        XCTAssertThrowsError(try decoder.decode(string: "")) { error in
            guard case let GoCubeError.parsing(.invalidQuaternionFormat(reason)) = error else {
                XCTFail("Expected invalidQuaternionFormat error")
                return
            }
            XCTAssertEqual(reason, "Empty string")
        }
    }

    func testDecodeString_WhitespaceOnly_ThrowsError() {
        XCTAssertThrowsError(try decoder.decode(string: "   ")) { error in
            guard case let GoCubeError.parsing(.invalidQuaternionFormat(reason)) = error else {
                XCTFail("Expected invalidQuaternionFormat error")
                return
            }
            XCTAssertEqual(reason, "Empty string")
        }
    }

    func testDecodeData_Empty_ThrowsError() {
        let data = Data()

        XCTAssertThrowsError(try decoder.decode(data)) { error in
            guard case let GoCubeError.parsing(.invalidQuaternionFormat(reason)) = error else {
                XCTFail("Expected invalidQuaternionFormat error")
                return
            }
            XCTAssertEqual(reason, "Empty payload")
        }
    }

    func testDecodeString_TooFewComponents_ThrowsError() {
        XCTAssertThrowsError(try decoder.decode(string: "0.1#0.2#0.3")) { error in
            guard case let GoCubeError.parsing(.invalidQuaternionComponentCount(expected, actual)) = error else {
                XCTFail("Expected invalidQuaternionComponentCount error")
                return
            }
            XCTAssertEqual(expected, 4)
            XCTAssertEqual(actual, 3)
        }
    }

    func testDecodeString_TooManyComponents_ThrowsError() {
        XCTAssertThrowsError(try decoder.decode(string: "0.1#0.2#0.3#0.4#0.5")) { error in
            guard case let GoCubeError.parsing(.invalidQuaternionComponentCount(expected, actual)) = error else {
                XCTFail("Expected invalidQuaternionComponentCount error")
                return
            }
            XCTAssertEqual(expected, 4)
            XCTAssertEqual(actual, 5)
        }
    }

    func testDecodeString_SingleComponent_ThrowsError() {
        XCTAssertThrowsError(try decoder.decode(string: "0.5")) { error in
            guard case let GoCubeError.parsing(.invalidQuaternionComponentCount(expected, actual)) = error else {
                XCTFail("Expected invalidQuaternionComponentCount error")
                return
            }
            XCTAssertEqual(expected, 4)
            XCTAssertEqual(actual, 1)
        }
    }

    func testDecodeString_InvalidNumericX_ThrowsError() {
        XCTAssertThrowsError(try decoder.decode(string: "abc#0.2#0.3#0.4")) { error in
            guard case let GoCubeError.parsing(.invalidQuaternionComponent(component)) = error else {
                XCTFail("Expected invalidQuaternionComponent error")
                return
            }
            XCTAssertEqual(component, "abc")
        }
    }

    func testDecodeString_InvalidNumericY_ThrowsError() {
        XCTAssertThrowsError(try decoder.decode(string: "0.1#abc#0.3#0.4")) { error in
            guard case let GoCubeError.parsing(.invalidQuaternionComponent(component)) = error else {
                XCTFail("Expected invalidQuaternionComponent error")
                return
            }
            XCTAssertEqual(component, "abc")
        }
    }

    func testDecodeString_InvalidNumericZ_ThrowsError() {
        XCTAssertThrowsError(try decoder.decode(string: "0.1#0.2#abc#0.4")) { error in
            guard case let GoCubeError.parsing(.invalidQuaternionComponent(component)) = error else {
                XCTFail("Expected invalidQuaternionComponent error")
                return
            }
            XCTAssertEqual(component, "abc")
        }
    }

    func testDecodeString_InvalidNumericW_ThrowsError() {
        XCTAssertThrowsError(try decoder.decode(string: "0.1#0.2#0.3#abc")) { error in
            guard case let GoCubeError.parsing(.invalidQuaternionComponent(component)) = error else {
                XCTFail("Expected invalidQuaternionComponent error")
                return
            }
            XCTAssertEqual(component, "abc")
        }
    }

    func testDecodeString_EmptyComponentX_ThrowsError() {
        XCTAssertThrowsError(try decoder.decode(string: "#0.2#0.3#0.4")) { error in
            guard case let GoCubeError.parsing(.invalidQuaternionComponent(component)) = error else {
                XCTFail("Expected invalidQuaternionComponent error")
                return
            }
            XCTAssertEqual(component, "")
        }
    }

    func testDecodeData_InvalidUTF8_ThrowsError() {
        // Invalid UTF-8 sequence
        let data = Data([0xFF, 0xFE])

        XCTAssertThrowsError(try decoder.decode(data)) { error in
            guard case GoCubeError.parsing(.invalidQuaternionFormat) = error else {
                XCTFail("Expected invalidQuaternionFormat error")
                return
            }
        }
    }

    // MARK: - Encoding Tests

    func testEncodeToString_Identity() {
        let quaternion = Quaternion.identity

        let encoded = decoder.encode(toString: quaternion)

        XCTAssertEqual(encoded, "0.000000#0.000000#0.000000#1.000000")
    }

    func testEncodeToString_CustomValues() {
        let quaternion = Quaternion(x: 0.1, y: 0.2, z: 0.3, w: 0.4)

        let encoded = decoder.encode(toString: quaternion)

        XCTAssertTrue(encoded.hasPrefix("0.1"))
        XCTAssertTrue(encoded.contains("#"))
    }

    func testEncodeToData_ReturnsValidUTF8() {
        let quaternion = Quaternion(x: 0.5, y: 0.5, z: 0.5, w: 0.5)

        let data = decoder.encode(quaternion)
        let string = String(data: data, encoding: .utf8)

        XCTAssertNotNil(string)
        XCTAssertTrue(string!.contains("#"))
    }

    // MARK: - Round-trip Tests

    func testRoundTrip_Identity() throws {
        let original = Quaternion.identity

        let encoded = decoder.encode(toString: original)
        let decoded = try decoder.decode(string: encoded)

        XCTAssertTrue(decoded.isApproximatelyEqual(to: original, tolerance: 0.000001))
    }

    func testRoundTrip_RandomValues() throws {
        let original = Quaternion(x: 0.123, y: -0.456, z: 0.789, w: 0.321)

        let encoded = decoder.encode(toString: original)
        let decoded = try decoder.decode(string: encoded)

        XCTAssertTrue(decoded.isApproximatelyEqual(to: original, tolerance: 0.000001))
    }

    func testRoundTrip_ViaData() throws {
        let original = Quaternion(x: 0.5, y: 0.5, z: 0.5, w: 0.5)

        let data = decoder.encode(original)
        let decoded = try decoder.decode(data)

        XCTAssertTrue(decoded.isApproximatelyEqual(to: original, tolerance: 0.000001))
    }
}

// MARK: - Quaternion Model Tests

final class QuaternionModelTests: XCTestCase {
    func testQuaternion_Identity() {
        let identity = Quaternion.identity

        XCTAssertEqual(identity.x, 0)
        XCTAssertEqual(identity.y, 0)
        XCTAssertEqual(identity.z, 0)
        XCTAssertEqual(identity.w, 1)
    }

    func testQuaternion_Magnitude_Identity() {
        let identity = Quaternion.identity

        XCTAssertEqual(identity.magnitude, 1.0, accuracy: 0.0001)
    }

    func testQuaternion_Magnitude_Unit() {
        let q = Quaternion(x: 0.5, y: 0.5, z: 0.5, w: 0.5)

        XCTAssertEqual(q.magnitude, 1.0, accuracy: 0.0001)
    }

    func testQuaternion_Magnitude_NonUnit() {
        let q = Quaternion(x: 1, y: 1, z: 1, w: 1)

        XCTAssertEqual(q.magnitude, 2.0, accuracy: 0.0001)
    }

    func testQuaternion_IsNormalized_True() {
        let q = Quaternion(x: 0.5, y: 0.5, z: 0.5, w: 0.5)

        XCTAssertTrue(q.isNormalized)
    }

    func testQuaternion_IsNormalized_False() {
        let q = Quaternion(x: 1, y: 1, z: 1, w: 1)

        XCTAssertFalse(q.isNormalized)
    }

    func testQuaternion_Normalized() {
        let q = Quaternion(x: 2, y: 0, z: 0, w: 0)

        let normalized = q.normalized

        XCTAssertEqual(normalized.magnitude, 1.0, accuracy: 0.0001)
        XCTAssertEqual(normalized.x, 1.0, accuracy: 0.0001)
    }

    func testQuaternion_Normalized_ZeroMagnitude() {
        let q = Quaternion(x: 0, y: 0, z: 0, w: 0)

        let normalized = q.normalized

        XCTAssertEqual(normalized, Quaternion.identity)
    }

    func testQuaternion_Conjugate() {
        let q = Quaternion(x: 1, y: 2, z: 3, w: 4)

        let conjugate = q.conjugate

        XCTAssertEqual(conjugate.x, -1)
        XCTAssertEqual(conjugate.y, -2)
        XCTAssertEqual(conjugate.z, -3)
        XCTAssertEqual(conjugate.w, 4)
    }

    func testQuaternion_Inverse() {
        let q = Quaternion(x: 0.5, y: 0.5, z: 0.5, w: 0.5)

        let inverse = q.inverse

        // q * q^-1 should equal identity
        let product = q * inverse

        XCTAssertTrue(product.isApproximatelyEqual(to: .identity, tolerance: 0.0001))
    }

    func testQuaternion_Multiplication_Identity() {
        let q = Quaternion(x: 0.5, y: 0.5, z: 0.5, w: 0.5)

        let result = q * Quaternion.identity

        XCTAssertTrue(result.isApproximatelyEqual(to: q, tolerance: 0.0001))
    }

    func testQuaternion_Multiplication_Inverse() {
        let q = Quaternion(x: 0.5, y: 0.5, z: 0.5, w: 0.5)

        let result = q * q.inverse

        XCTAssertTrue(result.isApproximatelyEqual(to: .identity, tolerance: 0.0001))
    }

    func testQuaternion_ToEulerAngles_Identity() {
        let euler = Quaternion.identity.toEulerAngles()

        XCTAssertEqual(euler.pitch, 0, accuracy: 0.0001)
        XCTAssertEqual(euler.yaw, 0, accuracy: 0.0001)
        XCTAssertEqual(euler.roll, 0, accuracy: 0.0001)
    }

    func testQuaternion_ToEulerAnglesDegrees() {
        let euler = Quaternion.identity.toEulerAnglesDegrees()

        XCTAssertEqual(euler.pitch, 0, accuracy: 0.0001)
        XCTAssertEqual(euler.yaw, 0, accuracy: 0.0001)
        XCTAssertEqual(euler.roll, 0, accuracy: 0.0001)
    }

    func testQuaternion_ToRotationMatrix_Identity() {
        let matrix = Quaternion.identity.toRotationMatrix()

        // Identity quaternion should produce identity matrix
        XCTAssertEqual(matrix[0][0], 1, accuracy: 0.0001)
        XCTAssertEqual(matrix[1][1], 1, accuracy: 0.0001)
        XCTAssertEqual(matrix[2][2], 1, accuracy: 0.0001)
        XCTAssertEqual(matrix[3][3], 1, accuracy: 0.0001)
    }

    func testQuaternion_Slerp_T0() {
        let q1 = Quaternion.identity
        let q2 = Quaternion(x: 0.5, y: 0.5, z: 0.5, w: 0.5)

        let result = Quaternion.slerp(from: q1, to: q2, t: 0)

        XCTAssertTrue(result.isApproximatelyEqual(to: q1, tolerance: 0.0001))
    }

    func testQuaternion_Slerp_T1() {
        let q1 = Quaternion.identity
        let q2 = Quaternion(x: 0.5, y: 0.5, z: 0.5, w: 0.5)

        let result = Quaternion.slerp(from: q1, to: q2, t: 1)

        XCTAssertTrue(result.isApproximatelyEqual(to: q2, tolerance: 0.0001))
    }

    func testQuaternion_Slerp_Midpoint() {
        let q1 = Quaternion.identity
        let q2 = Quaternion(x: 0.5, y: 0.5, z: 0.5, w: 0.5)

        let result = Quaternion.slerp(from: q1, to: q2, t: 0.5)

        // Midpoint should be roughly between q1 and q2
        XCTAssertGreaterThan(result.w, q2.w)
        XCTAssertLessThan(result.w, q1.w)
    }

    func testQuaternion_FromAxisAngle() {
        let axis = SIMD3<Double>(0, 1, 0) // Y axis
        let angle = Double.pi / 2 // 90 degrees

        let quaternion = Quaternion.fromAxisAngle(axis: axis, angle: angle)

        XCTAssertTrue(quaternion.isNormalized)
    }

    func testQuaternion_Angle() {
        let q1 = Quaternion.identity
        let q2 = Quaternion.fromAxisAngle(axis: SIMD3<Double>(0, 1, 0), angle: Double.pi / 2)

        let angle = q1.angle(to: q2)

        XCTAssertEqual(angle, Double.pi / 2, accuracy: 0.01)
    }

    func testQuaternion_IsApproximatelyEqual_True() {
        let q1 = Quaternion(x: 0.5, y: 0.5, z: 0.5, w: 0.5)
        let q2 = Quaternion(x: 0.50001, y: 0.50001, z: 0.50001, w: 0.50001)

        XCTAssertTrue(q1.isApproximatelyEqual(to: q2, tolerance: 0.001))
    }

    func testQuaternion_IsApproximatelyEqual_False() {
        let q1 = Quaternion(x: 0.5, y: 0.5, z: 0.5, w: 0.5)
        let q2 = Quaternion(x: 0.6, y: 0.5, z: 0.5, w: 0.5)

        XCTAssertFalse(q1.isApproximatelyEqual(to: q2, tolerance: 0.001))
    }

    func testQuaternion_Equatable() {
        let q1 = Quaternion(x: 0.5, y: 0.5, z: 0.5, w: 0.5)
        let q2 = Quaternion(x: 0.5, y: 0.5, z: 0.5, w: 0.5)
        let q3 = Quaternion(x: 0.6, y: 0.5, z: 0.5, w: 0.5)

        XCTAssertEqual(q1, q2)
        XCTAssertNotEqual(q1, q3)
    }

    func testQuaternion_Hashable() {
        var set = Set<Quaternion>()
        set.insert(Quaternion.identity)
        set.insert(Quaternion.identity)
        set.insert(Quaternion(x: 0.5, y: 0.5, z: 0.5, w: 0.5))

        XCTAssertEqual(set.count, 2)
    }

    func testQuaternion_Description() {
        let q = Quaternion(x: 0.1, y: 0.2, z: 0.3, w: 0.4)

        let description = q.description

        XCTAssertTrue(description.contains("0.1"))
        XCTAssertTrue(description.contains("0.2"))
        XCTAssertTrue(description.contains("0.3"))
        XCTAssertTrue(description.contains("0.4"))
    }
}

// MARK: - QuaternionSmoother Tests

final class QuaternionSmootherTests: XCTestCase {
    func testSmoother_FirstUpdate() async {
        let smoother = QuaternionSmoother(smoothingFactor: 0.5)
        let input = Quaternion(x: 0.5, y: 0.5, z: 0.5, w: 0.5)

        let result = await smoother.update(input)

        XCTAssertEqual(result, input)
    }

    func testSmoother_SecondUpdate() async {
        let smoother = QuaternionSmoother(smoothingFactor: 0.5)
        let q1 = Quaternion.identity
        let q2 = Quaternion(x: 0.5, y: 0.5, z: 0.5, w: 0.5)

        _ = await smoother.update(q1)
        let result = await smoother.update(q2)

        // Result should be somewhere between q1 and q2
        XCTAssertFalse(result.isApproximatelyEqual(to: q1, tolerance: 0.01))
        XCTAssertFalse(result.isApproximatelyEqual(to: q2, tolerance: 0.01))
    }

    func testSmoother_Reset() async {
        let smoother = QuaternionSmoother(smoothingFactor: 0.5)
        let q = Quaternion(x: 0.5, y: 0.5, z: 0.5, w: 0.5)

        _ = await smoother.update(q)
        await smoother.reset()

        let current = await smoother.current
        XCTAssertNil(current)
    }

    func testSmoother_Current() async {
        let smoother = QuaternionSmoother(smoothingFactor: 0.5)

        let initialCurrent = await smoother.current
        XCTAssertNil(initialCurrent)

        let q = Quaternion.identity
        _ = await smoother.update(q)

        let updatedCurrent = await smoother.current
        XCTAssertNotNil(updatedCurrent)
    }

    func testSmoother_SmoothingFactorZero() async {
        let smoother = QuaternionSmoother(smoothingFactor: 0)
        let q1 = Quaternion.identity
        let q2 = Quaternion(x: 0.5, y: 0.5, z: 0.5, w: 0.5)

        _ = await smoother.update(q1)
        let result = await smoother.update(q2)

        // With smoothing factor 0, should snap to new value
        XCTAssertTrue(result.isApproximatelyEqual(to: q2, tolerance: 0.01))
    }
}

// MARK: - OrientationManager Tests

final class OrientationManagerTests: XCTestCase {
    func testOrientationManager_NoHome() async {
        let manager = OrientationManager()
        let q = Quaternion(x: 0.5, y: 0.5, z: 0.5, w: 0.5)

        let result = await manager.relativeOrientation(q)

        XCTAssertEqual(result, q)
    }

    func testOrientationManager_SetHome() async {
        let manager = OrientationManager()
        let home = Quaternion(x: 0.5, y: 0.5, z: 0.5, w: 0.5)

        await manager.setHome(home)

        let hasHome = await manager.hasHome
        XCTAssertTrue(hasHome)
    }

    func testOrientationManager_RelativeToHome() async {
        let manager = OrientationManager()
        let home = Quaternion(x: 0.5, y: 0.5, z: 0.5, w: 0.5)

        await manager.setHome(home)

        // Same orientation as home should give identity
        let result = await manager.relativeOrientation(home)

        XCTAssertTrue(result.isApproximatelyEqual(to: .identity, tolerance: 0.01))
    }

    func testOrientationManager_ClearHome() async {
        let manager = OrientationManager()
        let home = Quaternion.identity

        await manager.setHome(home)
        let hasHomeAfterSet = await manager.hasHome
        XCTAssertTrue(hasHomeAfterSet)

        await manager.clearHome()
        let hasHomeAfterClear = await manager.hasHome
        XCTAssertFalse(hasHomeAfterClear)
    }
}
