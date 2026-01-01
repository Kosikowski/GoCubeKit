import Foundation

/// Represents the complete state of a Rubik's cube (54 stickers)
public struct CubeState: Equatable, Hashable, Sendable {
    /// All 54 facelets organized by face (6 faces × 9 stickers)
    /// Index order per face: center, then clockwise from top-left
    public let facelets: [[CubeColor]]

    /// Orientation values for each center piece (6 values)
    public let centerOrientations: [UInt8]

    /// Create a cube state from facelet data
    public init(facelets: [[CubeColor]], centerOrientations: [UInt8] = Array(repeating: 0, count: 6)) {
        precondition(facelets.count == 6, "Must have exactly 6 faces")
        precondition(facelets.allSatisfy { $0.count == 9 }, "Each face must have 9 stickers")
        precondition(centerOrientations.count == 6, "Must have 6 center orientations")

        self.facelets = facelets
        self.centerOrientations = centerOrientations
    }

    /// Create a solved cube state
    public static var solved: CubeState {
        CubeState(
            facelets: CubeFace.allCases.map { face in
                Array(repeating: face.solvedCenterColor, count: 9)
            }
        )
    }

    /// Check if the cube is in a solved state
    public var isSolved: Bool {
        for (faceIndex, face) in facelets.enumerated() {
            guard let cubeFace = CubeFace(rawValue: faceIndex) else { return false }
            let expectedColor = cubeFace.solvedCenterColor
            if !face.allSatisfy({ $0 == expectedColor }) {
                return false
            }
        }
        return true
    }

    /// Get the color at a specific position
    public func color(at face: CubeFace, position: Int) -> CubeColor {
        precondition(position >= 0 && position < 9, "Position must be 0-8")
        return facelets[face.rawValue][position]
    }

    /// Get all colors for a face
    public func colors(for face: CubeFace) -> [CubeColor] {
        facelets[face.rawValue]
    }

    /// Get the center color for a face
    public func centerColor(for face: CubeFace) -> CubeColor {
        facelets[face.rawValue][0]
    }

    /// Count the number of correctly positioned stickers
    public var correctStickerCount: Int {
        var count = 0
        for (faceIndex, face) in facelets.enumerated() {
            guard let cubeFace = CubeFace(rawValue: faceIndex) else { continue }
            let expectedColor = cubeFace.solvedCenterColor
            count += face.filter { $0 == expectedColor }.count
        }
        return count
    }

    /// Calculate the percentage of correctly positioned stickers
    public var solvedPercentage: Double {
        Double(correctStickerCount) / 54.0 * 100.0
    }
}

// MARK: - CustomStringConvertible

extension CubeState: CustomStringConvertible {
    public var description: String {
        var result = ""
        for face in CubeFace.allCases {
            let colors = self.colors(for: face)
            let colorString = colors.map { String($0.character) }.joined()
            result += "\(face.notation): \(colorString)\n"
        }
        return result
    }

    /// Create a visual ASCII representation of the cube net
    public var netRepresentation: String {
        // Standard cube net layout:
        //       U
        //     L F R B
        //       D

        let u = colors(for: .up)
        let l = colors(for: .left)
        let f = colors(for: .front)
        let r = colors(for: .right)
        let b = colors(for: .back)
        let d = colors(for: .down)

        func row(_ face: [CubeColor], start: Int) -> String {
            face[start..<start+3].map { String($0.character) }.joined(separator: " ")
        }

        func faceRow(_ faces: [[CubeColor]], rowIndex: Int) -> String {
            faces.map { row($0, start: rowIndex * 3 + 1) }.joined(separator: " | ")
        }

        var lines: [String] = []

        // Up face (rows with proper indexing for 3x3 display)
        // Position mapping: 0=center, 1-8 around clockwise from top-left
        // For display: top-left(1), top(2), top-right(3), left(8), center(0), right(4), bottom-left(7), bottom(6), bottom-right(5)
        let uDisplay = [u[1], u[2], u[3], u[8], u[0], u[4], u[7], u[6], u[5]]
        lines.append("       \(uDisplay[0].character) \(uDisplay[1].character) \(uDisplay[2].character)")
        lines.append("       \(uDisplay[3].character) \(uDisplay[4].character) \(uDisplay[5].character)")
        lines.append("       \(uDisplay[6].character) \(uDisplay[7].character) \(uDisplay[8].character)")

        // Middle row (L F R B)
        let lDisplay = [l[1], l[2], l[3], l[8], l[0], l[4], l[7], l[6], l[5]]
        let fDisplay = [f[1], f[2], f[3], f[8], f[0], f[4], f[7], f[6], f[5]]
        let rDisplay = [r[1], r[2], r[3], r[8], r[0], r[4], r[7], r[6], r[5]]
        let bDisplay = [b[1], b[2], b[3], b[8], b[0], b[4], b[7], b[6], b[5]]

        for i in 0..<3 {
            let rowStart = i * 3
            lines.append("\(lDisplay[rowStart].character) \(lDisplay[rowStart+1].character) \(lDisplay[rowStart+2].character)  " +
                         "\(fDisplay[rowStart].character) \(fDisplay[rowStart+1].character) \(fDisplay[rowStart+2].character)  " +
                         "\(rDisplay[rowStart].character) \(rDisplay[rowStart+1].character) \(rDisplay[rowStart+2].character)  " +
                         "\(bDisplay[rowStart].character) \(bDisplay[rowStart+1].character) \(bDisplay[rowStart+2].character)")
        }

        // Down face
        let dDisplay = [d[1], d[2], d[3], d[8], d[0], d[4], d[7], d[6], d[5]]
        lines.append("       \(dDisplay[0].character) \(dDisplay[1].character) \(dDisplay[2].character)")
        lines.append("       \(dDisplay[3].character) \(dDisplay[4].character) \(dDisplay[5].character)")
        lines.append("       \(dDisplay[6].character) \(dDisplay[7].character) \(dDisplay[8].character)")

        return lines.joined(separator: "\n")
    }
}

// MARK: - Builder

extension CubeState {
    /// Builder for creating cube states
    public struct Builder {
        private var facelets: [[CubeColor]]
        private var centerOrientations: [UInt8]

        public init(from state: CubeState = .solved) {
            self.facelets = state.facelets
            self.centerOrientations = state.centerOrientations
        }

        public mutating func setColor(_ color: CubeColor, at face: CubeFace, position: Int) {
            precondition(position >= 0 && position < 9)
            facelets[face.rawValue][position] = color
        }

        public mutating func setFace(_ face: CubeFace, colors: [CubeColor]) {
            precondition(colors.count == 9)
            facelets[face.rawValue] = colors
        }

        public mutating func setCenterOrientation(_ orientation: UInt8, for face: CubeFace) {
            centerOrientations[face.rawValue] = orientation
        }

        public func build() -> CubeState {
            CubeState(facelets: facelets, centerOrientations: centerOrientations)
        }
    }
}
