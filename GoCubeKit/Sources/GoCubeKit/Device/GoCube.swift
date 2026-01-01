import Foundation
import Combine
import CoreBluetooth

/// Represents a connected GoCube device
public class GoCube: @unchecked Sendable {

    // MARK: - Properties

    /// Device identifier
    public let id: UUID

    /// Device name
    public let name: String

    /// Delegate for receiving events
    public weak var delegate: GoCubeDelegate?

    /// BLE communicator
    private let communicator: BLECommunicator

    /// Message decoders
    private let moveDecoder = MoveDecoder()
    private let stateDecoder = StateDecoder()
    private let quaternionDecoder = QuaternionDecoder()

    /// Quaternion smoother for display
    private let quaternionSmoother = QuaternionSmoother(smoothingFactor: 0.5)

    /// Orientation manager for relative orientation
    public let orientationManager = OrientationManager()

    /// Cancellables for Combine subscriptions
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Publishers

    private let _movesSubject = PassthroughSubject<Move, Never>()
    /// Publisher for cube moves
    public var movesPublisher: AnyPublisher<Move, Never> {
        _movesSubject.eraseToAnyPublisher()
    }

    private let _stateSubject = CurrentValueSubject<CubeState?, Never>(nil)
    /// Publisher for cube state changes
    public var statePublisher: AnyPublisher<CubeState, Never> {
        _stateSubject.compactMap { $0 }.eraseToAnyPublisher()
    }

    private let _orientationSubject = PassthroughSubject<Quaternion, Never>()
    /// Publisher for orientation updates
    public var orientationPublisher: AnyPublisher<Quaternion, Never> {
        _orientationSubject.eraseToAnyPublisher()
    }

    private let _batterySubject = CurrentValueSubject<Int?, Never>(nil)
    /// Publisher for battery level
    public var batteryPublisher: AnyPublisher<Int, Never> {
        _batterySubject.compactMap { $0 }.eraseToAnyPublisher()
    }

    private let _cubeTypeSubject = CurrentValueSubject<GoCubeType?, Never>(nil)
    /// Publisher for cube type
    public var cubeTypePublisher: AnyPublisher<GoCubeType, Never> {
        _cubeTypeSubject.compactMap { $0 }.eraseToAnyPublisher()
    }

    private let _moveSequenceSubject = CurrentValueSubject<MoveSequence, Never>(MoveSequence())
    /// Publisher for the accumulated move sequence
    public var moveSequencePublisher: AnyPublisher<MoveSequence, Never> {
        _moveSequenceSubject.eraseToAnyPublisher()
    }

    // MARK: - State

    /// Current cube state (if known)
    public var currentState: CubeState? {
        _stateSubject.value
    }

    /// Current battery level (if known)
    public var batteryLevel: Int? {
        _batterySubject.value
    }

    /// Current cube type (if known)
    public var cubeType: GoCubeType? {
        _cubeTypeSubject.value
    }

    /// Accumulated move sequence since last reset
    public var moveSequence: MoveSequence {
        _moveSequenceSubject.value
    }

    /// Whether orientation tracking is enabled
    private(set) var isOrientationEnabled = false

    // MARK: - Initialization

    init(device: DiscoveredDevice, communicator: BLECommunicator) {
        self.id = device.id
        self.name = device.name
        self.communicator = communicator

        setupSubscriptions()
    }

