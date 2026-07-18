import AliniereCore
import AppKit
import CoreGraphics
import Foundation
import Observation
import UniformTypeIdentifiers

@MainActor
@Observable
final class AlignerViewModel {
    private let lowConfidenceAlignmentThreshold = 0.35
    private let automaticSearchRadius = 256

    var frames: [AppImageFrame] = []
    var anchorFrameID: UUID?
    var alignmentMode: AlignmentMode = .automaticPatch
    var selectionRect: CGRect?
    var manualPoints: [UUID: CGPoint] = [:]
    var selectedFrameID: UUID?
    var isPlaying = true
    var playbackIndex = 0
    var globalDelay = 0.12
    var mp4Duration = 6.0
    var alignmentZoom = 1.0
    var previewZoom = 1.0
    var cropPolicy: CropPolicy = .commonArea
    var manualCropRect: CGRect?
    var manualCropInsets: CropInsets = .zero
    var statusMessage = "Import images to begin."
    var exportError: String?

    var document: AlignmentDocument {
        AlignmentDocument(
            frames: frames.map(\.imageFrame),
            anchorFrameID: anchorFrameID,
            alignmentMode: alignmentMode,
            selectionRect: selectionRect,
            manualPoints: manualPoints,
            offsets: Dictionary(uniqueKeysWithValues: frames.map { ($0.id, $0.offset) }),
            manualCropRect: manualCropRect,
            manualCropInsets: manualCropInsets,
            cropPolicy: cropPolicy,
            defaultDelay: globalDelay
        )
    }

    var supportedTypes: [UTType] {
        [.jpeg, .png, .tiff]
    }

    var anchorIndex: Int {
        guard let anchorFrameID,
              let index = frames.firstIndex(where: { $0.id == anchorFrameID })
        else {
            return 0
        }
        return index
    }

    var selectedFrameIndex: Int {
        guard let selectedFrameID,
              let index = frames.firstIndex(where: { $0.id == selectedFrameID })
        else {
            return anchorIndex
        }
        return index
    }

    var sequence: [Int] {
        AnimationSequence.pingPongIndices(frameCount: frames.count)
    }

    var previewFrame: AppImageFrame? {
        guard !frames.isEmpty else { return nil }
        let indices = sequence
        guard !indices.isEmpty else { return frames.first }
        let index = indices[playbackIndex % indices.count]
        return frames[index]
    }

    var commonCropRect: CGRect? {
        guard let first = frames.first else { return nil }
        return CropCalculator.commonCropRect(
            imageSize: CGSize(width: first.cgImage.width, height: first.cgImage.height),
            offsets: frames.map(\.offset)
        )
    }

    var alignedBoundsRect: CGRect? {
        guard let first = frames.first else { return nil }
        return CropCalculator.alignedBoundsRect(
            imageSize: CGSize(width: first.cgImage.width, height: first.cgImage.height),
            offsets: frames.map(\.offset)
        )
    }

    var exportCropRect: CGRect? {
        guard let first = frames.first else { return nil }
        let imageSize = CGSize(width: first.cgImage.width, height: first.cgImage.height)
        switch cropPolicy {
        case .commonArea:
            return CropCalculator.commonCropRect(imageSize: imageSize, offsets: frames.map(\.offset))
        case .manual:
            let common = CropCalculator.commonCropRect(imageSize: imageSize, offsets: frames.map(\.offset))
            return CropCalculator.cropRect(commonRect: common, insets: manualCropInsets)
        }
    }

    func importImages(from urls: [URL]) {
        let limitedURLs = Array(urls.prefix(4))
        do {
            let loaded = try limitedURLs.map(ImageLoading.loadFrame(from:))
            frames = loaded
            anchorFrameID = loaded.first?.id
            selectedFrameID = loaded.first?.id
            alignmentMode = .automaticPatch
            selectionRect = nil
            manualPoints = [:]
            manualCropRect = nil
            manualCropInsets = .zero
            cropPolicy = .commonArea
            playbackIndex = 0
            statusMessage = loaded.count < 2
                ? "Import at least two images for alignment."
                : "Draw a rectangle around a detailed point, or switch to point mode."
        } catch {
            exportError = error.localizedDescription
        }
    }

