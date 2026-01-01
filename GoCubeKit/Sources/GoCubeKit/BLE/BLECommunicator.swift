@preconcurrency import CoreBluetooth
import Foundation
import Combine

/// Errors that can occur during BLE communication
public enum BLEError: Error, Equatable {
    case bluetoothUnavailable
    case bluetoothUnauthorized
    case bluetoothPoweredOff
    case deviceNotFound
    case connectionFailed(String)
    case disconnected
    case serviceNotFound
    case characteristicNotFound
    case writeFailure(String)
    case notConnected
    case timeout
}

/// Represents a discovered GoCube device
public struct DiscoveredDevice: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let name: String
    public let rssi: Int
    public let peripheral: CBPeripheral

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
public class BLECommunicator: NSObject, @unchecked Sendable {

    // MARK: - Properties

    private var centralManager: CBCentralManager!
    private var connectedPeripheral: CBPeripheral?
    private var writeCharacteristic: CBCharacteristic?
    private var notifyCharacteristic: CBCharacteristic?

    private let messageBuffer = MessageBuffer()
    private let messageParser = MessageParser()

    // MARK: - Publishers

    private let _discoveredDevicesSubject = CurrentValueSubject<[DiscoveredDevice], Never>([])
    public var discoveredDevicesPublisher: AnyPublisher<[DiscoveredDevice], Never> {
        _discoveredDevicesSubject.eraseToAnyPublisher()
    }

    private let _connectionStateSubject = CurrentValueSubject<ConnectionState, Never>(.disconnected)
    public var connectionStatePublisher: AnyPublisher<ConnectionState, Never> {
        _connectionStateSubject.eraseToAnyPublisher()
    }

    private let _receivedMessageSubject = PassthroughSubject<GoCubeMessage, Never>()
    public var receivedMessagePublisher: AnyPublisher<GoCubeMessage, Never> {
        _receivedMessageSubject.eraseToAnyPublisher()
    }

    private let _bluetoothStateSubject = CurrentValueSubject<CBManagerState, Never>(.unknown)
    public var bluetoothStatePublisher: AnyPublisher<CBManagerState, Never> {
        _bluetoothStateSubject.eraseToAnyPublisher()
    }

    private let _errorSubject = PassthroughSubject<BLEError, Never>()
    public var errorPublisher: AnyPublisher<BLEError, Never> {
        _errorSubject.eraseToAnyPublisher()
    }

    // MARK: - State

    private var discoveredDevices: [UUID: DiscoveredDevice] = [:]
    private var connectionContinuation: CheckedContinuation<Void, Error>?
    private var isScanning = false

    // MARK: - Initialization

    public override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: DispatchQueue(label: "com.gocubekit.ble"))
    }

    // MARK: - Public API

    /// Current Bluetooth state
    public var bluetoothState: CBManagerState {
        centralManager.state
    }

    /// Current connection state
    public var connectionState: ConnectionState {
        _connectionStateSubject.value
    }

    /// Whether Bluetooth is ready for scanning
    public var isBluetoothReady: Bool {
        centralManager.state == .poweredOn
    }

    /// Start scanning for GoCube devices
    public func startScanning() {
        guard centralManager.state == .poweredOn else {
            _errorSubject.send(.bluetoothPoweredOff)
            return
        }

        guard !isScanning else { return }

        isScanning = true
        discoveredDevices.removeAll()
        _discoveredDevicesSubject.send([])

        centralManager.scanForPeripherals(
            withServices: [GoCubeBLE.serviceUUID],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
        )
    }

    /// Stop scanning for devices
    public func stopScanning() {
        guard isScanning else { return }
        isScanning = false
        centralManager.stopScan()
    }

    /// Connect to a discovered device
    public func connect(to device: DiscoveredDevice) async throws {
        guard centralManager.state == .poweredOn else {
            throw BLEError.bluetoothPoweredOff
        }

        stopScanning()

        _connectionStateSubject.send(.connecting)

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.connectionContinuation = continuation
            self.centralManager.connect(device.peripheral, options: nil)
        }
    }

    /// Disconnect from the current device
    public func disconnect() {
        guard let peripheral = connectedPeripheral else { return }

        _connectionStateSubject.send(.disconnecting)
        centralManager.cancelPeripheralConnection(peripheral)
    }

    /// Send a command to the connected cube
    public func sendCommand(_ command: GoCubeCommand) throws {
        let data = messageParser.buildCommandFrame(command)
        try write(data: data)
    }

    /// Write raw data to the cube
    public func write(data: Data) throws {
        guard let peripheral = connectedPeripheral,
              let characteristic = writeCharacteristic else {
            throw BLEError.notConnected
        }

        peripheral.writeValue(data, for: characteristic, type: .withoutResponse)
    }

    /// Clear the message buffer
    public func clearBuffer() {
        messageBuffer.clear()
    }
}

