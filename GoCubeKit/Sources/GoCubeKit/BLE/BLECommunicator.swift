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
        self.id = peripheral.identifier
        self.name = peripheral.name ?? "Unknown GoCube"
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
/// and forwards them to the actor-isolated BLECommunicator
private final class BLEDelegateProxy: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate, @unchecked Sendable {

    weak var communicator: BLECommunicator?

    // MARK: - CBCentralManagerDelegate

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { await communicator?.handleBluetoothStateUpdate(central.state) }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let device = DiscoveredDevice(peripheral: peripheral, rssi: RSSI.intValue)
        Task { await communicator?.handleDiscovery(device) }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Task { await communicator?.handleDidConnect(peripheral) }
    }

    func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        Task { await communicator?.handleDidFailToConnect(error) }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        Task { await communicator?.handleDidDisconnect(error) }
    }

    // MARK: - CBPeripheralDelegate

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        Task { await communicator?.handleDidDiscoverServices(peripheral, error: error) }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        Task { await communicator?.handleDidDiscoverCharacteristics(service, error: error) }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard error == nil,
              characteristic.uuid == GoCubeBLE.notifyCharacteristicUUID,
              let data = characteristic.value else { return }
        Task { await communicator?.handleDidReceiveData(data) }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateNotificationStateFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        if let error = error {
            Task { await communicator?.handleNotificationStateError(error) }
        }
    }
}

// MARK: - BLECommunicator

/// Low-level BLE communication handler
/// Isolated to CubeActor for thread-safe state management
@CubeActor
public final class BLECommunicator {

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
    private var messageBuffer: [UInt8] = []

    // Continuations for one-shot operations
    private var connectionContinuation: CheckedContinuation<Void, Error>?

    // MARK: - AsyncStreams for streaming events

    /// Stream of discovered devices (updated on each discovery)
    public let discoveries: AsyncStream<[DiscoveredDevice]>
    private let discoveriesContinuation: AsyncStream<[DiscoveredDevice]>.Continuation

    /// Stream of parsed messages from the cube
    public let messages: AsyncStream<GoCubeMessage>
    private let messagesContinuation: AsyncStream<GoCubeMessage>.Continuation

    /// Stream of connection state changes
    public let connectionStateChanges: AsyncStream<ConnectionState>
    private let connectionStateContinuation: AsyncStream<ConnectionState>.Continuation

    /// Stream of Bluetooth state changes
    public let bluetoothStateChanges: AsyncStream<CBManagerState>
    private let bluetoothStateContinuation: AsyncStream<CBManagerState>.Continuation

    // MARK: - Initialization

    public init() {
        // Initialize AsyncStreams
        var discCont: AsyncStream<[DiscoveredDevice]>.Continuation!
        discoveries = AsyncStream { discCont = $0 }
        discoveriesContinuation = discCont

        var msgCont: AsyncStream<GoCubeMessage>.Continuation!
        messages = AsyncStream { msgCont = $0 }
        messagesContinuation = msgCont

        var connCont: AsyncStream<ConnectionState>.Continuation!
        connectionStateChanges = AsyncStream { connCont = $0 }
        connectionStateContinuation = connCont

        var btCont: AsyncStream<CBManagerState>.Continuation!
        bluetoothStateChanges = AsyncStream { btCont = $0 }
        bluetoothStateContinuation = btCont

        // Setup delegate proxy and central manager
        delegateProxy.communicator = self
        centralManager = CBCentralManager(delegate: delegateProxy, queue: nil)
    }

    deinit {
        discoveriesContinuation.finish()
        messagesContinuation.finish()
        connectionStateContinuation.finish()
        bluetoothStateContinuation.finish()
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
    public func connect(to device: DiscoveredDevice) async throws {
        guard _bluetoothState == .poweredOn else {
            throw GoCubeError.bluetoothPoweredOff
        }

        stopScanning()
        setConnectionState(.connecting)

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.connectionContinuation = continuation
            self.centralManager.connect(device.peripheral, options: nil)
        }
    }

    public func disconnect() {
        guard let peripheral = connectedPeripheral else { return }
        setConnectionState(.disconnecting)
        centralManager.cancelPeripheralConnection(peripheral)
    }

    public func sendCommand(_ command: GoCubeCommand) throws {
        try write(data: messageParser.buildCommandFrame(command))
    }

    public func write(data: Data) throws {
        guard let peripheral = connectedPeripheral,
              let characteristic = writeCharacteristic else {
            throw GoCubeError.notConnected
        }
        peripheral.writeValue(data, for: characteristic, type: .withoutResponse)
    }

    public func clearBuffer() {
        messageBuffer.removeAll()
    }

    // MARK: - Delegate Handlers (called from proxy)

    func handleBluetoothStateUpdate(_ state: CBManagerState) {
        _bluetoothState = state
        bluetoothStateContinuation.yield(state)

        switch state {
        case .poweredOff:
            setConnectionState(.disconnected)
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

    func handleDidDisconnect(_ error: Error?) {
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

        guard writeCharacteristic != nil && notifyCharacteristic != nil else {
            resumeConnection(with: .failure(GoCubeError.connection(.characteristicNotFound)))
            return
        }

        setConnectionState(.connected)
        resumeConnection(with: .success(()))
    }

    func handleDidReceiveData(_ data: Data) {
        messageBuffer.append(contentsOf: data)

        // Extract and process complete messages
        while let messageData = extractOneMessage() {
            do {
                let message = try messageParser.parse(messageData)
                messagesContinuation.yield(message)
            } catch {
                logger.error("Failed to parse message: \(error.localizedDescription)")
            }
        }
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
        case .failure(let error):
            continuation?.resume(throwing: error)
        }
    }

    private func extractOneMessage() -> Data? {
        guard let startIndex = messageBuffer.firstIndex(of: GoCubeFrame.prefix) else {
            messageBuffer.removeAll()
            return nil
        }

        if startIndex > 0 {
            messageBuffer.removeFirst(startIndex)
        }

        guard messageBuffer.count >= GoCubeFrame.minimumLength else {
            return nil
        }

        let declaredLength = Int(messageBuffer[GoCubeFrame.lengthOffset])
        let expectedTotalLength = 1 + 1 + declaredLength + 1 + 2

        guard messageBuffer.count >= expectedTotalLength else {
            return nil
        }

        let suffixStart = expectedTotalLength - 2
        guard messageBuffer[suffixStart] == GoCubeFrame.suffix[0] &&
              messageBuffer[suffixStart + 1] == GoCubeFrame.suffix[1] else {
            messageBuffer.removeFirst()
            return extractOneMessage()
        }

        let messageBytes = Array(messageBuffer.prefix(expectedTotalLength))
        messageBuffer.removeFirst(expectedTotalLength)
        return Data(messageBytes)
    }
}