    func setGlobalDelay(_ delay: TimeInterval) {
        globalDelay = delay
        for index in frames.indices {
            frames[index].delay = delay
        }
    }

    func setAnchor(_ id: UUID) {
        anchorFrameID = id
        selectedFrameID = id
        selectionRect = nil
        manualPoints = [:]
        resetOffsets()
        statusMessage = alignmentMode == .automaticPatch
            ? "Draw a new alignment zone."
            : "Click the reference point on each frame."
    }

    func selectFrame(_ id: UUID) {
        selectedFrameID = id
    }

    func removeFrame(_ id: UUID) {
        guard let index = frames.firstIndex(where: { $0.id == id }) else {
            return
        }

        frames.remove(at: index)
        manualPoints[id] = nil

        if frames.isEmpty {
            anchorFrameID = nil
            selectedFrameID = nil
            selectionRect = nil
            manualPoints = [:]
            manualCropRect = nil
            manualCropInsets = .zero
            cropPolicy = .commonArea
            playbackIndex = 0
            resetOffsets()
            statusMessage = "Import images to begin."
            return
        }

        if anchorFrameID == id {
            anchorFrameID = frames[min(index, frames.count - 1)].id
            selectionRect = nil
        }
        if selectedFrameID == id {
            selectedFrameID = anchorFrameID ?? frames[min(index, frames.count - 1)].id
        }

        playbackIndex = 0
        if cropPolicy == .manual {
            clampManualInsets()
        }

        if frames.count < 2 {
            resetOffsets()
            statusMessage = "Import at least two frames for alignment."
        } else if alignmentMode == .manualPoints {
            alignManualPoints()
        } else {
            alignFrames()
        }
    }

    func updateSelection(_ rect: CGRect, anchorFrameID: UUID? = nil) {
        alignmentMode = .automaticPatch
        self.anchorFrameID = anchorFrameID ?? selectedFrameID ?? self.anchorFrameID ?? frames.first?.id
        selectedFrameID = self.anchorFrameID
        selectionRect = rect.standardized.integral
        alignFrames()
    }

    func setAlignmentMode(_ mode: AlignmentMode) {
        alignmentMode = mode
        resetOffsets()
        switch mode {
        case .automaticPatch:
            selectedFrameID = anchorFrameID ?? frames.first?.id
            statusMessage = selectionRect == nil
                ? "Draw a rectangle around a detailed point that should stay still."
                : "Automatic patch mode active."
            alignFrames()
        case .manualPoints:
            statusMessage = "Click the same reference point on each frame."
            alignManualPoints()
        }
    }

