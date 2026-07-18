import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum GIFExporterError: Error, Equatable {
    case couldNotCreateDestination
    case couldNotCreateContext
    case missingFrame(Int)
    case writeFailed
}

public struct GIFExporter: Sendable {
    public init() {}

    public func export(
        frames: [CGImage],
        sequence: [Int],
        offsets: [CGSize],
        cropRect: CGRect,
        delays: [TimeInterval],
        validRect: CGRect? = nil,
        destination url: URL
    ) throws {
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.gif.identifier as CFString,
            sequence.count,
            nil
        ) else {
            throw GIFExporterError.couldNotCreateDestination
        }

        CGImageDestinationSetProperties(destination, [
            kCGImagePropertyGIFDictionary: [
                kCGImagePropertyGIFLoopCount: 0
            ]
        ] as CFDictionary)

        for index in sequence {
            guard frames.indices.contains(index), offsets.indices.contains(index) else {
                throw GIFExporterError.missingFrame(index)
            }

            let image = try renderFrame(
                frames[index],
                offset: offsets[index],
                cropRect: cropRect,
                validRect: validRect
            )
            let delay = delays.indices.contains(index) ? delays[index] : 0.12
            CGImageDestinationAddImage(destination, image, [
                kCGImagePropertyGIFDictionary: [
                    kCGImagePropertyGIFDelayTime: delay,
                    kCGImagePropertyGIFUnclampedDelayTime: delay
                ]
            ] as CFDictionary)
        }

        guard CGImageDestinationFinalize(destination) else {
            throw GIFExporterError.writeFailed
        }
    }

    public func renderFrame(
        _ image: CGImage,
        offset: CGSize,
        cropRect: CGRect,
        validRect: CGRect? = nil
    ) throws -> CGImage {
        let crop = cropRect.integral
        let valid = validRect?.integral
        let outputWidth = max(1, Int(crop.width))
        let outputHeight = max(1, Int(crop.height))
        let source = try rgbaPixels(from: image)
        var output = [UInt8](repeating: 0, count: outputWidth * outputHeight * 4)

        for y in 0..<outputHeight {
            for x in 0..<outputWidth {
                let outputX = Double(x) + crop.minX
                let outputY = Double(y) + crop.minY
                let color: (UInt8, UInt8, UInt8, UInt8)
                if let valid,
                   !valid.contains(CGPoint(x: outputX, y: outputY)) {
                    color = (0, 0, 0, 255)
                } else {
                    color = sampleBilinear(
                        source,
                        width: image.width,
                        height: image.height,
                        x: outputX - offset.width,
                        y: outputY - offset.height
                    )
                }
                let index = (y * outputWidth + x) * 4
                output[index] = color.0
                output[index + 1] = color.1
                output[index + 2] = color.2
                output[index + 3] = color.3
            }
        }

        return try makeImage(width: outputWidth, height: outputHeight, pixels: output)
    }

    private func rgbaPixels(from image: CGImage) throws -> [UInt8] {
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        guard let context = CGContext(
            data: &pixels,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: image.width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw GIFExporterError.couldNotCreateContext
        }

        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return pixels
    }

    private func makeImage(width: Int, height: Int, pixels: [UInt8]) throws -> CGImage {
        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let image = CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: provider,
                decode: nil,
                shouldInterpolate: true,
                intent: .defaultIntent
              )
        else {
            throw GIFExporterError.couldNotCreateContext
        }
        return image
    }

    private func sampleBilinear(
        _ pixels: [UInt8],
        width: Int,
        height: Int,
        x: Double,
        y: Double
    ) -> (UInt8, UInt8, UInt8, UInt8) {
        guard x >= 0, y >= 0, x <= Double(width - 1), y <= Double(height - 1) else {
            return (0, 0, 0, 255)
        }

        let x0 = Int(floor(x))
        let y0 = Int(floor(y))
        let x1 = min(width - 1, x0 + 1)
        let y1 = min(height - 1, y0 + 1)
        let tx = x - Double(x0)
        let ty = y - Double(y0)

        func channel(_ x: Int, _ y: Int, _ offset: Int) -> Double {
            Double(pixels[(y * width + x) * 4 + offset])
        }

        func interpolate(_ offset: Int) -> UInt8 {
            let top = channel(x0, y0, offset) * (1 - tx) + channel(x1, y0, offset) * tx
            let bottom = channel(x0, y1, offset) * (1 - tx) + channel(x1, y1, offset) * tx
            let value = top * (1 - ty) + bottom * ty
            return UInt8(max(0, min(255, value.rounded())))
        }

        return (
            interpolate(0),
            interpolate(1),
            interpolate(2),
            interpolate(3)
        )
    }
}
