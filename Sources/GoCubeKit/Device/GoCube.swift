import Foundation
import Observation
import os.log

/// Represents a connected GoCube device
/// Uses @Observable for reactive state updates in SwiftUI
/// All heavy processing is done by BLEActor off MainActor
@Observable
@MainActor
public final class GoCube: Identifiable, Sendable {
    // MARK: - Properties

    private let logger = Logger(subsystem: "com.gocubekit", category: "GoCube")

    /// Device identifier
    public nonisolated let id: UUID

    /// Device name
    public nonisolated let name: String

    /// Configuration
    public nonisolated let configuration: GoCubeConfiguration

    /// BLE communicator
    private let communicator: BLECommunicator

    /// Cube processor (handles all decoding on @CubeActor, off MainActor)
    private let processor: CubeProcessor

    /// Task for listening to processed streams
    private var moveListenerTask: Task<Void, Never>?
    private var stateListenerTask: Task<Void, Never>?
    private var orientationListenerTask: Task<Void, Never>?
    private var batteryListenerTask: Task<Void, Never>?
    private var cubeTypeListenerTask: Task<Void, Never>?
    private var connectionListenerTask: Task<Void, Never>?

    // MARK: - Observable State

    /// Current cube state (if known)
    public private(set) var currentState: CubeState?

    /// Current battery level (if known)
    public private(set) var batteryLevel: Int?

    /// Current cube type (if known)
    public private(set) var cubeType: GoCubeType?

    /// Accumulated move sequence since last reset
    public private(set) var moveSequence = MoveSequence()

    /// Whether orientation tracking is enabled
    public private(set) var isOrientationEnabled = false

    /// Whether the cube is connected
    public private(set) var isConnected = true

    /// Most recent move (for UI binding)
    public private(set) var lastMove: Move?

    /// Most recent orientation (for UI binding)
    public private(set) var lastOrientation: Quaternion?

    // MARK: - Event Streams (for sequential processing)

    /// Stream of moves received from the cube
    public let moves: AsyncStream<Move>
    private let movesContinuation: AsyncStream<Move>.Continuation

    /// Stream of orientation updates (quaternions) - high frequency
    public let orientationUpdates: AsyncStream<Quaternion>
    private let orientationUpdatesContinuation: AsyncStream<Quaternion>.Continuation

    /// Stream that emits when the cube disconnects
    public let disconnected: AsyncStream<Void>
    private let disconnectedContinuation: AsyncStream<Void>.Continuation

    // MARK: - Initialization

    init(device: DiscoveredDevice, communicator: BLECommunicator, processor: CubeProcessor, configuration: GoCubeConfiguration = .default) {
        id = device.id
        name = device.name
        self.communicator = communicator
        self.processor = processor
        self.configuration = configuration

        // Initialize AsyncStreams using makeStream (iOS 17+)
        (moves, movesContinuation) = AsyncStream.makeStream(of: Move.self)
        (orientationUpdates, orientationUpdatesContinuation) = AsyncStream.makeStream(of: Quaternion.self)
        (disconnected, disconnectedContinuation) = AsyncStream.makeStream(of: Void.self)
    }

    deinit {
        movesContinuation.finish()
        orientationUpdatesContinuation.finish()
        disconnectedContinuation.finish()
    }

    /// Start listening to processed streams from BLEActor
    public func startListening() {
        // Listen for processed moves from BLEActor
        moveListenerTask = Task { [weak self] in
            guard let self else { return }
            for await move in self.processor.processedMoves {
                self.moveSequence.append(move)
                self.lastMove = move
                self.movesContinuation.yield(move)
            }
        }

        // Listen for processed states from BLEActor
        stateListenerTask = Task { [weak self] in
            guard let self else { return }
            for await state in self.processor.processedStates {
                self.currentState = state
            }
        }

        // Listen for processed orientations from BLEActor
        orientationListenerTask = Task { [weak self] in
            guard let self else { return }
            for await orientation in self.processor.processedOrientations {
                self.lastOrientation = orientation
                self.orientationUpdatesContinuation.yield(orientation)
            }
        }

        // Listen for battery updates from BLEActor
        batteryListenerTask = Task { [weak self] in
            guard let self else { return }
            for await level in self.processor.processedBattery {
                self.batteryLevel = level
            }
        }

        // Listen for cube type updates from BLEActor
        cubeTypeListenerTask = Task { [weak self] in
            guard let self else { return }
            for await type in self.processor.processedCubeType {
                self.cubeType = type
            }
        }

        // Listen for connection state changes
        connectionListenerTask = Task { [weak self] in
            guard let self else { return }
            for await state in self.communicator.connectionStateChanges {
                if state == .disconnected {
                    self.isConnected = false
                    self.disconnectedContinuation.yield(())
                }
            }
        }
    }

