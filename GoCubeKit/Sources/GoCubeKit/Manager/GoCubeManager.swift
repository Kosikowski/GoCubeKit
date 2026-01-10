import Foundation
@preconcurrency import CoreBluetooth
import Observation
import os.log

/// Manager for discovering and connecting to GoCube devices
/// Uses @Observable for reactive state updates in SwiftUI
@Observable
@MainActor
public final class GoCubeManager: Sendable {

    // MARK: - Shared Instance (optional convenience)

    /// Shared instance of GoCubeManager for convenience
    /// Note: You can create your own instances for testing or multiple cube support
    public static let shared = GoCubeManager()

    // MARK: - Properties

    private let logger = Logger(subsystem: "com.gocubekit", category: "Manager")

    /// The BLE communicator
    private let communicator: BLECommunicator

    /// Configuration
    public nonisolated let configuration: GoCubeConfiguration

    // MARK: - Stream Listener Tasks

    private var discoveryListenerTask: Task<Void, Never>?
    private var bluetoothStateListenerTask: Task<Void, Never>?
    private var connectionStateListenerTask: Task<Void, Never>?

    // MARK: - Observable State

    /// Currently connected cube
    public private(set) var connectedCube: GoCube?

    /// Whether currently scanning for devices
    public private(set) var isScanning: Bool = false

    /// Discovered devices (observable array for SwiftUI)
    public private(set) var discoveredDevices: [DiscoveredDevice] = []

    /// Current Bluetooth state
    public private(set) var bluetoothState: CBManagerState = .unknown

    /// Whether Bluetooth is ready for use
    public var isBluetoothReady: Bool {
        bluetoothState == .poweredOn
    }

    /// Whether connected to a cube
    public var isConnected: Bool {
        connectedCube != nil
    }

    // MARK: - Reconnection State

    /// Last connected device (for auto-reconnection)
    private var lastConnectedDevice: DiscoveredDevice?

    /// Current reconnection attempt count
    private var reconnectAttempts: Int = 0

    /// Whether we're currently attempting to reconnect
    private var isReconnecting: Bool = false

    /// Flag to prevent reconnection when user explicitly disconnects
    private var shouldReconnect: Bool = true

    /// Task for reconnection attempts
    private var reconnectTask: Task<Void, Never>?

    // MARK: - Event Streams (for external consumers)

    /// Stream of successful connections
    public let connections: AsyncStream<GoCube>
    private let connectionsContinuation: AsyncStream<GoCube>.Continuation

    /// Stream of connection failures
    public let connectionFailures: AsyncStream<GoCubeError>
    private let connectionFailuresContinuation: AsyncStream<GoCubeError>.Continuation

    // MARK: - Initialization

    /// Create a GoCubeManager with default communicator and configuration
    public convenience init() {
        self.init(communicator: BLECommunicator(), configuration: .default)
    }

    /// Create a GoCubeManager with custom configuration
    public convenience init(configuration: GoCubeConfiguration) {
        self.init(communicator: BLECommunicator(), configuration: configuration)
    }

    /// Create a GoCubeManager with custom communicator and configuration (for testing)
    public init(communicator: BLECommunicator, configuration: GoCubeConfiguration = .default) {
        self.communicator = communicator
        self.configuration = configuration

        // Initialize AsyncStreams using makeStream (iOS 17+)
        (connections, connectionsContinuation) = AsyncStream.makeStream(of: GoCube.self)
        (connectionFailures, connectionFailuresContinuation) = AsyncStream.makeStream(of: GoCubeError.self)
    }

    deinit {
        connectionsContinuation.finish()
        connectionFailuresContinuation.finish()
    }

    /// Start listening to BLE streams and updating observable state
    public func startListening() {
        // Listen for device discoveries
        discoveryListenerTask = Task { [weak self] in
            guard let self else { return }
            for await devices in self.communicator.discoveries {
                self.discoveredDevices = devices
            }
        }

        // Listen for Bluetooth state changes
        bluetoothStateListenerTask = Task { [weak self] in
            guard let self else { return }
            for await state in self.communicator.bluetoothStateChanges {
                self.bluetoothState = state
            }
        }

        // Listen for connection state changes
        connectionStateListenerTask = Task { [weak self] in
            guard let self else { return }
            for await state in self.communicator.connectionStateChanges {
                if state == .disconnected {
                    self.handleDisconnection()
                }
            }
        }
    }

    /// Handle disconnection event
    private func handleDisconnection() {
        let wasConnected = connectedCube != nil
        connectedCube = nil

        // Attempt reconnection if configured and not explicitly disconnected
        if wasConnected && configuration.autoReconnect && shouldReconnect {
            attemptReconnection()
        }
    }

