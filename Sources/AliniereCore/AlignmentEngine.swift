import CoreGraphics
import Foundation

public struct AlignmentResult: Equatable, Sendable {
    public var offset: CGSize
    public var confidence: Double
    public var warning: String?

    public init(offset: CGSize, confidence: Double, warning: String? = nil) {
        self.offset = offset
        self.confidence = confidence
        self.warning = warning
    }
}

public enum AlignmentEngineError: Error, Equatable {
    case invalidSelection
    case selectionOutOfBounds
    case imageSizeMismatch
}

public struct AlignmentEngine: Sendable {
    private let lowTextureVarianceThreshold: Double

    public init(lowTextureVarianceThreshold: Double = 0.0008) {
        self.lowTextureVarianceThreshold = lowTextureVarianceThreshold
    }

    public func align(
        anchor: LumaImage,
        image: LumaImage,
        selection: CGRect,
        searchRadius: Int = 96
    ) throws -> AlignmentResult {
        guard anchor.width == image.width, anchor.height == image.height else {
            throw AlignmentEngineError.imageSizeMismatch
        }

        let rect = selection.integral
        let x0 = Int(rect.origin.x)
        let y0 = Int(rect.origin.y)
        let templateWidth = Int(rect.width)
        let templateHeight = Int(rect.height)
        guard templateWidth >= 8, templateHeight >= 8 else {
            throw AlignmentEngineError.invalidSelection
        }
        guard x0 >= 0, y0 >= 0, x0 + templateWidth <= anchor.width, y0 + templateHeight <= anchor.height else {
            throw AlignmentEngineError.selectionOutOfBounds
        }

        let templateStats = stats(in: anchor, x: x0, y: y0, width: templateWidth, height: templateHeight)
        if templateStats.variance < lowTextureVarianceThreshold {
            return AlignmentResult(
                offset: .zero,
                confidence: 0,
                warning: "Pick a more detailed area; this selection has too little texture to align reliably."
            )
        }

        let coarseStep = searchRadius >= 24 ? 4 : 2
        let coarse = bestMatch(
            anchor: anchor,
            image: image,
            x0: x0,
            y0: y0,
            width: templateWidth,
            height: templateHeight,
            dxRange: stride(from: -searchRadius, through: searchRadius, by: coarseStep).map { $0 },
            dyRange: stride(from: -searchRadius, through: searchRadius, by: coarseStep).map { $0 },
            templateStats: templateStats
        )

        let refineRadius = max(6, coarseStep * 2)
        let refined = bestMatch(
            anchor: anchor,
            image: image,
            x0: x0,
            y0: y0,
            width: templateWidth,
            height: templateHeight,
            dxRange: Array((coarse.dx - refineRadius)...(coarse.dx + refineRadius)),
            dyRange: Array((coarse.dy - refineRadius)...(coarse.dy + refineRadius)),
            templateStats: templateStats
        )

        let warning = refined.score < 0.45 ? "Low confidence match; try a sharper, more recognizable zone." : nil
        return AlignmentResult(
            offset: CGSize(width: -refined.dx, height: -refined.dy),
            confidence: max(0, min(1, refined.score)),
            warning: warning
        )
    }

    private struct RegionStats {
        var mean: Double
        var variance: Double
        var stdDev: Double
    }

    private struct Match {
        var dx: Int
        var dy: Int
        var score: Double
    }

    private func stats(in image: LumaImage, x: Int, y: Int, width: Int, height: Int) -> RegionStats {
        let count = width * height
        var sum = 0.0
        var sumSquares = 0.0

        for yy in y..<(y + height) {
            for xx in x..<(x + width) {
                let value = image[xx, yy]
                sum += value
                sumSquares += value * value
            }
        }

        let mean = sum / Double(count)
        let variance = max(0, sumSquares / Double(count) - mean * mean)
        return RegionStats(mean: mean, variance: variance, stdDev: sqrt(variance))
    }

    private func bestMatch(
        anchor: LumaImage,
        image: LumaImage,
        x0: Int,
        y0: Int,
        width: Int,
        height: Int,
        dxRange: [Int],
        dyRange: [Int],
        templateStats: RegionStats
    ) -> Match {
        var best = Match(dx: 0, dy: 0, score: -.infinity)

        for dy in dyRange {
            let candidateY = y0 + dy
            guard candidateY >= 0, candidateY + height <= image.height else { continue }

            for dx in dxRange {
                let candidateX = x0 + dx
                guard candidateX >= 0, candidateX + width <= image.width else { continue }

                let candidateStats = stats(in: image, x: candidateX, y: candidateY, width: width, height: height)
                guard candidateStats.stdDev > 0.00001 else { continue }

                var numerator = 0.0
                for yy in 0..<height {
                    for xx in 0..<width {
                        let a = anchor[x0 + xx, y0 + yy] - templateStats.mean
                        let b = image[candidateX + xx, candidateY + yy] - candidateStats.mean
                        numerator += a * b
                    }
                }

                let denominator = Double(width * height) * templateStats.stdDev * candidateStats.stdDev
                let score = denominator > 0 ? numerator / denominator : -.infinity
                if score > best.score {
                    best = Match(dx: dx, dy: dy, score: score)
                }
            }
        }

        return best
    }
}
