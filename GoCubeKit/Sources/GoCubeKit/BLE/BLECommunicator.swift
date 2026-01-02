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

/// Low-level BLE communication handler
/// Note: This class uses locks for thread safety because CoreBluetooth
/// callbacks arrive on arbitrary threads. Messages are dispatched to
/// CubeActor for processing.
public final class BLECommunicator: NSObject, Sendable {

    // MARK: - Properties

    private let logger = Logger(subsystem: "com.gocubekit", category: "BLE")
    private let messageParser = MessageParser()
    private let lock = NSLock()

    // BLE objects (protected by lock, accessed from BLE callbacks)
    private nonisolated(unsafe) var centralManager: CBCentralManager!
    private nonisolated(unsafe) var connectedPeripheral: CBPeripheral?
    private nonisolated(unsafe) var writeCharacteristic: CBCharacteristic?
    private nonisolated(unsafe) var notifyCharacteristic: CBCharacteristic?

    // State (protected by lock)
    private nonisolated(unsafe) var _discoveredDevices: [UUID: DiscoveredDevice] = [:]
    private nonisolated(unsafe) var _connectionState: ConnectionState = .disconnected
    private nonisolated(unsafe) var _isScanning: Bool = false
    private nonisolated(unsafe) var _messageBuffer: [UInt8] = []
    private nonisolated(unsafe) var connectionContinuation: CheckedContinuation<Void, Error>?

    // MARK: - Callbacks

    /// Called on MainActor when devices are discovered
    public nonisolated(unsafe) var onDevicesDiscovered: (@Sendable @MainActor ([DiscoveredDevice]) -> Void)?

    /// Called on MainActor when connection state changes
    public nonisolated(unsafe) var onConnectionStateChanged: (@Sendable @MainActor (ConnectionState) -> Void)?

    /// Called on CubeActor when a message is received
    public nonisolated(unsafe) var onMessageReceived: (@Sendable @CubeActor (GoCubeMessage) -> Void)?

    /// Called on MainActor when Bluetooth state changes
    public nonisolated(unsafe) var onBluetoothStateChanged: (@Sendable @MainActor (CBManagerState) -> Void)?

    /// Called on MainActor when an error occurs
    public nonisolated(unsafe) var onError: (@Sendable @MainActor (GoCubeError) -> Void)?

    // MARK: - Initialization

    public override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }

    // MARK: - Thread-safe accessors

    public var bluetoothState: CBManagerState {
        centralManager.state
    }

    public var isBluetoothReady: Bool {
        centralManager.state == .poweredOn
    }

    public var connectionState: ConnectionState {
        lock.lock()
        defer { lock.unlock() }
        return _connectionState
    }

    public var discoveredDevices: [DiscoveredDevice] {
        lock.lock()
        defer { lock.unlock() }
        return Array(_discoveredDevices.values)
    }

    public var isScanning: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _isScanning
    }

    // MARK: - Public API

    public func startScanning() {
        guard centralManager.state == .poweredOn else {
            Task { @MainActor in onError?(.bluetoothPoweredOff) }
            return
        }

        lock.lock()
        guard !_isScanning else {
            lock.unlock()
            return
        }
        _isScanning = true
        _discoveredDevices.removeAll()
        lock.unlock()

        centralManager.scanForPeripherals(
            withServices: [GoCubeBLE.serviceUUID],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
        )
    }

    public func stopScanning() {
        lock.lock()
        guard _isScanning else {
            lock.unlock()
            return
        }
        _isScanning = false
        lock.unlock()

        centralManager.stopScan()
    }

    public func connect(to device: DiscoveredDevice) async throws {
        guard centralManager.state == .poweredOn else {
            throw GoCubeError.bluetoothPoweredOff
        }

        stopScanning()

        lock.lock()
        _connectionState = .connecting
        lock.unlock()

        Task { @MainActor in onConnectionStateChanged?(.connecting) }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            lock.lock()
            self.connectionContinuation = continuation
            lock.unlock()
            self.centralManager.connect(device.peripheral, options: nil)
        }
    }

    public func disconnect() {
        guard let peripheral = connectedPeripheral else { return }

        lock.lock()
        _connectionState = .disconnecting
        lock.unlock()

        Task { @MainActor in onConnectionStateChanged?(.disconnecting) }
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
        lock.lock()
        _messageBuffer.removeAll()
        lock.unlock()
    }

    // MARK: - Message Buffer (called from BLE callback thread)

    private func appendToBuffer(_ data: Data) {
        lock.lock()
        _messageBuffer.append(contentsOf: data)

        // Extract and process messages while holding lock
        while let messageData = extractOneMessageLocked() {
            lock.unlock()
            do {
                let message = try messageParser.parse(messageData)
                Task { @CubeActor in self.onMessageReceived?(message) }
            } catch {
                logger.error("Failed to parse message: \(error.localizedDescription)")
            }
            lock.lock()
        }
        lock.unlock()
    }

    /// Must be called with lock held
    private func extractOneMessageLocked() -> Data? {
        guard let startIndex = _messageBuffer.firstIndex(of: GoCubeFrame.prefix) else {
            _messageBuffer.removeAll()
            return nil
        }

        if startIndex > 0 {
            _messageBuffer.removeFirst(startIndex)
        }

        guard _messageBuffer.count >= GoCubeFrame.minimumLength else {
            return nil
        }

        let declaredLength = Int(_messageBuffer[GoCubeFrame.lengthOffset])
        let expectedTotalLength = 1 + 1 + declaredLength + 1 + 2

        guard _messageBuffer.count >= expectedTotalLength else {
            return nil
        }

        let suffixStart = expectedTotalLength - 2
        guard _messageBuffer[suffixStart] == GoCubeFrame.suffix[0] &&
              _messageBuffer[suffixStart + 1] == GoCubeFrame.suffix[1] else {
            _messageBuffer.removeFirst()
            return extractOneMessageLocked()
        }

        let messageBytes = Array(_messageBuffer.prefix(expectedTotalLength))
        _messageBuffer.removeFirst(expectedTotalLength)
        return Data(messageBytes)
    }

    // MARK: - State updates (called from BLE callbacks)

    private func setConnectionState(_ state: ConnectionState) {
        lock.lock()
        _connectionState = state
        lock.unlock()
        Task { @MainActor in onConnectionStateChanged?(state) }
    }

    private func resumeContinuation(with result: Result<Void, Error>) {
        lock.lock()
        let continuation = connectionContinuation
        connectionContinuation = nil
        lock.unlock()

        switch result {
        case .success:
            continuation?.resume()
        case .failure(let error):
            continuation?.resume(throwing: error)
        }
    }
}

