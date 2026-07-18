import AliniereCore
import AppKit
import CoreGraphics
import Foundation

struct AppImageFrame: Identifiable, Equatable {
    let id: UUID
    var url: URL
    var name: String
    var cgImage: CGImage
    var thumbnail: NSImage
    var offset: CGSize
    var manualOffset: CGSize
    var confidence: Double?
    var warning: String?
    var delay: TimeInterval

    var imageFrame: ImageFrame {
        ImageFrame(
            id: id,
            sourceURL: url,
            pixelSize: CGSize(width: cgImage.width, height: cgImage.height),
            delay: delay
        )
    }

    static func == (lhs: AppImageFrame, rhs: AppImageFrame) -> Bool {
        lhs.id == rhs.id
            && lhs.url == rhs.url
            && lhs.offset == rhs.offset
            && lhs.manualOffset == rhs.manualOffset
            && lhs.confidence == rhs.confidence
            && lhs.warning == rhs.warning
            && lhs.delay == rhs.delay
    }
}
