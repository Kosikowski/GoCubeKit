import Foundation

/// Delegate protocol for receiving GoCube events
public protocol GoCubeDelegate: AnyObject {
    /// Called when a move is detected on the cube
    func goCube(_ cube: GoCube, didReceiveMove move: Move)

    /// Called when the cube state is updated
    func goCube(_ cube: GoCube, didUpdateState state: CubeState)

    /// Called when the cube orientation is updated (~15 Hz when enabled)
    func goCube(_ cube: GoCube, didUpdateOrientation quaternion: Quaternion)

    /// Called when the battery level is received
    func goCube(_ cube: GoCube, didUpdateBattery level: Int)

    /// Called when the cube type is received
    func goCube(_ cube: GoCube, didReceiveCubeType type: GoCubeType)

    /// Called when the cube is disconnected
    func goCubeDidDisconnect(_ cube: GoCube)

    /// Called when the cube is successfully connected
    func goCubeDidConnect(_ cube: GoCube)

    /// Called when an error occurs
    func goCube(_ cube: GoCube, didEncounterError error: GoCubeError)
}

// MARK: - Default Implementations

public extension GoCubeDelegate {
    func goCube(_ cube: GoCube, didReceiveMove move: Move) {}
    func goCube(_ cube: GoCube, didUpdateState state: CubeState) {}
    func goCube(_ cube: GoCube, didUpdateOrientation quaternion: Quaternion) {}
    func goCube(_ cube: GoCube, didUpdateBattery level: Int) {}
    func goCube(_ cube: GoCube, didReceiveCubeType type: GoCubeType) {}
    func goCubeDidDisconnect(_ cube: GoCube) {}
    func goCubeDidConnect(_ cube: GoCube) {}
    func goCube(_ cube: GoCube, didEncounterError error: GoCubeError) {}
}
