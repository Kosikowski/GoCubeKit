/// GoCubeKit - A Swift library for communicating with GoCube smart Rubik's cubes
///
/// # Overview
/// GoCubeKit provides a clean, modern Swift API for connecting to and interacting with
/// GoCube Bluetooth-enabled smart cubes. It supports both iOS and macOS platforms.
///
/// # Features
/// - Device discovery and connection via BLE
/// - Real-time move tracking
/// - Cube state synchronization
/// - 3D orientation tracking (quaternion)
/// - LED control
/// - Battery monitoring
///
/// # Quick Start
/// ```swift
/// import GoCubeKit
///
/// // Start scanning for cubes
/// let manager = GoCubeManager.shared
/// manager.startScanning()
///
/// // Connect to a discovered cube
/// let cube = try await manager.connect(to: discoveredDevice)
///
/// // Subscribe to moves
/// cube.movesPublisher
///     .sink { move in
///         print("Move: \(move)")
///     }
///
/// // Get battery level
/// let battery = try await cube.getBattery()
/// ```
///
/// # Protocol Reference
/// This library implements the GoCube BLE protocol as documented at:
/// https://github.com/oddpetersson/gocube-protocol

// MARK: - Public API Exports

// Models
@_exported import struct Foundation.Data
@_exported import struct Foundation.UUID

// Re-export all public types

/// The version of GoCubeKit
public let GoCubeKitVersion = "1.0.0"
