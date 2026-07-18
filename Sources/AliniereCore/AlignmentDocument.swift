import CoreGraphics
import Foundation

public enum CropPolicy: Equatable, Sendable {
    case commonArea
    case manual
}

public enum AlignmentMode: Equatable, Sendable {
    case automaticPatch
    case manualPoints
}

public struct ImageFrame: Identifiable, Equatable, Sendable {
    public let id: UUID
    public var sourceURL: URL
    public var pixelSize: CGSize
    public var delay: TimeInterval

    public init(
        id: UUID = UUID(),
        sourceURL: URL,
        pixelSize: CGSize,
        delay: TimeInterval = 0.12
    ) {
        self.id = id
        self.sourceURL = sourceURL
        self.pixelSize = pixelSize
        self.delay = delay
    }
}

public struct AlignmentDocument: Equatable, Sendable {
    public var frames: [ImageFrame]
    public var anchorFrameID: ImageFrame.ID?
    public var alignmentMode: AlignmentMode
    public var selectionRect: CGRect?
    public var manualPoints: [ImageFrame.ID: CGPoint]
    public var offsets: [ImageFrame.ID: CGSize]
    public var manualCropRect: CGRect?
    public var manualCropInsets: CropInsets
    public var cropPolicy: CropPolicy
    public var defaultDelay: TimeInterval

    public init(
        frames: [ImageFrame] = [],
        anchorFrameID: ImageFrame.ID? = nil,
        alignmentMode: AlignmentMode = .automaticPatch,
        selectionRect: CGRect? = nil,
        manualPoints: [ImageFrame.ID: CGPoint] = [:],
        offsets: [ImageFrame.ID: CGSize] = [:],
        manualCropRect: CGRect? = nil,
        manualCropInsets: CropInsets = .zero,
        cropPolicy: CropPolicy = .commonArea,
        defaultDelay: TimeInterval = 0.12
    ) {
        self.frames = frames
        self.anchorFrameID = anchorFrameID
        self.alignmentMode = alignmentMode
        self.selectionRect = selectionRect
        self.manualPoints = manualPoints
        self.offsets = offsets
        self.manualCropRect = manualCropRect
        self.manualCropInsets = manualCropInsets
        self.cropPolicy = cropPolicy
        self.defaultDelay = defaultDelay
    }

    public var anchorIndex: Int {
        guard let anchorFrameID,
              let index = frames.firstIndex(where: { $0.id == anchorFrameID })
        else {
            return 0
        }
        return index
    }
}

public struct CropInsets: Equatable, Sendable {
    public var left: Double
    public var right: Double
    public var top: Double
    public var bottom: Double

    public init(left: Double = 0, right: Double = 0, top: Double = 0, bottom: Double = 0) {
        self.left = left
        self.right = right
        self.top = top
        self.bottom = bottom
    }

    public static let zero = CropInsets()
}