    private func setupSubscriptions() {
        // Subscribe to received messages
        communicator.receivedMessagePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] message in
                self?.handleMessage(message)
            }
            .store(in: &cancellables)

        // Subscribe to connection state changes
        communicator.connectionStatePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                guard let self = self else { return }
                if state == .disconnected {
                    self.delegate?.goCubeDidDisconnect(self)
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Message Handling

    private func handleMessage(_ message: GoCubeMessage) {
        switch message.type {
        case .rotation:
            handleRotationMessage(message.payload)

        case .cubeState:
            handleStateMessage(message.payload)

        case .orientation:
            handleOrientationMessage(message.payload)

        case .battery:
            handleBatteryMessage(message.payload)

        case .offlineStats:
            handleOfflineStatsMessage(message.payload)

        case .cubeType:
            handleCubeTypeMessage(message.payload)
        }
    }

    private func handleRotationMessage(_ payload: Data) {
        do {
            let moves = try moveDecoder.decode(payload)
            for move in moves {
                _movesSubject.send(move)
                var sequence = _moveSequenceSubject.value
                sequence.append(move)
                _moveSequenceSubject.send(sequence)
                delegate?.goCube(self, didReceiveMove: move)
            }
        } catch {
            print("GoCubeKit: Failed to decode rotation: \(error)")
        }
    }

    private func handleStateMessage(_ payload: Data) {
        do {
            let state = try stateDecoder.decode(payload)
            _stateSubject.send(state)
            delegate?.goCube(self, didUpdateState: state)
        } catch {
            print("GoCubeKit: Failed to decode state: \(error)")
        }
    }

    private func handleOrientationMessage(_ payload: Data) {
        do {
            let rawQuaternion = try quaternionDecoder.decode(payload)
            let smoothed = quaternionSmoother.update(rawQuaternion)
            let relative = orientationManager.relativeOrientation(smoothed)
            _orientationSubject.send(relative)
            delegate?.goCube(self, didUpdateOrientation: relative)
        } catch {
            print("GoCubeKit: Failed to decode orientation: \(error)")
        }
    }

    private func handleBatteryMessage(_ payload: Data) {
        guard let level = payload.first else { return }
        let batteryLevel = Int(min(level, 100))
        _batterySubject.send(batteryLevel)
        delegate?.goCube(self, didUpdateBattery: batteryLevel)
    }

    private func handleOfflineStatsMessage(_ payload: Data) {
        // Format: "moves#time#solves"
        // Currently just logging, could expose this in the future
        if let string = String(data: payload, encoding: .utf8) {
            print("GoCubeKit: Offline stats: \(string)")
        }
    }

    private func handleCubeTypeMessage(_ payload: Data) {
        guard let typeRaw = payload.first else { return }
        let type = GoCubeType(rawValue: typeRaw)
        _cubeTypeSubject.send(type)
        delegate?.goCube(self, didReceiveCubeType: type)
    }

    // MARK: - Commands

    /// Request the current battery level
    public func requestBattery() throws {
        try communicator.sendCommand(.getBattery)
    }

    /// Request battery level and wait for response
    public func getBattery() async throws -> Int {
        try communicator.sendCommand(.getBattery)

        return try await withCheckedThrowingContinuation { continuation in
            var cancellable: AnyCancellable?
            cancellable = batteryPublisher
                .timeout(.seconds(5), scheduler: DispatchQueue.main)
                .first()
                .sink(
                    receiveCompletion: { completion in
                        if case .failure = completion {
                            continuation.resume(throwing: GoCubeError.timeout)
                        }
                        cancellable?.cancel()
                    },
                    receiveValue: { level in
                        continuation.resume(returning: level)
                        cancellable?.cancel()
                    }
                )
        }
    }

    /// Request the current cube state
    public func requestState() throws {
        try communicator.sendCommand(.getCubeState)
    }

    /// Request cube state and wait for response
    public func getState() async throws -> CubeState {
        try communicator.sendCommand(.getCubeState)

        return try await withCheckedThrowingContinuation { continuation in
            var cancellable: AnyCancellable?
            cancellable = statePublisher
                .timeout(.seconds(5), scheduler: DispatchQueue.main)
                .first()
                .sink(
                    receiveCompletion: { completion in
                        if case .failure = completion {
                            continuation.resume(throwing: GoCubeError.timeout)
                        }
                        cancellable?.cancel()
                    },
                    receiveValue: { state in
                        continuation.resume(returning: state)
                        cancellable?.cancel()
                    }
                )
        }
    }

    /// Request the cube type
    public func requestCubeType() throws {
        try communicator.sendCommand(.getCubeType)
    }

    /// Request cube type and wait for response
    public func getCubeType() async throws -> GoCubeType {
        try communicator.sendCommand(.getCubeType)

        return try await withCheckedThrowingContinuation { continuation in
            var cancellable: AnyCancellable?
            cancellable = cubeTypePublisher
                .timeout(.seconds(5), scheduler: DispatchQueue.main)
                .first()
                .sink(
                    receiveCompletion: { completion in
                        if case .failure = completion {
                            continuation.resume(throwing: GoCubeError.timeout)
                        }
                        cancellable?.cancel()
                    },
                    receiveValue: { type in
                        continuation.resume(returning: type)
                        cancellable?.cancel()
                    }
                )
        }
    }

    /// Reset the cube tracking to solved state
    public func resetToSolved() throws {
        try communicator.sendCommand(.resetToSolved)
        _stateSubject.send(.solved)
        clearMoveSequence()
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
    public func setHomeOrientation() {
        if let current = quaternionSmoother.current {
            orientationManager.setHome(current)
        }
    }

    /// Clear the home orientation
    public func clearHomeOrientation() {
        orientationManager.clearHome()
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
        _moveSequenceSubject.send(MoveSequence())
    }

    // MARK: - Connection

    /// Disconnect from the cube
    public func disconnect() {
        communicator.disconnect()
    }
}

// MARK: - CustomStringConvertible

extension GoCube: CustomStringConvertible {
    public var description: String {
        "GoCube(\(name), id: \(id))"
    }
}
