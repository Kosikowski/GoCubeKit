@preconcurrency import CoreBluetooth
import Foundation
import os.log

/// Represents a discovered GoCube device
public struct DiscoveredDevice: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let name: String
    public let rssi: Int
    public nonisolated(unsafe) let peripheral: CBPeripheral

    public init(peripheral: CBPeripheral, rssi: Int) {
        id = peripheral.identifier
        name = peripheral.name ?? "Unknown GoCube"
        self.rssi = rssi
        self.peripheral = peripheral
    }

    public static func == (lhs: DiscoveredDevice, rhs: DiscoveredDevice) -> Bool {
        lhs.id == rhs.id
    }
}

/// Connection state for a GoCube device
public enum ConnectionState: Equatable, Sendable {
    case disconnected
    case connecting
    case connected
    case disconnecting
}

// MARK: - BLE Delegate Proxy

/// Non-actor proxy that handles CoreBluetooth delegate callbacks
/// Raw data is yielded directly to AsyncStream (minimal overhead)
/// Connection events dispatch to MainActor (infrequent, needs UI state update)
private final class BLEDelegateProxy: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate, @unchecked Sendable {
    weak var communicator: BLECommunicator?

    /// Continuation for raw BLE data - yields directly without Task (high frequency path)
    var rawDataContinuation: AsyncStream<Data>.Continuation?

    // MARK: - CBCentralManagerDelegate

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor in
            communicator?.handleBluetoothStateUpdate(central.state)
        }
    }

    func centralManager(
        _: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData _: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let device = DiscoveredDevice(peripheral: peripheral, rssi: RSSI.intValue)
        Task { @MainActor in
            communicator?.handleDiscovery(device)
        }
    }

    func centralManager(_: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Task { @MainActor in
            communicator?.handleDidConnect(peripheral)
        }
    }

    func centralManager(
        _: CBCentralManager,
        didFailToConnect _: CBPeripheral,
        error: Error?
    ) {
        Task { @MainActor in
            communicator?.handleDidFailToConnect(error)
        }
    }

    func centralManager(
        _: CBCentralManager,
        didDisconnectPeripheral _: CBPeripheral,
        error: Error?
    ) {
        Task { @MainActor in
            communicator?.handleDidDisconnect(error)
        }
    }

    // MARK: - CBPeripheralDelegate

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        Task { @MainActor in
            communicator?.handleDidDiscoverServices(peripheral, error: error)
        }
    }

    func peripheral(
        _: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        Task { @MainActor in
            communicator?.handleDidDiscoverCharacteristics(service, error: error)
        }
    }

    func peripheral(
        _: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        // Hot path: yield directly to stream (no Task overhead)
        if let error = error {
            GoCubeLogger.error("didUpdateValueFor error: \(error)")
            return
        }
        guard characteristic.uuid == GoCubeBLE.notifyCharacteristicUUID else {
            GoCubeLogger.debug("didUpdateValueFor wrong characteristic: \(characteristic.uuid)")
            return
        }
        guard let data = characteristic.value else {
            GoCubeLogger.warning("didUpdateValueFor no data")
            return
        }
        GoCubeLogger.logData(data, prefix: "BLE received")
        if rawDataContinuation == nil {
            GoCubeLogger.warning("rawDataContinuation is nil!")
        }
        rawDataContinuation?.yield(data)
    }

    func peripheral(
        _: CBPeripheral,
        didUpdateNotificationStateFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        if let error = error {
            GoCubeLogger.error("Notification state error for \(characteristic.uuid): \(error)")
            Task { @MainActor in
                communicator?.handleNotificationStateError(error)
            }
        } else {
            GoCubeLogger.info("Notifications enabled for \(characteristic.uuid), isNotifying: \(characteristic.isNotifying)")
        }
    }
}

// MARK: - BLECommunicator

/// Low-level BLE communication handler
/// Isolated to MainActor for thread-safe state management and SwiftUI compatibility
/// Heavy data processing is delegated to BLEActor (off MainActor)
@MainActor
public final class BLECommunicator: Sendable {
    // MARK: - Properties

    private let logger = Logger(subsystem: "com.gocubekit", category: "BLE")
    private let messageParser = MessageParser()
    private let delegateProxy = BLEDelegateProxy()

    // BLE objects
    private nonisolated(unsafe) var centralManager: CBCentralManager!
    private var connectedPeripheral: CBPeripheral?
    private var writeCharacteristic: CBCharacteristic?
    private var notifyCharacteristic: CBCharacteristic?

    // State
    private var _discoveredDevices: [UUID: DiscoveredDevice] = [:]
    private var _connectionState: ConnectionState = .disconnected
    private var _isScanning: Bool = false
    private var _bluetoothState: CBManagerState = .unknown