    /// Stop listening to streams
    public func stopListening() {
        moveListenerTask?.cancel()
        moveListenerTask = nil
        stateListenerTask?.cancel()
        stateListenerTask = nil
        orientationListenerTask?.cancel()
        orientationListenerTask = nil
        batteryListenerTask?.cancel()
        batteryListenerTask = nil
        cubeTypeListenerTask?.cancel()
        cubeTypeListenerTask = nil
        connectionListenerTask?.cancel()
        connectionListenerTask = nil
    }

    // MARK: - Commands (with typed throws)

    /// Request the current battery level
    public func requestBattery() throws(GoCubeError) {
        try communicator.sendCommand(.getBattery)
    }

    /// Request battery level and wait for response
    public func getBattery() async throws(GoCubeError) -> Int {
        try communicator.sendCommand(.getBattery)

        let deadline = ContinuousClock.now.advanced(by: configuration.commandTimeout)
        while ContinuousClock.now < deadline {
            if let level = batteryLevel {
                return level
            }
            try? await Task.sleep(for: .milliseconds(50))
        }

        throw .timeout
    }

    /// Request the current cube state
    public func requestState() throws(GoCubeError) {
        try communicator.sendCommand(.getCubeState)
    }

    /// Request cube state and wait for response
    public func getState() async throws(GoCubeError) -> CubeState {
        try communicator.sendCommand(.getCubeState)

        let deadline = ContinuousClock.now.advanced(by: configuration.commandTimeout)
        while ContinuousClock.now < deadline {
            if let state = currentState {
                return state
            }
            try? await Task.sleep(for: .milliseconds(50))
        }

        throw .timeout
    }

    /// Request the cube type
    public func requestCubeType() throws(GoCubeError) {
        try communicator.sendCommand(.getCubeType)
    }

    /// Request cube type and wait for response
    public func fetchCubeType() async throws(GoCubeError) -> GoCubeType {
        try communicator.sendCommand(.getCubeType)

        let deadline = ContinuousClock.now.advanced(by: configuration.commandTimeout)
        while ContinuousClock.now < deadline {
            if let type = cubeType {
                return type
            }
            try? await Task.sleep(for: .milliseconds(50))
        }

        throw .timeout
    }

    /// Reset the cube tracking to solved state
    public func resetToSolved() throws(GoCubeError) {
        try communicator.sendCommand(.resetToSolved)
        currentState = .solved
        moveSequence = MoveSequence()
    }

    /// Reboot the cube
    public func reboot() throws(GoCubeError) {
        try communicator.sendCommand(.reboot)
    }

    /// Enable 3D orientation tracking (~15 Hz updates)
    public func enableOrientation() throws(GoCubeError) {
        try communicator.sendCommand(.enableOrientation)
        isOrientationEnabled = true
    }

    /// Disable 3D orientation tracking
    public func disableOrientation() throws(GoCubeError) {
        try communicator.sendCommand(.disableOrientation)
        isOrientationEnabled = false
    }

    /// Calibrate the orientation sensor
    public func calibrateOrientation() throws(GoCubeError) {
        try communicator.sendCommand(.calibrateOrientation)
    }

    /// Set the current orientation as "home" (identity)
    public func setHomeOrientation() async {
        await processor.setHomeOrientation()
    }

    /// Clear the home orientation
    public func clearHomeOrientation() async {
        await processor.clearHomeOrientation()
    }

    /// Check if home orientation is set
    public func hasHomeOrientation() async -> Bool {
        await processor.hasHomeOrientation()
    }

    /// Request offline statistics
    public func requestOfflineStats() throws(GoCubeError) {
        try communicator.sendCommand(.getOfflineStats)
    }

    // MARK: - LED Control

    /// Flash the LEDs at normal speed
    public func flashLEDs() throws(GoCubeError) {
        try communicator.sendCommand(.flashLEDNormal)
    }

    /// Flash the LEDs slowly
    public func flashLEDsSlow() throws(GoCubeError) {
        try communicator.sendCommand(.flashLEDSlow)
    }

    /// Toggle the animated backlight
    public func toggleAnimatedBacklight() throws(GoCubeError) {
        try communicator.sendCommand(.toggleAnimatedBacklight)
    }

    /// Toggle the backlight on/off
    public func toggleBacklight() throws(GoCubeError) {
        try communicator.sendCommand(.toggleBacklight)
    }

    // MARK: - Move Sequence Management

    /// Clear the accumulated move sequence
    public func clearMoveSequence() {
        moveSequence = MoveSequence()
    }

    // MARK: - Connection

    /// Disconnect from the cube
    public func disconnect() {
        stopListening()
        communicator.disconnect()
        isConnected = false
    }
}

// MARK: - CustomStringConvertible

extension GoCube: CustomStringConvertible {
    public nonisolated var description: String {
        "GoCube(\(name), id: \(id))"
    }
}
