import CoreGraphics
import Foundation
import ImageIO

public struct LumaImage: Equatable, Sendable {
    public let width: Int
    public let height: Int
    public var pixels: [Double]

    public init(width: Int, height: Int, pixels: [Double]) {
        precondition(width > 0)
        precondition(height > 0)
        precondition(pixels.count == width * height)
        self.width = width
        self.height = height
        self.pixels = pixels
    }

    public subscript(x: Int, y: Int) -> Double {
        get { pixels[y * width + x] }
        set { pixels[y * width + x] = newValue }
    }

    public init?(cgImage: CGImage, maxDimension: Int? = nil) {
        let sourceWidth = cgImage.width
        let sourceHeight = cgImage.height
        let targetSize: CGSize

        if let maxDimension, max(sourceWidth, sourceHeight) > maxDimension {
            let scale = Double(maxDimension) / Double(max(sourceWidth, sourceHeight))
            targetSize = CGSize(
                width: max(1, Int(Double(sourceWidth) * scale)),
                height: max(1, Int(Double(sourceHeight) * scale))
            )
        } else {
            targetSize = CGSize(width: sourceWidth, height: sourceHeight)
        }

        let width = Int(targetSize.width)
        let height = Int(targetSize.height)
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(
            data: &bytes,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        context.interpolationQuality = .high
        context.draw(cgImage, in: CGRect(origin: .zero, size: targetSize))

        var pixels = [Double](repeating: 0, count: width * height)
        for index in 0..<(width * height) {
            let base = index * 4
            let red = Double(bytes[base])
            let green = Double(bytes[base + 1])
            let blue = Double(bytes[base + 2])
            pixels[index] = (0.2126 * red + 0.7152 * green + 0.0722 * blue) / 255.0
        }

        self.init(width: width, height: height, pixels: pixels)
    }

    public func scaledRect(fromOriginal rect: CGRect, originalSize: CGSize) -> CGRect {
        let scaleX = Double(width) / originalSize.width
        let scaleY = Double(height) / originalSize.height
        return CGRect(
            x: rect.origin.x * scaleX,
            y: rect.origin.y * scaleY,
            width: rect.size.width * scaleX,
            height: rect.size.height * scaleY
        ).integral
    }
}