    func alignFrames() {
        guard alignmentMode == .automaticPatch else {
            alignManualPoints()
            return
        }
        guard let selectionRect,
              frames.count >= 2,
              frames.indices.contains(anchorIndex)
        else {
            return
        }

        let lumas = frames.map { LumaImage(cgImage: $0.cgImage, maxDimension: 1600) }
        guard lumas[anchorIndex] != nil else {
            statusMessage = "Could not prepare the anchor frame for alignment."
            return
        }

        let engine = AlignmentEngine()
        var warnings: [String] = []
        var autoOffsets = Array<CGSize?>(repeating: nil, count: frames.count)
        autoOffsets[anchorIndex] = .zero

        for index in frames.indices {
            frames[index].confidence = nil
            frames[index].warning = lumas[index] == nil ? "Could not read this frame." : nil
            if lumas[index] == nil {
                warnings.append("\(frames[index].name): could not be read.")
            }
        }

        frames[anchorIndex].offset = frames[anchorIndex].manualOffset
        frames[anchorIndex].confidence = 1
        frames[anchorIndex].warning = nil

        func align(targetIndex: Int, from sourceIndices: [Int]) -> Bool {
            var bestResult: (sourceIndex: Int, offset: CGSize, confidence: Double, warning: String?)?
            let orderedSources = Array(NSOrderedSet(array: sourceIndices)) as? [Int] ?? sourceIndices

            for sourceIndex in orderedSources {
                guard let sourceLuma = lumas[sourceIndex],
                      let targetLuma = lumas[targetIndex],
                      let sourceAutoOffset = autoOffsets[sourceIndex]
                else {
                    continue
                }

                let sourceFrame = frames[sourceIndex]
                let sourceOriginalSize = CGSize(width: sourceFrame.cgImage.width, height: sourceFrame.cgImage.height)
                let sourceSelection = selectionRect.offsetBy(
                    dx: sourceAutoOffset.width,
                    dy: sourceAutoOffset.height
                )
                let scaledSelections = candidateAlignmentSelections(
                    fromOriginal: sourceSelection,
                    sourceLuma: sourceLuma,
                    originalSize: sourceOriginalSize
                )
                let scaleBackX = sourceOriginalSize.width / Double(sourceLuma.width)
                let scaleBackY = sourceOriginalSize.height / Double(sourceLuma.height)

                for selection in scaledSelections {
                    do {
                        let result = try engine.align(
                            anchor: sourceLuma,
                            image: targetLuma,
                            selection: selection,
                            searchRadius: automaticSearchRadius
                        )

                        let pairOffset = CGSize(
                            width: result.offset.width * scaleBackX,
                            height: result.offset.height * scaleBackY
                        )
                        let autoOffset = sourceAutoOffset + pairOffset
                        let candidateWarning = result.confidence < lowConfidenceAlignmentThreshold
                            ? (result.warning ?? "Low confidence match; alignment may be a little soft.")
                            : result.warning

                        let candidate = (
                            sourceIndex: sourceIndex,
                            offset: autoOffset,
                            confidence: result.confidence,
                            warning: candidateWarning
                        )

                        if result.confidence >= lowConfidenceAlignmentThreshold {
                            bestResult = candidate
                            break
                        }

                        if bestResult == nil || result.confidence > bestResult!.confidence {
                            bestResult = candidate
                        }
                    } catch {
                        continue
                    }
                }

                if let bestResult, bestResult.confidence >= lowConfidenceAlignmentThreshold {
                    break
                }
            }

            guard let bestResult else {
                frames[targetIndex].warning = "Alignment failed for this frame."
                return false
            }

            autoOffsets[targetIndex] = bestResult.offset
            frames[targetIndex].offset = bestResult.offset + frames[targetIndex].manualOffset
            frames[targetIndex].confidence = bestResult.confidence
            frames[targetIndex].warning = bestResult.warning
            if let warning = bestResult.warning {
                warnings.append("\(frames[targetIndex].name): \(warning)")
            }
            return true
        }

        if anchorIndex + 1 < frames.count {
            for targetIndex in (anchorIndex + 1)..<frames.count {
                _ = align(targetIndex: targetIndex, from: [anchorIndex])
            }
        }

        if anchorIndex > 0 {
            for targetIndex in stride(from: anchorIndex - 1, through: 0, by: -1) {
                _ = align(targetIndex: targetIndex, from: [anchorIndex])
            }
        }

        for index in frames.indices where autoOffsets[index] == nil {
            let fallback = nearestAlignedOffset(to: index, autoOffsets: autoOffsets) ?? .zero
            frames[index].offset = fallback + frames[index].manualOffset
            frames[index].confidence = frames[index].confidence ?? 0
            frames[index].warning = frames[index].warning ?? "Alignment failed for this frame."
            warnings.append("\(frames[index].name): alignment failed.")
        }

        statusMessage = warnings.first ?? "Aligned \(frames.count) frames."
        if cropPolicy == .manual {
            clampManualInsets()
        }
    }

    func setManualPoint(_ point: CGPoint, for frameID: UUID) {
        alignmentMode = .manualPoints
        selectedFrameID = frameID
        manualPoints[frameID] = point
        alignManualPoints()
    }

