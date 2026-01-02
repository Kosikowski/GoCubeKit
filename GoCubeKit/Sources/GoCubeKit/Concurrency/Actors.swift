import Foundation

/// Global actor for cube state and logic
/// GoCube and GoCubeManager operations are isolated to this actor
@globalActor
public actor CubeActor {
    public static let shared = CubeActor()
}
