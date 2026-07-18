import AVFoundation
import CoreGraphics
import CoreVideo
import Foundation

public enum VideoExporterError: Error, Equatable {
    case couldNotCreateWriter
    case couldNotCreatePixelBuffer
    case couldNotCreateContext
    case missingFrame(Int)
    case writerFailed(String)
}

public struct VideoExporter: Sendable {
    public init() {}

    public func exportMP4(
        frames: [CGImage],
        sequence: [Int],
        offsets: [CGSize],
        cropRect: CGRect,
        delays: [TimeInterval],
        destination url: URL,
        framesPerSecond: Int32 = 30,
        repeats: Int = 8,
        validRect: CGRect? = nil
    ) async throws {
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }

        let crop = cropRect.integral
        let width = max(2, Int(crop.width.rounded(.down)) / 2 * 2)
        let height = max(2, Int(crop.height.rounded(.down)) / 2 * 2)
        guard let writer = try? AVAssetWriter(outputURL: url, fileType: .mp4) else {
            throw VideoExporterError.couldNotCreateWriter
        }

        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: max(8_000_000, width * height * 6),
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
            ]
        ])
        input.expectsMediaDataInRealTime = false

        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height,
                kCVPixelBufferCGImageCompatibilityKey as String: true,
                kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
            ]
        )

        writer.add(input)
        guard writer.startWriting() else {
            throw VideoExporterError.writerFailed(writer.error?.localizedDescription ?? "Could not start writing.")
        }
        writer.startSession(atSourceTime: .zero)

        let frameDuration = CMTime(value: 1, timescale: framesPerSecond)
        var frameNumber: Int64 = 0
        let repeatedSequence = Array(repeating: sequence, count: max(1, repeats)).flatMap { $0 }
        var pixelBufferCache: [Int: CVPixelBuffer] = [:]

        for index in Set(repeatedSequence) {
            guard frames.indices.contains(index), offsets.indices.contains(index) else {
                throw VideoExporterError.missingFrame(index)
            }

            let rendered = try GIFExporter().renderFrame(
                frames[index],
                offset: offsets[index],
                cropRect: CGRect(x: crop.minX, y: crop.minY, width: CGFloat(width), height: CGFloat(height)),
                validRect: validRect
            )
            pixelBufferCache[index] = try makePixelBuffer(from: rendered, width: width, height: height)
        }

        for index in repeatedSequence {
            guard let buffer = pixelBufferCache[index] else {
                throw VideoExporterError.missingFrame(index)
            }

            let delay = delays.indices.contains(index) ? delays[index] : 0.12
            let durationFrames = max(1, Int64((delay * Double(framesPerSecond)).rounded()))

            for _ in 0..<durationFrames {
                while !input.isReadyForMoreMediaData {
                    try await Task.sleep(nanoseconds: 2_000_000)
                }

                let presentationTime = CMTimeMultiply(frameDuration, multiplier: Int32(frameNumber))
                guard adaptor.append(buffer, withPresentationTime: presentationTime) else {
                    throw VideoExporterError.writerFailed(writer.error?.localizedDescription ?? "Could not append frame.")
                }
                frameNumber += 1
            }
        }

        input.markAsFinished()
        await writer.finishWriting()

        if writer.status != .completed {
            throw VideoExporterError.writerFailed(writer.error?.localizedDescription ?? "Could not finish video.")
        }
    }

    private func makePixelBuffer(from image: CGImage, width: Int, height: Int) throws -> CVPixelBuffer {
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            [
                kCVPixelBufferCGImageCompatibilityKey: true,
                kCVPixelBufferCGBitmapContextCompatibilityKey: true
            ] as CFDictionary,
            &pixelBuffer
        )
        guard status == kCVReturnSuccess, let pixelBuffer else {
            throw VideoExporterError.couldNotCreatePixelBuffer
        }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer),
              let context = CGContext(
                data: baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
              )
        else {
            throw VideoExporterError.couldNotCreateContext
        }

        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return pixelBuffer
    }
}
