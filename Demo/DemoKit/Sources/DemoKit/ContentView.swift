import GoCubeKit
import SwiftUI

public struct ContentView: View {
    @State private var manager = GoCubeManager.shared
    @State private var lastMove: String = "—"
    @State private var batteryLevel: Int?
    @State private var debugLogging: Bool = false

    public init() {}

    public var body: some View {
        VStack(spacing: 20) {
            headerSection
            connectionSection
            cubeInfoSection
            Spacer()
        }
        .padding()
        #if os(macOS)
            .frame(minWidth: 400, minHeight: 500)
        #endif
    }

    private var headerSection: some View {
        VStack(spacing: 8) {
            Image(systemName: "cube.fill")
                .font(.system(size: 60))
                .foregroundStyle(.blue)
            Text("GoCubeKit Demo")
                .font(.largeTitle)
                .fontWeight(.bold)

            Toggle("Debug Logging", isOn: $debugLogging)
                .toggleStyle(.switch)
                .onChange(of: debugLogging) { _, newValue in
                    GoCubeLogger.isEnabled = newValue
                }
        }
    }

    private var connectionSection: some View {
        VStack(spacing: 12) {
            if manager.connectedCube != nil {
                Label("Connected", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.headline)

                Button("Disconnect") {
                    manager.disconnect()
                }
                .buttonStyle(.bordered)
            } else {
                if manager.isScanning {
                    ProgressView()
                        .padding(.bottom, 4)
                    Text("Scanning...")
                        .foregroundStyle(.secondary)

                    Button("Stop Scanning") {
                        manager.stopScanning()
                    }
                    .buttonStyle(.bordered)
                } else {
                    Button("Scan for GoCube") {
                        manager.startListening()
                        manager.startScanning()
                    }
                    .buttonStyle(.borderedProminent)
                }

                if !manager.discoveredDevices.isEmpty {
                    devicesListSection
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var devicesListSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Discovered Devices")
                .font(.headline)

            ForEach(manager.discoveredDevices) { device in
                Button {
                    Task {
                        do {
                            let cube = try await manager.connect(to: device)
                            startListeningToMoves(cube)
                            await fetchBattery(cube)
                        } catch {
                            print("Connection failed: \(error)")
                        }
                    }
                } label: {
                    HStack {
                        Image(systemName: "cube")
                        Text(device.name)
                        Spacer()
                        Text("\(device.rssi) dBm")
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var cubeInfoSection: some View {
        Group {
            if let cube = manager.connectedCube {
                VStack(spacing: 16) {
                    InfoRow(title: "Name", value: cube.name)
                    InfoRow(title: "Last Move", value: lastMove)

                    if let battery = batteryLevel {
                        InfoRow(title: "Battery", value: "\(battery)%")
                    }

                    HStack(spacing: 12) {
                        Button("Get Battery") {
                            Task { await fetchBattery(cube) }
                        }

                        Button("Flash LEDs") {
                            try? cube.flashLEDs()
                        }
                    }
                    .buttonStyle(.bordered)
                }
                .padding()
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private func startListeningToMoves(_ cube: GoCube) {
        Task {
            for await move in cube.moves {
                await MainActor.run {
                    lastMove = move.notation
                }
            }
        }
    }

    private func fetchBattery(_ cube: GoCube) async {
        do {
            let level = try await cube.getBattery()
            await MainActor.run {
                batteryLevel = level
            }
        } catch {
            print("Failed to get battery: \(error)")
        }
    }
}

struct InfoRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
        }
    }
}

#Preview {
    ContentView()
}