    // Continuations for one-shot operations
    private var connectionContinuation: CheckedContinuation<Void, Error>?

    // MARK: - CubeProcessor for off-main processing

    /// Processor for BLE data (isolated to @CubeActor)
    public private(set) var processor: CubeProcessor?

    // MARK: - Raw Data Stream (feeds directly to CubeProcessor)

    /// Stream of raw BLE data - consumed by CubeProcessor
    private var rawDataStream: AsyncStream<Data>?
    private var rawDataContinuation: AsyncStream<Data>.Continuation?

    // MARK: - AsyncStreams for streaming events (using makeStream for iOS 17+)

    /// Stream of discovered devices (updated on each discovery)
    public let discoveries: AsyncStream<[DiscoveredDevice]>
    private let discoveriesContinuation: AsyncStream<[DiscoveredDevice]>.Continuation

    /// Stream of connection state changes
    public let connectionStateChanges: AsyncStream<ConnectionState>
    private let connectionStateContinuation: AsyncStream<ConnectionState>.Continuation

    /// Stream of Bluetooth state changes
    public let bluetoothStateChanges: AsyncStream<CBManagerState>
    private let bluetoothStateContinuation: AsyncStream<CBManagerState>.Continuation

    // MARK: - Initialization

    public init() {
        // Initialize AsyncStreams using makeStream (iOS 17+ cleaner syntax)
        (discoveries, discoveriesContinuation) = AsyncStream.makeStream(of: [DiscoveredDevice].self)
        (connectionStateChanges, connectionStateContinuation) = AsyncStream.makeStream(of: ConnectionState.self)
        (bluetoothStateChanges, bluetoothStateContinuation) = AsyncStream.makeStream(of: CBManagerState.self)

        // Setup delegate proxy and central manager
        delegateProxy.communicator = self
        centralManager = CBCentralManager(delegate: delegateProxy, queue: nil)
    }

    deinit {
        discoveriesContinuation.finish()
        connectionStateContinuation.finish()
        bluetoothStateContinuation.finish()
        rawDataContinuation?.finish()
    }

    // MARK: - Public Accessors

    public var bluetoothState: CBManagerState {
        _bluetoothState
    }

    public var isBluetoothReady: Bool {
        _bluetoothState == .poweredOn
    }

    public var connectionState: ConnectionState {
        _connectionState
    }

    public var discoveredDevices: [DiscoveredDevice] {
        Array(_discoveredDevices.values)
    }

    public var isScanning: Bool {
        _isScanning
    }

    // MARK: - Public API

    public func startScanning() {
        guard _bluetoothState == .poweredOn else {
            logger.warning("Cannot scan: Bluetooth not powered on")
            return
        }

        guard !_isScanning else { return }

        _isScanning = true
        _discoveredDevices.removeAll()

        centralManager.scanForPeripherals(
            withServices: [GoCubeBLE.serviceUUID],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
        )
    }

    public func stopScanning() {
        guard _isScanning else { return }
        _isScanning = false
        centralManager.stopScan()
    }

