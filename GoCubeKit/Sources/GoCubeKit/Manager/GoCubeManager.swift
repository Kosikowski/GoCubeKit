import Foundation
@preconcurrency import CoreBluetooth
import os.log

/// Delegate protocol for GoCubeManager events
public protocol GoCubeManagerDelegate: AnyObject, Sendable {
    /// Called when the list of discovered devices is updated
    @MainActor func goCubeManager(_ manager: GoCubeManager, didDiscoverDevices devices: [DiscoveredDevice])

    /// Called when a cube is successfully connected
    @MainActor func goCubeManager(_ manager: GoCubeManager, didConnect cube: GoCube)

    /// Called when connection fails
    @MainActor func goCubeManager(_ manager: GoCubeManager, didFailToConnect error: GoCubeError)

    /// Called when Bluetooth state changes
    @MainActor func goCubeManager(_ manager: GoCubeManager, didUpdateBluetoothState state: CBManagerState)
}

// MARK: - Default Implementations

public extension GoCubeManagerDelegate {
    @MainActor func goCubeManager(_ manager: GoCubeManager, didDiscoverDevices devices: [DiscoveredDevice]) {}
    @MainActor func goCubeManager(_ manager: GoCubeManager, didConnect cube: GoCube) {}
    @MainActor func goCubeManager(_ manager: GoCubeManager, didFailToConnect error: GoCubeError) {}
    @MainActor func goCubeManager(_ manager: GoCubeManager, didUpdateBluetoothState state: CBManagerState) {}
}

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

    // MARK: - State (protected by CubeActor isolation)

    /// Currently connected cube
    public private(set) var connectedCube: GoCube?

    /// Whether currently scanning for devices
    public private(set) var isScanning: Bool = false

    /// Delegate for receiving events
    public nonisolated(unsafe) weak var delegate: GoCubeManagerDelegate?

    // MARK: - Callbacks (alternative to delegate)

    /// Callback when devices are discovered
    public nonisolated(unsafe) var onDevicesDiscovered: (@Sendable @MainActor ([DiscoveredDevice]) -> Void)?

    /// Callback when connected
    public nonisolated(unsafe) var onConnected: (@Sendable @MainActor (GoCube) -> Void)?

    /// Callback when connection fails
    public nonisolated(unsafe) var onConnectionFailed: (@Sendable @MainActor (GoCubeError) -> Void)?

    /// Callback when Bluetooth state changes
    public nonisolated(unsafe) var onBluetoothStateChanged: (@Sendable @MainActor (CBManagerState) -> Void)?

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
    }

    /// Setup callbacks after initialization (must be called separately due to actor isolation)
    public func setupCallbacks() {
        // Forward discovered devices
        communicator.onDevicesDiscovered = { [weak self] devices in
            guard let self = self else { return }
            Task { @MainActor in
                self.delegate?.goCubeManager(self, didDiscoverDevices: devices)
                self.onDevicesDiscovered?(devices)
            }
        }

        // Forward Bluetooth state
        communicator.onBluetoothStateChanged = { [weak self] state in
            guard let self = self else { return }
            Task { @MainActor in
                self.delegate?.goCubeManager(self, didUpdateBluetoothState: state)
                self.onBluetoothStateChanged?(state)
            }
        }

        // Track connection state
        communicator.onConnectionStateChanged = { [weak self] connectionState in
            guard let self = self else { return }
            if connectionState == .disconnected {
                Task {
                    await self.clearConnectedCube()
                }
            }
        }
    }

    private func clearConnectedCube() {
        connectedCube = nil
    }

    // MARK: - Public API

    /// Current Bluetooth state
    public nonisolated var bluetoothState: CBManagerState {
        communicator.bluetoothState
    }

    /// Whether Bluetooth is ready for use
    public nonisolated var isBluetoothReady: Bool {
        communicator.isBluetoothReady
    }

    /// Get discovered devices
    public nonisolated var discoveredDevices: [DiscoveredDevice] {
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
            cube.setupCallbacks()
            connectedCube = cube

            // Request initial state
            try? cube.requestState()
            try? cube.requestBattery()
            try? cube.requestCubeType()

            Task { @MainActor in
                self.delegate?.goCubeManager(self, didConnect: cube)
                self.onConnected?(cube)
                cube.delegate?.goCubeDidConnect(cube)
            }

            return cube
        } catch let error as GoCubeError {
            Task { @MainActor in
                self.delegate?.goCubeManager(self, didFailToConnect: error)
                self.onConnectionFailed?(error)
            }
            throw error
        } catch {
            let goCubeError = GoCubeError.connectionFailed(error.localizedDescription)
            Task { @MainActor in
                self.delegate?.goCubeManager(self, didFailToConnect: goCubeError)
                self.onConnectionFailed?(goCubeError)
            }
            throw goCubeError
        }
    }

    /// Disconnect from the current cube
    public func disconnect() {
        communicator.disconnect()
        connectedCube = nil
    }

    /// Connect to the first available GoCube
    /// Uses configuration.scanTimeout for timeout duration
    /// - Returns: The connected GoCube instance
    @discardableResult
    public func connectToFirstAvailable() async throws -> GoCube {
        startScanning()

        // Wait for a device to be discovered with timeout
        // Uses Task.sleep with proper cancellation handling to avoid race conditions
        let device: DiscoveredDevice = try await withThrowingTaskGroup(of: DiscoveredDevice.self) { group in
            // Task to wait for device discovery
            group.addTask {
                while true {
                    let devices = self.communicator.discoveredDevices
                    if let device = devices.first {
                        return device
                    }
                    // Check periodically
                    try await Task.sleep(for: .milliseconds(100))
                }
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
