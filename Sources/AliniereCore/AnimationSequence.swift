import Foundation

public enum AnimationSequence {
    public static func pingPongIndices(frameCount: Int) -> [Int] {
        guard frameCount > 0 else { return [] }
        guard frameCount > 2 else { return Array(0..<frameCount) }

        let forward = Array(0..<frameCount)
        let backward = Array((1..<(frameCount - 1)).reversed())
        return forward + backward
    }
}