    /// Attempt to reconnect to the last connected device
    private func attemptReconnection() {
        guard let device = lastConnectedDevice else {
            logger.info("No last connected device for reconnection")
            return
        }

        guard !isReconnecting else {
            logger.debug("Already attempting reconnection")
            return
        }

        let maxAttempts = configuration.maxReconnectAttempts

        // Check if we've exceeded max attempts (0 = unlimited)
        if maxAttempts > 0 && reconnectAttempts >= maxAttempts {
            logger.info("Max reconnection attempts (\(maxAttempts)) reached")
            reconnectAttempts = 0
            return
        }

        isReconnecting = true
        reconnectAttempts += 1

        logger.info("Attempting reconnection (attempt \(self.reconnectAttempts))")

        reconnectTask = Task { [weak self] in
            guard let self else { return }

            // Wait before attempting reconnection
            try? await Task.sleep(for: self.configuration.reconnectDelay)

            // Check if we should still reconnect
            guard self.shouldReconnect && self.connectedCube == nil else {
                self.isReconnecting = false
                return
            }

            do {
                _ = try await self.connect(to: device)
                self.logger.info("Reconnection successful")
                self.reconnectAttempts = 0
            } catch {
                self.logger.error("Reconnection failed: \(error.localizedDescription)")
            }

            self.isReconnecting = false
        }
    }

    /// Stop listening to BLE streams
    public func stopListening() {
        discoveryListenerTask?.cancel()
        discoveryListenerTask = nil
        bluetoothStateListenerTask?.cancel()
        bluetoothStateListenerTask = nil
        connectionStateListenerTask?.cancel()
        connectionStateListenerTask = nil
    }

    // MARK: - Scanning

    /// Start scanning for GoCube devices
    public func startScanning() {
        isScanning = true
        communicator.startScanning()
    }

    /// Stop scanning for devices
    public func stopScanning() {
        isScanning = false
        communicator.stopScanning()
    }

    // MARK: - Connection

    /// Connect to a discovered device
    /// - Parameter device: The device to connect to
    /// - Returns: The connected GoCube instance
    @discardableResult
    public func connect(to device: DiscoveredDevice) async throws(GoCubeError) -> GoCube {
        do {
            // Create CubeProcessor for processing with configured smoothing factor
            await communicator.createProcessor(smoothingFactor: configuration.quaternionSmoothingFactor)

            try await communicator.connect(to: device)

            guard let processor = communicator.processor else {
                throw GoCubeError.connectionFailed("Failed to create cube processor")
            }

            let cube = GoCube(device: device, communicator: communicator, processor: processor, configuration: configuration)
            cube.startListening()
            connectedCube = cube

            // Store for potential reconnection
            lastConnectedDevice = device
            shouldReconnect = true
            reconnectAttempts = 0

            // Request initial state
            try? cube.requestState()
            try? cube.requestBattery()
            try? cube.requestCubeType()

            // Emit to AsyncStream
            connectionsContinuation.yield(cube)

            return cube
        } catch let error as GoCubeError {
            communicator.destroyProcessor()
            connectionFailuresContinuation.yield(error)
            throw error
        } catch {
            communicator.destroyProcessor()
            let cubeError = GoCubeError.connectionFailed(error.localizedDescription)
            connectionFailuresContinuation.yield(cubeError)
            throw cubeError
        }
    }

    /// Disconnect from the current cube
    /// - Parameter allowReconnect: If false, prevents automatic reconnection (default: false)
    public func disconnect(allowReconnect: Bool = false) {
        // Cancel any pending reconnection
        reconnectTask?.cancel()
        reconnectTask = nil
        isReconnecting = false

        // Prevent auto-reconnection unless explicitly allowed
        shouldReconnect = allowReconnect

        connectedCube?.stopListening()
        communicator.disconnect()
        communicator.destroyProcessor()
        connectedCube = nil

        if !allowReconnect {
            reconnectAttempts = 0
        }
    }

    /// Connect to the first available GoCube
    /// Uses configuration.scanTimeout for timeout duration
    /// - Returns: The connected GoCube instance
    @discardableResult
    public func connectToFirstAvailable() async throws(GoCubeError) -> GoCube {
        startScanning()

        // Wait for a device to be discovered with timeout
        let device: DiscoveredDevice
        do {
            device = try await withThrowingTaskGroup(of: DiscoveredDevice.self) { group in
                // Task to wait for device discovery
                group.addTask {
                    for await devices in self.communicator.discoveries {
                        if let device = devices.first {
                            return device
                        }
                    }
                    throw GoCubeError.connection(.deviceNotFound)
                }

                // Task for timeout
                group.addTask {
                    try await Task.sleep(for: self.configuration.scanTimeout)
                    throw GoCubeError.timeout
                }

                // Return first result (either device found or timeout)
                guard let result = try await group.next() else {
                    throw GoCubeError.timeout
                }
                group.cancelAll()
                return result
            }
        } catch let error as GoCubeError {
            stopScanning()
            throw error
        } catch {
            stopScanning()
            throw .connectionFailed(error.localizedDescription)
        }

        stopScanning()
        return try await connect(to: device)
    }
}
