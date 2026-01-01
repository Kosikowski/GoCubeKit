import Foundation
import Combine
import CoreBluetooth

/// Delegate protocol for GoCubeManager events
public protocol GoCubeManagerDelegate: AnyObject {
    /// Called when the list of discovered devices is updated
    func goCubeManager(_ manager: GoCubeManager, didDiscoverDevices devices: [DiscoveredDevice])

    /// Called when a cube is successfully connected
    func goCubeManager(_ manager: GoCubeManager, didConnect cube: GoCube)

    /// Called when connection fails
    func goCubeManager(_ manager: GoCubeManager, didFailToConnect error: GoCubeError)

    /// Called when Bluetooth state changes
    func goCubeManager(_ manager: GoCubeManager, didUpdateBluetoothState state: CBManagerState)
}

// MARK: - Default Implementations

public extension GoCubeManagerDelegate {
    func goCubeManager(_ manager: GoCubeManager, didDiscoverDevices devices: [DiscoveredDevice]) {}
    func goCubeManager(_ manager: GoCubeManager, didConnect cube: GoCube) {}
    func goCubeManager(_ manager: GoCubeManager, didFailToConnect error: GoCubeError) {}
    func goCubeManager(_ manager: GoCubeManager, didUpdateBluetoothState state: CBManagerState) {}
}

/// Manager for discovering and connecting to GoCube devices
public class GoCubeManager: @unchecked Sendable {

    // MARK: - Singleton

    /// Shared instance of GoCubeManager
    public static let shared = GoCubeManager()

    // MARK: - Properties

    /// Delegate for receiving events
    public weak var delegate: GoCubeManagerDelegate?

    /// The BLE communicator
    private let communicator = BLECommunicator()

    /// Currently connected cube
    private(set) var connectedCube: GoCube?

    /// Cancellables for Combine subscriptions
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Publishers

    private let _discoveredDevicesSubject = CurrentValueSubject<[DiscoveredDevice], Never>([])
    /// Publisher for discovered devices
    public var discoveredDevicesPublisher: AnyPublisher<[DiscoveredDevice], Never> {
        _discoveredDevicesSubject.eraseToAnyPublisher()
    }

    private let _connectedCubeSubject = CurrentValueSubject<GoCube?, Never>(nil)
    /// Publisher for connected cube
    public var connectedCubePublisher: AnyPublisher<GoCube?, Never> {
        _connectedCubeSubject.eraseToAnyPublisher()
    }

    private let _bluetoothStateSubject = CurrentValueSubject<CBManagerState, Never>(.unknown)
    /// Publisher for Bluetooth state
    public var bluetoothStatePublisher: AnyPublisher<CBManagerState, Never> {
        _bluetoothStateSubject.eraseToAnyPublisher()
    }

    private let _isConnectedSubject = CurrentValueSubject<Bool, Never>(false)
    /// Publisher for connection state
    public var isConnectedPublisher: AnyPublisher<Bool, Never> {
        _isConnectedSubject.eraseToAnyPublisher()
    }

    private let _isScanningSubject = CurrentValueSubject<Bool, Never>(false)
    /// Publisher for scanning state
    public var isScanningPublisher: AnyPublisher<Bool, Never> {
        _isScanningSubject.eraseToAnyPublisher()
    }

    // MARK: - State

    /// Current list of discovered devices
    public var discoveredDevices: [DiscoveredDevice] {
        _discoveredDevicesSubject.value
    }

    /// Current Bluetooth state
    public var bluetoothState: CBManagerState {
        _bluetoothStateSubject.value
    }

    /// Whether Bluetooth is ready for use
    public var isBluetoothReady: Bool {
        communicator.isBluetoothReady
    }

    /// Whether currently scanning
    public var isScanning: Bool {
        _isScanningSubject.value
    }

    /// Whether connected to a cube
    public var isConnected: Bool {
        _isConnectedSubject.value
    }

