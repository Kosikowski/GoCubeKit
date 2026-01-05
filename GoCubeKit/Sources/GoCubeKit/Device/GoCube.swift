import Foundation
import os.log

/// Represents a connected GoCube device
/// Isolated to CubeActor for thread-safe state management
@CubeActor
public final class GoCube {

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

    /// Message decoders
    private let moveDecoder = MoveDecoder()
    private let stateDecoder = StateDecoder()
    private let quaternionDecoder = QuaternionDecoder()

    /// Quaternion smoother for display
    private let quaternionSmoother: QuaternionSmoother

    /// Orientation manager for relative orientation
    public let orientationManager = OrientationManager()

    /// Task for listening to message stream
    private var messageListenerTask: Task<Void, Never>?
    private var connectionListenerTask: Task<Void, Never>?

    // MARK: - State (protected by CubeActor isolation)

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

    // MARK: - Callbacks

    /// Delegate for receiving events
    public nonisolated(unsafe) weak var delegate: GoCubeDelegate?

    /// Callback when a move is received
    public nonisolated(unsafe) var onMove: (@Sendable @MainActor (Move) -> Void)?

    /// Callback when cube state is updated
    public nonisolated(unsafe) var onStateUpdated: (@Sendable @MainActor (CubeState) -> Void)?

    /// Callback when orientation is updated
    public nonisolated(unsafe) var onOrientationUpdated: (@Sendable @MainActor (Quaternion) -> Void)?

    /// Callback when battery level is updated
    public nonisolated(unsafe) var onBatteryUpdated: (@Sendable @MainActor (Int) -> Void)?

    /// Callback when cube type is received
    public nonisolated(unsafe) var onCubeTypeReceived: (@Sendable @MainActor (GoCubeType) -> Void)?

    // MARK: - Initialization

    init(device: DiscoveredDevice, communicator: BLECommunicator, configuration: GoCubeConfiguration = .default) {
        self.id = device.id
        self.name = device.name
        self.communicator = communicator
        self.configuration = configuration
        self.quaternionSmoother = QuaternionSmoother(smoothingFactor: configuration.quaternionSmoothingFactor)
    }

    /// Start listening to message and connection streams
    public func startListening() {
        // Listen for messages from the cube
        messageListenerTask = Task { [weak self] in
            guard let self = self else { return }
            for await message in self.communicator.messages {
                await self.handleMessage(message)
            }
        }

        // Listen for connection state changes
        connectionListenerTask = Task { [weak self] in
            guard let self = self else { return }
            for await state in self.communicator.connectionStateChanges {
                if state == .disconnected {
                    Task { @MainActor in
                        self.delegate?.goCubeDidDisconnect(self)
                    }
                }
            }
        }
    }

    /// Stop listening to streams
    public func stopListening() {
        messageListenerTask?.cancel()
        messageListenerTask = nil
        connectionListenerTask?.cancel()
        connectionListenerTask = nil
    }

    // MARK: - Message Handling

    private func handleMessage(_ message: GoCubeMessage) async {
        switch message.type {
        case .rotation:
            await handleRotationMessage(message.payload)

        case .cubeState:
            await handleStateMessage(message.payload)

        case .orientation:
            await handleOrientationMessage(message.payload)

        case .battery:
            await handleBatteryMessage(message.payload)

        case .offlineStats:
            handleOfflineStatsMessage(message.payload)

        case .cubeType:
            await handleCubeTypeMessage(message.payload)
        }
    }

    private func handleRotationMessage(_ payload: Data) async {
        do {
            let moves = try moveDecoder.decode(payload)
            for move in moves {
                moveSequence.append(move)

                Task { @MainActor in
                    self.onMove?(move)
                    self.delegate?.goCube(self, didReceiveMove: move)
                }
            }
        } catch {
            logger.error("Failed to decode rotation: \(error.localizedDescription)")
        }
    }

    private func handleStateMessage(_ payload: Data) async {
        do {
            let state = try stateDecoder.decode(payload)
            currentState = state

            Task { @MainActor in
                self.onStateUpdated?(state)
                self.delegate?.goCube(self, didUpdateState: state)
            }
        } catch {
            logger.error("Failed to decode state: \(error.localizedDescription)")
        }
    }

    private func handleOrientationMessage(_ payload: Data) async {
        do {
            let rawQuaternion = try quaternionDecoder.decode(payload)
            let smoothed = await quaternionSmoother.update(rawQuaternion)
            let relative = await orientationManager.relativeOrientation(smoothed)

            Task { @MainActor in
                self.onOrientationUpdated?(relative)
                self.delegate?.goCube(self, didUpdateOrientation: relative)
            }
        } catch {
            logger.error("Failed to decode orientation: \(error.localizedDescription)")
        }
    }