    /// Connect to a device (one-shot with continuation)
    public func connect(to device: DiscoveredDevice) async throws(GoCubeError) {
        guard _bluetoothState == .poweredOn else {
            throw .bluetoothPoweredOff
        }

        // Cancel any pending connection attempt
        if connectionContinuation != nil {
            resumeConnection(with: .failure(GoCubeError.connectionFailed("Connection cancelled")))
        }

        stopScanning()
        setConnectionState(.connecting)

        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                self.connectionContinuation = continuation
                self.centralManager.connect(device.peripheral, options: nil)
            }
        } catch let error as GoCubeError {
            throw error
        } catch {
            throw .connectionFailed(error.localizedDescription)
        }
    }

    public func disconnect() {
        guard let peripheral = connectedPeripheral else { return }
        setConnectionState(.disconnecting)
        centralManager.cancelPeripheralConnection(peripheral)
    }

    public func sendCommand(_ command: GoCubeCommand) throws(GoCubeError) {
        try write(data: messageParser.buildCommandFrame(command))
    }

    public func write(data: Data) throws(GoCubeError) {
        guard let peripheral = connectedPeripheral,
              let characteristic = writeCharacteristic
        else {
            throw .notConnected
        }
        peripheral.writeValue(data, for: characteristic, type: .withoutResponse)
    }

    public func clearBuffer() async {
        await processor?.clearBuffer()
    }

    /// Create and configure the CubeProcessor for processing
    /// Sets up raw data stream that feeds directly to processor
    /// - Parameter smoothingFactor: Quaternion smoothing factor from configuration
    public func createProcessor(smoothingFactor: Double) async {
        // Create raw data stream
        let (stream, continuation) = AsyncStream.makeStream(of: Data.self)
        rawDataStream = stream
        rawDataContinuation = continuation

        // Give continuation to delegate proxy for direct yielding (no Task overhead)
        delegateProxy.rawDataContinuation = continuation

        // Create processor and start it listening to the raw data stream
        let newProcessor = await CubeProcessor(smoothingFactor: smoothingFactor)
        processor = newProcessor
        await newProcessor.startListening(to: stream)
    }

    /// Destroy the CubeProcessor when disconnecting
    public func destroyProcessor() {
        // Finish the stream to stop processor's listening task
        rawDataContinuation?.finish()
        delegateProxy.rawDataContinuation = nil
        rawDataContinuation = nil
        rawDataStream = nil
        processor = nil
    }

    // MARK: - Delegate Handlers (called from proxy via MainActor)

    func handleBluetoothStateUpdate(_ state: CBManagerState) {
        _bluetoothState = state
        bluetoothStateContinuation.yield(state)

        switch state {
        case .poweredOff:
            setConnectionState(.disconnected)
            // Resume any pending connection continuation
            if connectionContinuation != nil {
                resumeConnection(with: .failure(GoCubeError.bluetoothPoweredOff))
            }
        default:
            break
        }
    }

    func handleDiscovery(_ device: DiscoveredDevice) {
        _discoveredDevices[device.id] = device
        discoveriesContinuation.yield(Array(_discoveredDevices.values))
    }

    func handleDidConnect(_ peripheral: CBPeripheral) {
        connectedPeripheral = peripheral
        peripheral.delegate = delegateProxy
        peripheral.discoverServices([GoCubeBLE.serviceUUID])
    }

    func handleDidFailToConnect(_ error: Error?) {
        setConnectionState(.disconnected)
        resumeConnection(with: .failure(GoCubeError.connectionFailed(error?.localizedDescription ?? "Unknown")))
    }

    func handleDidDisconnect(_: Error?) {
        connectedPeripheral = nil
        writeCharacteristic = nil
        notifyCharacteristic = nil
        setConnectionState(.disconnected)

        // If we were in the middle of connecting, fail the continuation
        if connectionContinuation != nil {
            resumeConnection(with: .failure(GoCubeError.connection(.disconnected)))
        }
    }

    func handleDidDiscoverServices(_ peripheral: CBPeripheral, error: Error?) {
        if let error = error {
            resumeConnection(with: .failure(GoCubeError.connectionFailed(error.localizedDescription)))
            return
        }

        guard let service = peripheral.services?.first(where: { $0.uuid == GoCubeBLE.serviceUUID }) else {
            resumeConnection(with: .failure(GoCubeError.connection(.serviceNotFound)))
            return
        }

        peripheral.discoverCharacteristics(
            [GoCubeBLE.writeCharacteristicUUID, GoCubeBLE.notifyCharacteristicUUID],
            for: service
        )
    }

    func handleDidDiscoverCharacteristics(_ service: CBService, error: Error?) {
        if let error = error {
            resumeConnection(with: .failure(GoCubeError.connectionFailed(error.localizedDescription)))
            return
        }

        guard let characteristics = service.characteristics else {
            resumeConnection(with: .failure(GoCubeError.connection(.characteristicNotFound)))
            return
        }

        for characteristic in characteristics {
            if characteristic.uuid == GoCubeBLE.writeCharacteristicUUID {
                writeCharacteristic = characteristic
            } else if characteristic.uuid == GoCubeBLE.notifyCharacteristicUUID {
                notifyCharacteristic = characteristic
                connectedPeripheral?.setNotifyValue(true, for: characteristic)
            }
        }

        guard writeCharacteristic != nil, notifyCharacteristic != nil else {
            resumeConnection(with: .failure(GoCubeError.connection(.characteristicNotFound)))
            return
        }

        setConnectionState(.connected)
        resumeConnection(with: .success(()))
    }

    func handleNotificationStateError(_ error: Error) {
        logger.error("Notification state error: \(error.localizedDescription)")
    }

    // MARK: - Private Helpers

    private func setConnectionState(_ state: ConnectionState) {
        _connectionState = state
        connectionStateContinuation.yield(state)
    }

    private func resumeConnection(with result: Result<Void, Error>) {
        let continuation = connectionContinuation
        connectionContinuation = nil

        switch result {
        case .success:
            continuation?.resume()
        case let .failure(error):
            continuation?.resume(throwing: error)
        }
    }
}
