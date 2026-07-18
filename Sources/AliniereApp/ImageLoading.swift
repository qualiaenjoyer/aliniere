import AppKit
import CoreGraphics
import Foundation
import ImageIO

enum ImageLoadingError: LocalizedError {
    case cannotRead(URL)
    case unsupportedImage(URL)

    var errorDescription: String? {
        switch self {
        case .cannotRead(let url):
            "Could not read \(url.lastPathComponent)."
        case .unsupportedImage(let url):
            "\(url.lastPathComponent) is not a supported JPEG, PNG, or TIFF image."
        }
    }
}

enum ImageLoading {
    static func loadFrame(from url: URL) throws -> AppImageFrame {
        guard url.startAccessingSecurityScopedResource() else {
            throw ImageLoadingError.cannotRead(url)
        }
        defer { url.stopAccessingSecurityScopedResource() }

        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil)
        else {
            throw ImageLoadingError.unsupportedImage(url)
        }

        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let pixelWidth = properties?[kCGImagePropertyPixelWidth] as? Int ?? 4096
        let pixelHeight = properties?[kCGImagePropertyPixelHeight] as? Int ?? 4096
        let maxPixelSize = max(pixelWidth, pixelHeight)
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceShouldCache: true,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ] as CFDictionary) else {
            throw ImageLoadingError.unsupportedImage(url)
        }

        let thumbnail = makeThumbnail(from: cgImage, maxPixelSize: 180)
        return AppImageFrame(
            id: UUID(),
            url: url,
            name: url.deletingPathExtension().lastPathComponent,
            cgImage: cgImage,
            thumbnail: thumbnail,
            offset: .zero,
            manualOffset: .zero,
            confidence: nil,
            warning: nil,
            delay: 0.12
        )
    }

    private static func makeThumbnail(from image: CGImage, maxPixelSize: CGFloat) -> NSImage {
        let width = CGFloat(image.width)
        let height = CGFloat(image.height)
        let scale = min(maxPixelSize / width, maxPixelSize / height, 1)
        let size = CGSize(width: width * scale, height: height * scale)
        let thumbnail = NSImage(size: size)
        thumbnail.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        NSImage(cgImage: image, size: CGSize(width: width, height: height))
            .draw(in: CGRect(origin: .zero, size: size))
        thumbnail.unlockFocus()
        return thumbnail
    }
}
