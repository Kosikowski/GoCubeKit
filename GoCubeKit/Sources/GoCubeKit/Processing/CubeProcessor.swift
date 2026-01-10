import Foundation
import os.log

/// Processes raw BLE data from GoCube devices
/// Isolated to CubeActor - all heavy computation happens off MainActor
@CubeActor
public final class CubeProcessor {

    private let logger = Logger(subsystem: "com.gocubekit", category: "CubeProcessor")

    // MARK: - Decoders (all processing happens here, off MainActor)

    private let messageParser = MessageParser()
    private let moveDecoder = MoveDecoder()
    private let stateDecoder = StateDecoder()
    private let quaternionDecoder = QuaternionDecoder()

    // MARK: - Quaternion Processing

    private let quaternionSmoother: QuaternionSmoother
    private let orientationManager = OrientationManager()

    // MARK: - Message Buffer

    private var messageBuffer: [UInt8] = []

    // MARK: - Output Streams (consumed by MainActor classes)

    /// Stream of decoded moves
    public let processedMoves: AsyncStream<Move>
    private let processedMovesContinuation: AsyncStream<Move>.Continuation

    /// Stream of decoded cube states
    public let processedStates: AsyncStream<CubeState>
    private let processedStatesContinuation: AsyncStream<CubeState>.Continuation

    /// Stream of processed orientations (smoothed + relative)
    public let processedOrientations: AsyncStream<Quaternion>
    private let processedOrientationsContinuation: AsyncStream<Quaternion>.Continuation

    /// Stream of battery levels
    public let processedBattery: AsyncStream<Int>
    private let processedBatteryContinuation: AsyncStream<Int>.Continuation

    /// Stream of cube types
    public let processedCubeType: AsyncStream<GoCubeType>
    private let processedCubeTypeContinuation: AsyncStream<GoCubeType>.Continuation

    // MARK: - Initialization

    public init(smoothingFactor: Double = 0.3) {
        self.quaternionSmoother = QuaternionSmoother(smoothingFactor: smoothingFactor)

        // Initialize output streams
        (processedMoves, processedMovesContinuation) = AsyncStream.makeStream(of: Move.self)
        (processedStates, processedStatesContinuation) = AsyncStream.makeStream(of: CubeState.self)
        (processedOrientations, processedOrientationsContinuation) = AsyncStream.makeStream(of: Quaternion.self)
        (processedBattery, processedBatteryContinuation) = AsyncStream.makeStream(of: Int.self)
        (processedCubeType, processedCubeTypeContinuation) = AsyncStream.makeStream(of: GoCubeType.self)
    }

    deinit {
        rawDataListenerTask?.cancel()
        processedMovesContinuation.finish()
        processedStatesContinuation.finish()
        processedOrientationsContinuation.finish()
        processedBatteryContinuation.finish()
        processedCubeTypeContinuation.finish()
    }

    // MARK: - Raw Data Stream Listener

    /// Task listening to raw BLE data stream
    private var rawDataListenerTask: Task<Void, Never>?

    /// Start listening to raw BLE data stream
    /// - Parameter rawDataStream: Stream of raw BLE data from BLEDelegateProxy
    public func startListening(to rawDataStream: AsyncStream<Data>) {
        rawDataListenerTask = Task { [weak self] in
            for await data in rawDataStream {
                self?.processRawData(data)
            }
        }
    }

    /// Stop listening to the raw data stream
    public func stopListening() {
        rawDataListenerTask?.cancel()
        rawDataListenerTask = nil
    }

    // MARK: - Raw Data Processing

    /// Process raw BLE data - buffers and extracts complete messages
    /// Called directly from BLEDelegateProxy (both on @CubeActor)
    public func processRawData(_ data: Data) {
        messageBuffer.append(contentsOf: data)

        // Extract and process complete messages
        while let messageData = extractOneMessage() {
            do {
                let message = try messageParser.parse(messageData)
                processMessage(message)
            } catch {
                logger.error("Failed to parse message: \(error.localizedDescription)")
            }
        }
    }

    /// Process a parsed message - decode and emit to appropriate stream
    private func processMessage(_ message: GoCubeMessage) {
        switch message.type {
        case .rotation:
            processRotation(message.payload)

        case .cubeState:
            processState(message.payload)

        case .orientation:
            // Orientation processing involves async calls to other actors
            Task {
                await self.processOrientation(message.payload)
            }

        case .battery:
            processBattery(message.payload)

        case .offlineStats:
            processOfflineStats(message.payload)

        case .cubeType:
            processCubeType(message.payload)
        }
    }

    // MARK: - Individual Message Processors

    private func processRotation(_ payload: Data) {
        do {
            let moves = try moveDecoder.decode(payload)
            for move in moves {
                processedMovesContinuation.yield(move)
            }
        } catch {
            logger.error("Failed to decode rotation: \(error.localizedDescription)")
        }
    }

    private func processState(_ payload: Data) {
        do {
            let state = try stateDecoder.decode(payload)
            processedStatesContinuation.yield(state)
        } catch {
            logger.error("Failed to decode state: \(error.localizedDescription)")
        }
    }

    private func processOrientation(_ payload: Data) async {
        do {
            let rawQuaternion = try quaternionDecoder.decode(payload)
            let smoothed = await quaternionSmoother.update(rawQuaternion)
            let relative = await orientationManager.relativeOrientation(smoothed)
            processedOrientationsContinuation.yield(relative)
        } catch {
            logger.error("Failed to decode orientation: \(error.localizedDescription)")
        }
    }

    private func processBattery(_ payload: Data) {
        guard let level = payload.first else { return }
        processedBatteryContinuation.yield(Int(min(level, 100)))
    }

    private func processOfflineStats(_ payload: Data) {
        if let string = String(data: payload, encoding: .utf8) {
            logger.info("Offline stats: \(string)")
        }
    }

    private func processCubeType(_ payload: Data) {
        guard let typeRaw = payload.first else { return }
        processedCubeTypeContinuation.yield(GoCubeType(rawValue: typeRaw))
    }

    // MARK: - Message Buffer Management

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

    public func clearBuffer() {
        messageBuffer.removeAll()
    }

    // MARK: - Orientation Manager Access

    /// Set the current orientation as home
    public func setHomeOrientation() async {
        if let current = await quaternionSmoother.current {
            await orientationManager.setHome(current)
        }
    }

    /// Clear the home orientation
    public func clearHomeOrientation() async {
        await orientationManager.clearHome()
    }

    /// Check if home orientation is set
    public func hasHomeOrientation() async -> Bool {
        await orientationManager.hasHome
    }
}
