import Foundation
@preconcurrency import CoreBluetooth
import os.log

/// Manager for discovering and connecting to GoCube devices
/// Isolated to CubeActor for thread-safe state management
@CubeActor
public final class GoCubeManager {

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

    // MARK: - Public AsyncStreams (modern Swift concurrency API)

    /// Stream of discovered devices
    public let deviceDiscoveries: AsyncStream<[DiscoveredDevice]>
    private let deviceDiscoveriesContinuation: AsyncStream<[DiscoveredDevice]>.Continuation

    /// Stream of successful connections
    public let connections: AsyncStream<GoCube>
    private let connectionsContinuation: AsyncStream<GoCube>.Continuation

    /// Stream of connection failures
    public let connectionFailures: AsyncStream<GoCubeError>
    private let connectionFailuresContinuation: AsyncStream<GoCubeError>.Continuation

    /// Stream of Bluetooth state changes
    public let bluetoothStateUpdates: AsyncStream<CBManagerState>
    private let bluetoothStateUpdatesContinuation: AsyncStream<CBManagerState>.Continuation

    // MARK: - State (protected by CubeActor isolation)

    /// Currently connected cube
    public private(set) var connectedCube: GoCube?

    /// Whether currently scanning for devices
    public private(set) var isScanning: Bool = false

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

        // Initialize AsyncStreams
        var discoveriesCont: AsyncStream<[DiscoveredDevice]>.Continuation!
        deviceDiscoveries = AsyncStream { discoveriesCont = $0 }
        deviceDiscoveriesContinuation = discoveriesCont

        var connectionsCont: AsyncStream<GoCube>.Continuation!
        connections = AsyncStream { connectionsCont = $0 }
        connectionsContinuation = connectionsCont

        var failuresCont: AsyncStream<GoCubeError>.Continuation!
        connectionFailures = AsyncStream { failuresCont = $0 }
        connectionFailuresContinuation = failuresCont

        var btStateCont: AsyncStream<CBManagerState>.Continuation!
        bluetoothStateUpdates = AsyncStream { btStateCont = $0 }
        bluetoothStateUpdatesContinuation = btStateCont
    }

    deinit {
        deviceDiscoveriesContinuation.finish()
        connectionsContinuation.finish()
        connectionFailuresContinuation.finish()
        bluetoothStateUpdatesContinuation.finish()
    }

    /// Start listening to BLE streams and forwarding to public AsyncStreams
    public func startListening() {
        // Listen for device discoveries
        discoveryListenerTask = Task { [weak self] in
            guard let self = self else { return }
            for await devices in self.communicator.discoveries {
                self.deviceDiscoveriesContinuation.yield(devices)
            }
        }

        // Listen for Bluetooth state changes
        bluetoothStateListenerTask = Task { [weak self] in
            guard let self = self else { return }
            for await state in self.communicator.bluetoothStateChanges {
                self.bluetoothStateUpdatesContinuation.yield(state)
            }
        }

        // Listen for connection state changes
        connectionStateListenerTask = Task { [weak self] in
            guard let self = self else { return }
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
            guard let self = self else { return }

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
                // Will try again on next disconnection event or we could retry here
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

    // MARK: - Public API

    /// Current Bluetooth state
    public var bluetoothState: CBManagerState {
        communicator.bluetoothState
    }

    /// Whether Bluetooth is ready for use
    public var isBluetoothReady: Bool {
        communicator.isBluetoothReady
    }

    /// Get discovered devices
    public var discoveredDevices: [DiscoveredDevice] {
        communicator.discoveredDevices
    }

    /// Whether connected to a cube
    public var isConnected: Bool {
        connectedCube != nil
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
    public func connect(to device: DiscoveredDevice) async throws -> GoCube {
        do {
            try await communicator.connect(to: device)

            let cube = GoCube(device: device, communicator: communicator, configuration: configuration)
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
            connectionFailuresContinuation.yield(error)
            throw error
        } catch {
            let goCubeError = GoCubeError.connectionFailed(error.localizedDescription)
            connectionFailuresContinuation.yield(goCubeError)
            throw goCubeError
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
        connectedCube = nil

        if !allowReconnect {
            reconnectAttempts = 0
        }
    }

    /// Connect to the first available GoCube
    /// Uses configuration.scanTimeout for timeout duration
    /// - Returns: The connected GoCube instance
    @discardableResult
    public func connectToFirstAvailable() async throws -> GoCube {
        startScanning()

        // Wait for a device to be discovered with timeout
        let device: DiscoveredDevice = try await withThrowingTaskGroup(of: DiscoveredDevice.self) { group in
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

        stopScanning()
        return try await connect(to: device)
    }
}