    private func handleBatteryMessage(_ payload: Data) async {
        guard let level = payload.first else { return }
        let battLevel = Int(min(level, 100))
        batteryLevel = battLevel

        Task { @MainActor in
            self.onBatteryUpdated?(battLevel)
            self.delegate?.goCube(self, didUpdateBattery: battLevel)
        }
    }

    private func handleOfflineStatsMessage(_ payload: Data) {
        // Format: "moves#time#solves"
        if let string = String(data: payload, encoding: .utf8) {
            logger.info("Offline stats: \(string)")
        }
    }

    private func handleCubeTypeMessage(_ payload: Data) async {
        guard let typeRaw = payload.first else { return }
        let type = GoCubeType(rawValue: typeRaw)
        cubeType = type

        Task { @MainActor in
            self.onCubeTypeReceived?(type)
            self.delegate?.goCube(self, didReceiveCubeType: type)
        }
    }

    // MARK: - Commands

    /// Request the current battery level
    public func requestBattery() throws {
        try communicator.sendCommand(.getBattery)
    }

    /// Request battery level and wait for response
    public func getBattery() async throws -> Int {
        try communicator.sendCommand(.getBattery)

        // Poll for result with timeout
        let timeout = configuration.commandTimeout
        let deadline = ContinuousClock.now.advanced(by: timeout)

        while ContinuousClock.now < deadline {
            if let level = batteryLevel {
                return level
            }
            try await Task.sleep(for: .milliseconds(50))
        }

        throw GoCubeError.timeout
    }

    /// Request the current cube state
    public func requestState() throws {
        try communicator.sendCommand(.getCubeState)
    }

    /// Request cube state and wait for response
    public func getState() async throws -> CubeState {
        try communicator.sendCommand(.getCubeState)

        // Poll for result with timeout
        let timeout = configuration.commandTimeout
        let deadline = ContinuousClock.now.advanced(by: timeout)

        while ContinuousClock.now < deadline {
            if let state = currentState {
                return state
            }
            try await Task.sleep(for: .milliseconds(50))
        }

        throw GoCubeError.timeout
    }

    /// Request the cube type
    public func requestCubeType() throws {
        try communicator.sendCommand(.getCubeType)
    }

    /// Request cube type and wait for response
    public func fetchCubeType() async throws -> GoCubeType {
        try communicator.sendCommand(.getCubeType)

        // Poll for result with timeout
        let timeout = configuration.commandTimeout
        let deadline = ContinuousClock.now.advanced(by: timeout)

        while ContinuousClock.now < deadline {
            if let type = cubeType {
                return type
            }
            try await Task.sleep(for: .milliseconds(50))
        }

        throw GoCubeError.timeout
    }

    /// Reset the cube tracking to solved state
    /// Note: Updates local state immediately; actual cube state is confirmed via state callback
    public func resetToSolved() throws {
        try communicator.sendCommand(.resetToSolved)
        currentState = .solved
        moveSequence = MoveSequence()
    }

    /// Reboot the cube
    public func reboot() throws {
        try communicator.sendCommand(.reboot)
    }

    /// Enable 3D orientation tracking (~15 Hz updates)
    public func enableOrientation() throws {
        try communicator.sendCommand(.enableOrientation)
        isOrientationEnabled = true
    }

    /// Disable 3D orientation tracking
    public func disableOrientation() throws {
        try communicator.sendCommand(.disableOrientation)
        isOrientationEnabled = false
    }

    /// Calibrate the orientation sensor
    public func calibrateOrientation() throws {
        try communicator.sendCommand(.calibrateOrientation)
    }

    /// Set the current orientation as "home" (identity)
    public func setHomeOrientation() async {
        if let current = await quaternionSmoother.current {
            await orientationManager.setHome(current)
        }
    }

    /// Clear the home orientation
    public func clearHomeOrientation() async {
        await orientationManager.clearHome()
    }

    /// Request offline statistics
    public func requestOfflineStats() throws {
        try communicator.sendCommand(.getOfflineStats)
    }

    // MARK: - LED Control

    /// Flash the LEDs at normal speed
    public func flashLEDs() throws {
        try communicator.sendCommand(.flashLEDNormal)
    }

    /// Flash the LEDs slowly
    public func flashLEDsSlow() throws {
        try communicator.sendCommand(.flashLEDSlow)
    }

    /// Toggle the animated backlight
    public func toggleAnimatedBacklight() throws {
        try communicator.sendCommand(.toggleAnimatedBacklight)
    }

    /// Toggle the backlight on/off
    public func toggleBacklight() throws {
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
    }
}

// MARK: - CustomStringConvertible

extension GoCube: CustomStringConvertible {
    public nonisolated var description: String {
        "GoCube(\(name), id: \(id))"
    }
}