    func alignManualPoints() {
        guard frames.count >= 2,
              frames.indices.contains(anchorIndex),
              let anchorFrameID,
              let anchorPoint = manualPoints[anchorFrameID]
        else {
            resetOffsets()
            statusMessage = "Click a reference point on the first frame first."
            return
        }

        var missing = 0
        for index in frames.indices {
            let frameID = frames[index].id
            guard let point = manualPoints[frameID] else {
                frames[index].offset = frames[index].manualOffset
                frames[index].confidence = frameID == anchorFrameID ? 1 : nil
                frames[index].warning = frameID == anchorFrameID ? nil : "Pick a point on this frame."
                if frameID != anchorFrameID {
                    missing += 1
                }
                continue
            }

            let pointOffset = CGSize(
                width: anchorPoint.x - point.x,
                height: anchorPoint.y - point.y
            )
            frames[index].offset = pointOffset + frames[index].manualOffset
            frames[index].confidence = 1
            frames[index].warning = nil
        }

        statusMessage = missing == 0
            ? "Aligned by manual points."
            : "Pick points on \(missing) more frame\(missing == 1 ? "" : "s")."

        if cropPolicy == .manual {
            clampManualInsets()
        }
    }

    func nudgeSelected(dx: CGFloat, dy: CGFloat) {
        guard let selectedFrameID,
              let index = frames.firstIndex(where: { $0.id == selectedFrameID })
        else {
            return
        }

        frames[index].manualOffset.width += dx
        frames[index].manualOffset.height += dy
        frames[index].offset.width += dx
        frames[index].offset.height += dy
    }

    func moveFrame(from source: IndexSet, to destination: Int) {
        frames.move(fromOffsets: source, toOffset: destination)
        if anchorFrameID == nil {
            anchorFrameID = frames.first?.id
        }
        playbackIndex = 0
        refreshAlignmentAfterFrameOrderChange()
    }

    func moveFrame(at index: Int, direction: Int) {
        let destination = index + direction
        guard frames.indices.contains(index), frames.indices.contains(destination) else {
            return
        }
        frames.swapAt(index, destination)
        playbackIndex = 0
        refreshAlignmentAfterFrameOrderChange()
    }

    func moveFrame(id: UUID, before targetID: UUID, realign: Bool = true) {
        guard let sourceIndex = frames.firstIndex(where: { $0.id == id }),
              let targetIndex = frames.firstIndex(where: { $0.id == targetID }),
              sourceIndex != targetIndex
        else {
            return
        }

        var insertionIndex = targetIndex
        if sourceIndex < targetIndex {
            insertionIndex -= 1
        }
        guard sourceIndex != insertionIndex else {
            return
        }

        let item = frames.remove(at: sourceIndex)
        frames.insert(item, at: insertionIndex)
        playbackIndex = 0
        if realign {
            refreshAlignmentAfterFrameOrderChange()
        }
    }

    func refreshAlignmentAfterFrameOrderChange() {
        if alignmentMode == .manualPoints {
            alignManualPoints()
        } else {
            alignFrames()
        }
    }

    func advancePlayback() {
        guard !sequence.isEmpty else { return }
        playbackIndex = (playbackIndex + 1) % sequence.count
    }

    func exportGIF(to url: URL) {
        guard let cropRect = exportCropRect else { return }
        do {
            try GIFExporter().export(
                frames: frames.map(\.cgImage),
                sequence: sequence,
                offsets: frames.map(\.offset),
                cropRect: cropRect,
                delays: frames.map(\.delay),
                validRect: manualCropValidRect,
                destination: url
            )
            statusMessage = "Exported \(url.lastPathComponent)."
        } catch {
            exportError = error.localizedDescription
        }
    }