// MARK: - CBCentralManagerDelegate

extension BLECommunicator: CBCentralManagerDelegate {

    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor in onBluetoothStateChanged?(central.state) }

        switch central.state {
        case .poweredOff:
            setConnectionState(.disconnected)
            Task { @MainActor in onError?(.bluetoothPoweredOff) }
        case .unauthorized:
            Task { @MainActor in onError?(.bluetoothUnauthorized) }
        case .unsupported:
            Task { @MainActor in onError?(.bluetoothUnavailable) }
        default:
            break
        }
    }

    public func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let device = DiscoveredDevice(peripheral: peripheral, rssi: RSSI.intValue)

        lock.lock()
        _discoveredDevices[device.id] = device
        let devices = Array(_discoveredDevices.values)
        lock.unlock()

        Task { @MainActor in onDevicesDiscovered?(devices) }
    }

    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        connectedPeripheral = peripheral
        peripheral.delegate = self
        peripheral.discoverServices([GoCubeBLE.serviceUUID])
    }

    public func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        setConnectionState(.disconnected)
        resumeContinuation(with: .failure(GoCubeError.connectionFailed(error?.localizedDescription ?? "Unknown")))
    }

    public func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        connectedPeripheral = nil
        writeCharacteristic = nil
        notifyCharacteristic = nil
        setConnectionState(.disconnected)

        lock.lock()
        let hasContinuation = connectionContinuation != nil
        lock.unlock()

        if hasContinuation {
            resumeContinuation(with: .failure(GoCubeError.connection(.disconnected)))
        }
    }
}

// MARK: - CBPeripheralDelegate

extension BLECommunicator: CBPeripheralDelegate {

    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error = error {
            resumeContinuation(with: .failure(GoCubeError.connectionFailed(error.localizedDescription)))
            return
        }

        guard let service = peripheral.services?.first(where: { $0.uuid == GoCubeBLE.serviceUUID }) else {
            resumeContinuation(with: .failure(GoCubeError.connection(.serviceNotFound)))
            return
        }

        peripheral.discoverCharacteristics(
            [GoCubeBLE.writeCharacteristicUUID, GoCubeBLE.notifyCharacteristicUUID],
            for: service
        )
    }

    public func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        if let error = error {
            resumeContinuation(with: .failure(GoCubeError.connectionFailed(error.localizedDescription)))
            return
        }

        guard let characteristics = service.characteristics else {
            resumeContinuation(with: .failure(GoCubeError.connection(.characteristicNotFound)))
            return
        }

        for characteristic in characteristics {
            if characteristic.uuid == GoCubeBLE.writeCharacteristicUUID {
                writeCharacteristic = characteristic
            } else if characteristic.uuid == GoCubeBLE.notifyCharacteristicUUID {
                notifyCharacteristic = characteristic
                peripheral.setNotifyValue(true, for: characteristic)
            }
        }

        guard writeCharacteristic != nil && notifyCharacteristic != nil else {
            resumeContinuation(with: .failure(GoCubeError.connection(.characteristicNotFound)))
            return
        }

        setConnectionState(.connected)
        resumeContinuation(with: .success(()))
    }

    public func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard error == nil,
              characteristic.uuid == GoCubeBLE.notifyCharacteristicUUID,
              let data = characteristic.value else { return }

        appendToBuffer(data)
    }

    public func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateNotificationStateFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        if let error = error {
            logger.error("Notification state error: \(error.localizedDescription)")
        }
    }
}
