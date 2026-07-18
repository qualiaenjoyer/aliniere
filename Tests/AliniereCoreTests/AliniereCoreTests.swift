import CoreGraphics
import AVFoundation
import Foundation
import ImageIO
import XCTest
@testable import AliniereCore

final class AliniereCoreTests: XCTestCase {
    func testPingPongSequences() {
        XCTAssertEqual(AnimationSequence.pingPongIndices(frameCount: 2), [0, 1])
        XCTAssertEqual(AnimationSequence.pingPongIndices(frameCount: 3), [0, 1, 2, 1])
        XCTAssertEqual(AnimationSequence.pingPongIndices(frameCount: 4), [0, 1, 2, 3, 2, 1])
    }

    func testManualPointOffsetMath() {
        let anchor = CGPoint(x: 20, y: 40)
        let other = CGPoint(x: 35, y: 31)
        let offset = CGSize(width: anchor.x - other.x, height: anchor.y - other.y)

        XCTAssertEqual(offset, CGSize(width: -15, height: 9))
    }

    func testAlignmentRecoversTranslation() throws {
        let anchor = syntheticImage(width: 80, height: 70)
        let shifted = shiftedImage(anchor, dx: 7, dy: -5)
        let result = try AlignmentEngine().align(
            anchor: anchor,
            image: shifted,
            selection: CGRect(x: 20, y: 20, width: 28, height: 24),
            searchRadius: 14
        )

        XCTAssertEqual(Int(result.offset.width), -7)
        XCTAssertEqual(Int(result.offset.height), 5)
        XCTAssertGreaterThan(result.confidence, 0.95)
    }

    func testCommonCropRectWithPositiveAndNegativeOffsets() {
        let crop = CropCalculator.commonCropRect(
            imageSize: CGSize(width: 100, height: 80),
            offsets: [
                .zero,
                CGSize(width: 10, height: -4),
                CGSize(width: -6, height: 8)
            ]
        )

        XCTAssertEqual(crop, CGRect(x: 10, y: 8, width: 84, height: 68))
    }

    func testAlignedBoundsRectIncludesTranslatedEdges() {
        let bounds = CropCalculator.alignedBoundsRect(
            imageSize: CGSize(width: 100, height: 80),
            offsets: [
                .zero,
                CGSize(width: -12, height: 7),
                CGSize(width: 15, height: -4)
            ]
        )

        XCTAssertEqual(bounds, CGRect(x: -12, y: -4, width: 127, height: 91))
    }

    func testManualCropClampsToCommonArea() {
        let crop = CropCalculator.clampedManualCropRect(
            CGRect(x: 0, y: 0, width: 200, height: 200),
            imageSize: CGSize(width: 100, height: 80),
            offsets: [
                .zero,
                CGSize(width: 10, height: -4),
                CGSize(width: -6, height: 8)
            ]
        )

        XCTAssertEqual(crop, CGRect(x: 10, y: 8, width: 84, height: 68))
    }

    func testCropInsetsAdjustEachEdgeIndependently() {
        let common = CGRect(x: 10, y: 8, width: 84, height: 68)
        let crop = CropCalculator.cropRect(
            commonRect: common,
            insets: CropInsets(left: 3, right: 5, top: 7, bottom: 11)
        )

        XCTAssertEqual(crop, CGRect(x: 13, y: 15, width: 76, height: 50))
        XCTAssertEqual(
            CropCalculator.insets(commonRect: common, cropRect: crop),
            CropInsets(left: 3, right: 5, top: 7, bottom: 11)
        )
    }

    func testCropInsetsCanGoNegative() {
        let common = CGRect(x: 10, y: 8, width: 84, height: 68)
        let crop = CropCalculator.cropRect(
            commonRect: common,
            insets: CropInsets(left: -4, right: -2, top: -3, bottom: -1)
        )

        XCTAssertEqual(crop, CGRect(x: 6, y: 5, width: 90, height: 72))
        XCTAssertEqual(
            CropCalculator.insets(commonRect: common, cropRect: crop),
            CropInsets(left: -4, right: -2, top: -3, bottom: -1)
        )
    }