    func makeGIFData() throws -> Data {
        guard let cropRect = exportCropRect else {
            return Data()
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("gif")
        defer { try? FileManager.default.removeItem(at: url) }

        try GIFExporter().export(
            frames: frames.map(\.cgImage),
            sequence: sequence,
            offsets: frames.map(\.offset),
            cropRect: cropRect,
            delays: frames.map(\.delay),
            validRect: manualCropValidRect,
            destination: url
        )
        return try Data(contentsOf: url)
    }

    func exportVideo(to url: URL) async {
        guard let cropRect = exportCropRect else { return }
        do {
            try await VideoExporter().exportMP4(
                frames: frames.map(\.cgImage),
                sequence: sequence,
                offsets: frames.map(\.offset),
                cropRect: cropRect,
                delays: frames.map(\.delay),
                destination: url,
                repeats: mp4RepeatCount,
                validRect: manualCropValidRect
            )
            statusMessage = "Exported \(url.lastPathComponent)."
        } catch {
            exportError = error.localizedDescription
        }
    }

    func useAutomaticCrop() {
        cropPolicy = .commonArea
        manualCropRect = nil
        manualCropInsets = .zero
    }

    func beginManualCrop() {
        cropPolicy = .manual
        manualCropRect = exportCropRect
        clampManualInsets()
    }

    func updateManualCrop(_ rect: CGRect) {
        guard let first = frames.first else { return }
        cropPolicy = .manual
        let clamped = CropCalculator.clampedManualCropRect(
            rect,
            imageSize: CGSize(width: first.cgImage.width, height: first.cgImage.height),
            offsets: frames.map(\.offset)
        )
        manualCropRect = clamped
        if let commonCropRect {
            manualCropInsets = CropCalculator.insets(commonRect: commonCropRect, cropRect: clamped)
        }
    }

    func setManualCropInset(_ edge: CropEdge, value: Double) {
        cropPolicy = .manual
        switch edge {
        case .left:
            manualCropInsets.left = value
        case .right:
            manualCropInsets.right = value
        case .top:
            manualCropInsets.top = value
        case .bottom:
            manualCropInsets.bottom = value
        }
        clampManualInsets()
    }

    private func resetOffsets() {
        for index in frames.indices {
            frames[index].offset = .zero
            frames[index].manualOffset = .zero
            frames[index].confidence = nil
            frames[index].warning = nil
        }
    }

    private func clampManualInsets() {
        guard let commonCropRect else {
            manualCropInsets = .zero
            manualCropRect = nil
            return
        }

        let crop = CropCalculator.cropRect(commonRect: commonCropRect, insets: manualCropInsets)
        manualCropRect = crop
        manualCropInsets = CropCalculator.insets(commonRect: commonCropRect, cropRect: crop)
    }

    private var mp4RepeatCount: Int {
        let duration = sequence.reduce(0.0) { total, index in
            total + (frames.indices.contains(index) ? frames[index].delay : globalDelay)
        }
        guard duration > 0 else { return 1 }
        return max(1, Int((mp4Duration / duration).rounded(.up)))
    }

    private var manualCropValidRect: CGRect? {
        cropPolicy == .manual ? commonCropRect : nil
    }

    private func nearestAlignedOffset(to index: Int, autoOffsets: [CGSize?]) -> CGSize? {
        let candidates = autoOffsets.indices.compactMap { candidateIndex -> (distance: Int, offset: CGSize)? in
            guard let offset = autoOffsets[candidateIndex] else { return nil }
            return (abs(candidateIndex - index), offset)
        }
        return candidates.min { $0.distance < $1.distance }?.offset
    }

    private func candidateAlignmentSelections(
        fromOriginal rect: CGRect,
        sourceLuma: LumaImage,
        originalSize: CGSize
    ) -> [CGRect] {
        let base = sourceLuma.scaledRect(fromOriginal: rect, originalSize: originalSize)
        let expanded = sourceLuma.scaledRect(
            fromOriginal: expandedRect(rect, factor: 0.15, in: originalSize),
            originalSize: originalSize
        )
        let contracted = sourceLuma.scaledRect(
            fromOriginal: contractedRect(rect, factor: 0.10),
            originalSize: originalSize
        )
        return [base, expanded, contracted].filter { $0.width >= 8 && $0.height >= 8 }
    }

    private func expandedRect(_ rect: CGRect, factor: Double, in imageSize: CGSize) -> CGRect {
        let dx = rect.width * factor
        let dy = rect.height * factor
        return rect
            .insetBy(dx: -dx, dy: -dy)
            .intersection(CGRect(origin: .zero, size: imageSize))
    }

    private func contractedRect(_ rect: CGRect, factor: Double) -> CGRect {
        let dx = rect.width * factor
        let dy = rect.height * factor
        let contracted = rect.insetBy(dx: dx, dy: dy)
        return contracted.isNull ? rect : contracted
    }
}

private func + (lhs: CGSize, rhs: CGSize) -> CGSize {
    CGSize(width: lhs.width + rhs.width, height: lhs.height + rhs.height)
}

enum CropEdge {
    case left
    case right
    case top
    case bottom
}