    // MARK: - Initialization

    private init() {
        setupSubscriptions()
    }

    /// Create a custom instance (for testing or advanced use cases)
    public init(communicator: BLECommunicator) {
        setupSubscriptions()
    }

    private func setupSubscriptions() {
        // Forward discovered devices
        communicator.discoveredDevicesPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] devices in
                guard let self = self else { return }
                self._discoveredDevicesSubject.send(devices)
                self.delegate?.goCubeManager(self, didDiscoverDevices: devices)
            }
            .store(in: &cancellables)

        // Forward Bluetooth state
        communicator.bluetoothStatePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                guard let self = self else { return }
                self._bluetoothStateSubject.send(state)
                self.delegate?.goCubeManager(self, didUpdateBluetoothState: state)
            }
            .store(in: &cancellables)

        // Track connection state
        communicator.connectionStatePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                guard let self = self else { return }
                let isConnected = state == .connected
                self._isConnectedSubject.send(isConnected)

                if state == .disconnected {
                    self.connectedCube = nil
                    self._connectedCubeSubject.send(nil)
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Scanning

    /// Start scanning for GoCube devices
    public func startScanning() {
        _isScanningSubject.send(true)
        communicator.startScanning()
    }

    /// Stop scanning for devices
    public func stopScanning() {
        _isScanningSubject.send(false)
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

            let cube = GoCube(device: device, communicator: communicator)
            connectedCube = cube
            _connectedCubeSubject.send(cube)

            // Request initial state
            try? cube.requestState()
            try? cube.requestBattery()
            try? cube.requestCubeType()

            delegate?.goCubeManager(self, didConnect: cube)
            cube.delegate?.goCubeDidConnect(cube)

            return cube
        } catch let error as BLEError {
            let goCubeError = mapBLEError(error)
            delegate?.goCubeManager(self, didFailToConnect: goCubeError)
            throw goCubeError
        } catch {
            let goCubeError = GoCubeError.connectionFailed(error.localizedDescription)
            delegate?.goCubeManager(self, didFailToConnect: goCubeError)
            throw goCubeError
        }
    }

    /// Disconnect from the current cube
    public func disconnect() {
        communicator.disconnect()
        connectedCube = nil
        _connectedCubeSubject.send(nil)
    }

    /// Connect to the first available GoCube
    /// - Parameter timeout: How long to scan before giving up
    /// - Returns: The connected GoCube instance
    @discardableResult
    public func connectToFirstAvailable(timeout: TimeInterval = 10) async throws -> GoCube {
        startScanning()

        // Wait for a device to be discovered with timeout
        let device = try await withThrowingTaskGroup(of: DiscoveredDevice.self) { group in
            // Task to wait for device discovery
            group.addTask {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<DiscoveredDevice, Error>) in
                    var cancellable: AnyCancellable?
                    var hasResumed = false

                    cancellable = self.discoveredDevicesPublisher
                        .filter { !$0.isEmpty }
                        .first()
                        .sink(
                            receiveCompletion: { _ in
                                cancellable?.cancel()
                            },
                            receiveValue: { devices in
                                guard !hasResumed, let device = devices.first else { return }
                                hasResumed = true
                                continuation.resume(returning: device)
                                cancellable?.cancel()
                            }
                        )
                }
            }

            // Task for timeout
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
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

    // MARK: - Helpers

    private func mapBLEError(_ error: BLEError) -> GoCubeError {
        switch error {
        case .bluetoothUnavailable:
            return .bluetoothUnavailable
        case .bluetoothUnauthorized:
            return .bluetoothUnauthorized
        case .bluetoothPoweredOff:
            return .bluetoothPoweredOff
        case .connectionFailed(let reason):
            return .connectionFailed(reason)
        case .disconnected:
            return .notConnected
        case .notConnected:
            return .notConnected
        case .timeout:
            return .timeout
        default:
            return .communicationError(String(describing: error))
        }
    }
}