    func testLowTextureSelectionRejectsAlignment() throws {
        let pixels = [Double](repeating: 0.5, count: 40 * 40)
        let image = LumaImage(width: 40, height: 40, pixels: pixels)
        let result = try AlignmentEngine().align(
            anchor: image,
            image: image,
            selection: CGRect(x: 10, y: 10, width: 16, height: 16),
            searchRadius: 8
        )

        XCTAssertEqual(result.confidence, 0)
        XCTAssertNotNil(result.warning)
    }

    func testGIFExportWritesExpectedFrameCountAndDelay() throws {
        let frames = [
            try makeCGImage(red: 255, green: 0, blue: 0),
            try makeCGImage(red: 0, green: 255, blue: 0)
        ]
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("gif")
        defer { try? FileManager.default.removeItem(at: url) }

        try GIFExporter().export(
            frames: frames,
            sequence: [0, 1],
            offsets: [.zero, .zero],
            cropRect: CGRect(x: 0, y: 0, width: 20, height: 20),
            delays: [0.12, 0.2],
            destination: url
        )

        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return XCTFail("Expected GIF source")
        }
        XCTAssertEqual(CGImageSourceGetCount(source), 2)

        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let gifProperties = properties?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
        let delay = gifProperties?[kCGImagePropertyGIFDelayTime] as? Double
        XCTAssertEqual(delay ?? 0, 0.12, accuracy: 0.02)
    }

    func testGIFExportPreservesRenderedOrientation() throws {
        let image = try makeQuadrantImage()
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("gif")
        defer { try? FileManager.default.removeItem(at: url) }

        try GIFExporter().export(
            frames: [image],
            sequence: [0],
            offsets: [.zero],
            cropRect: CGRect(x: 0, y: 0, width: 2, height: 2),
            delays: [0.12],
            destination: url
        )

        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let decoded = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            return XCTFail("Expected decoded GIF frame")
        }

        XCTAssertEqual(try rgba(atX: 0, y: 0, in: decoded), [255, 0, 0, 255])
        XCTAssertEqual(try rgba(atX: 1, y: 0, in: decoded), [0, 255, 0, 255])
        XCTAssertEqual(try rgba(atX: 0, y: 1, in: decoded), [0, 0, 255, 255])
        XCTAssertEqual(try rgba(atX: 1, y: 1, in: decoded), [255, 255, 255, 255])
    }

    func testMP4ExportWritesPlayableVideo() async throws {
        let image = try makeQuadrantImage()
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mp4")
        defer { try? FileManager.default.removeItem(at: url) }

        try await VideoExporter().exportMP4(
            frames: [image],
            sequence: [0, 0, 0, 0],
            offsets: [.zero],
            cropRect: CGRect(x: 0, y: 0, width: 2, height: 2),
            delays: [0.25],
            destination: url,
            repeats: 6
        )

        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        XCTAssertGreaterThan(attributes[.size] as? Int ?? 0, 0)

        let asset = AVURLAsset(url: url)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        XCTAssertEqual(tracks.count, 1)

        let duration = try await asset.load(.duration)
        XCTAssertEqual(CMTimeGetSeconds(duration), 6.0, accuracy: 0.05)
    }

    func testRenderFrameUsesTopLeftCropCoordinates() throws {
        let image = try makeQuadrantImage()
        let rendered = try GIFExporter().renderFrame(
            image,
            offset: .zero,
            cropRect: CGRect(x: 0, y: 0, width: 2, height: 2)
        )

        XCTAssertEqual(try rgba(atX: 0, y: 0, in: rendered), [255, 0, 0, 255])
        XCTAssertEqual(try rgba(atX: 1, y: 0, in: rendered), [0, 255, 0, 255])
        XCTAssertEqual(try rgba(atX: 0, y: 1, in: rendered), [0, 0, 255, 255])
        XCTAssertEqual(try rgba(atX: 1, y: 1, in: rendered), [255, 255, 255, 255])
    }

    func testRenderFrameAppliesOffsetBeforeCrop() throws {
        let image = try makeQuadrantImage()
        let rendered = try GIFExporter().renderFrame(
            image,
            offset: CGSize(width: -1, height: 0),
            cropRect: CGRect(x: 0, y: 0, width: 1, height: 1)
        )

        XCTAssertEqual(try rgba(atX: 0, y: 0, in: rendered), [0, 255, 0, 255])
    }

    func testRenderFrameClampsPastImageEdges() throws {
        let image = try makeQuadrantImage()
        let rendered = try GIFExporter().renderFrame(
            image,
            offset: CGSize(width: 0, height: 0),
            cropRect: CGRect(x: -1, y: -1, width: 2, height: 2)
        )

        XCTAssertEqual(try rgba(atX: 0, y: 0, in: rendered), [0, 0, 0, 255])
    }

    func testRenderFrameMasksOutsideValidRect() throws {
        let image = try makeQuadrantImage()
        let rendered = try GIFExporter().renderFrame(
            image,
            offset: CGSize(width: 0, height: 0),
            cropRect: CGRect(x: -1, y: 0, width: 3, height: 1),
            validRect: CGRect(x: 0, y: 0, width: 2, height: 2)
        )

        XCTAssertEqual(try rgba(atX: 0, y: 0, in: rendered), [0, 0, 0, 255])
        XCTAssertEqual(try rgba(atX: 1, y: 0, in: rendered), [255, 0, 0, 255])
    }

    private func syntheticImage(width: Int, height: Int) -> LumaImage {
        var pixels = [Double](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                let stripes = ((x * 17 + y * 31) % 23) < 11 ? 0.25 : 0.75
                let spot = (x - 34) * (x - 34) + (y - 30) * (y - 30) < 80 ? 1.0 : 0.0
                pixels[y * width + x] = min(1, stripes + spot)
            }
        }
        return LumaImage(width: width, height: height, pixels: pixels)
    }

    private func shiftedImage(_ image: LumaImage, dx: Int, dy: Int) -> LumaImage {
        var pixels = [Double](repeating: 0, count: image.width * image.height)
        for y in 0..<image.height {
            for x in 0..<image.width {
                let sourceX = x - dx
                let sourceY = y - dy
                if sourceX >= 0, sourceX < image.width, sourceY >= 0, sourceY < image.height {
                    pixels[y * image.width + x] = image[sourceX, sourceY]
                }
            }
        }
        return LumaImage(width: image.width, height: image.height, pixels: pixels)
    }

    private func makeCGImage(red: UInt8, green: UInt8, blue: UInt8) throws -> CGImage {
        let width = 20
        let height = 20
        var data = [UInt8]()
        for _ in 0..<(width * height) {
            data.append(contentsOf: [red, green, blue, 255])
        }

        guard let provider = CGDataProvider(data: Data(data) as CFData),
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
                shouldInterpolate: false,
                intent: .defaultIntent
              )
        else {
            throw GIFExporterError.couldNotCreateContext
        }
        return image
    }

    private func makeQuadrantImage() throws -> CGImage {
        let data: [UInt8] = [
            255, 0, 0, 255,
            0, 255, 0, 255,
            0, 0, 255, 255,
            255, 255, 255, 255
        ]

        guard let provider = CGDataProvider(data: Data(data) as CFData),
              let image = CGImage(
                width: 2,
                height: 2,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: 8,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
              )
        else {
            throw GIFExporterError.couldNotCreateContext
        }
        return image
    }

    private func rgba(atX x: Int, y: Int, in image: CGImage) throws -> [UInt8] {
        var data = [UInt8](repeating: 0, count: image.width * image.height * 4)
        guard let context = CGContext(
            data: &data,
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
        let index = (y * image.width + x) * 4
        return Array(data[index..<(index + 4)])
    }
}