// MARK: - CBCentralManagerDelegate

extension BLECommunicator: CBCentralManagerDelegate {

    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        _bluetoothStateSubject.send(central.state)

        switch central.state {
        case .poweredOff:
            _connectionStateSubject.send(.disconnected)
            _errorSubject.send(.bluetoothPoweredOff)
        case .unauthorized:
            _errorSubject.send(.bluetoothUnauthorized)
        case .unsupported:
            _errorSubject.send(.bluetoothUnavailable)
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
        discoveredDevices[peripheral.identifier] = device
        _discoveredDevicesSubject.send(Array(discoveredDevices.values))
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
        _connectionStateSubject.send(.disconnected)
        connectionContinuation?.resume(throwing: BLEError.connectionFailed(error?.localizedDescription ?? "Unknown error"))
        connectionContinuation = nil
    }

    public func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        connectedPeripheral = nil
        writeCharacteristic = nil
        notifyCharacteristic = nil
        _connectionStateSubject.send(.disconnected)

        if connectionContinuation != nil {
            connectionContinuation?.resume(throwing: BLEError.disconnected)
            connectionContinuation = nil
        }
    }
}

// MARK: - CBPeripheralDelegate

extension BLECommunicator: CBPeripheralDelegate {

    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error = error {
            connectionContinuation?.resume(throwing: BLEError.connectionFailed(error.localizedDescription))
            connectionContinuation = nil
            return
        }

        guard let service = peripheral.services?.first(where: { $0.uuid == GoCubeBLE.serviceUUID }) else {
            connectionContinuation?.resume(throwing: BLEError.serviceNotFound)
            connectionContinuation = nil
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
            connectionContinuation?.resume(throwing: BLEError.connectionFailed(error.localizedDescription))
            connectionContinuation = nil
            return
        }

        guard let characteristics = service.characteristics else {
            connectionContinuation?.resume(throwing: BLEError.characteristicNotFound)
            connectionContinuation = nil
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

        // Verify we found both characteristics
        guard writeCharacteristic != nil && notifyCharacteristic != nil else {
            connectionContinuation?.resume(throwing: BLEError.characteristicNotFound)
            connectionContinuation = nil
            return
        }

        // Connection complete
        _connectionStateSubject.send(.connected)
        connectionContinuation?.resume()
        connectionContinuation = nil
    }

    public func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard error == nil,
              characteristic.uuid == GoCubeBLE.notifyCharacteristicUUID,
              let data = characteristic.value else {
            return
        }

        // Add to buffer and process complete messages
        let completeMessages = messageBuffer.append(data)

        for messageData in completeMessages {
            do {
                let message = try messageParser.parse(messageData)
                _receivedMessageSubject.send(message)
            } catch {
                // Log parsing errors but don't crash
                print("GoCubeKit: Failed to parse message: \(error)")
            }
        }
    }

    public func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateNotificationStateFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        if let error = error {
            print("GoCubeKit: Notification state error: \(error)")
        }
    }
}
