import CoreGraphics
import Foundation

public enum CropCalculator {
    public static func commonCropRect(
        imageSize: CGSize,
        offsets: [CGSize]
    ) -> CGRect {
        guard !offsets.isEmpty else {
            return CGRect(origin: .zero, size: imageSize).integral
        }

        var intersection = CGRect(origin: .zero, size: imageSize)
        for offset in offsets {
            let frameRect = CGRect(
                x: offset.width,
                y: offset.height,
                width: imageSize.width,
                height: imageSize.height
            )
            intersection = intersection.intersection(frameRect)
        }

        return intersection.integral
    }

    public static func alignedBoundsRect(
        imageSize: CGSize,
        offsets: [CGSize]
    ) -> CGRect {
        guard !offsets.isEmpty else {
            return CGRect(origin: .zero, size: imageSize).integral
        }

        var bounds = CGRect.null
        for offset in offsets {
            let frameRect = CGRect(
                x: offset.width,
                y: offset.height,
                width: imageSize.width,
                height: imageSize.height
            )
            bounds = bounds.union(frameRect)
        }

        return bounds.integral
    }

    public static func clampedManualCropRect(
        _ manualRect: CGRect?,
        imageSize: CGSize,
        offsets: [CGSize]
    ) -> CGRect {
        let common = commonCropRect(imageSize: imageSize, offsets: offsets)
        guard let manualRect else {
            return common
        }

        let clamped = manualRect.standardized.integral.intersection(common)
        guard !clamped.isNull, clamped.width >= 1, clamped.height >= 1 else {
            return common
        }
        return clamped.integral
    }

    public static func cropRect(
        commonRect: CGRect,
        insets: CropInsets
    ) -> CGRect {
        let maxHorizontalInset = max(0, commonRect.width - 1)
        let maxVerticalInset = max(0, commonRect.height - 1)
        let left = insets.left
        let right = min(insets.right, maxHorizontalInset - left)
        let top = insets.top
        let bottom = min(insets.bottom, maxVerticalInset - top)

        return CGRect(
            x: commonRect.minX + left,
            y: commonRect.minY + top,
            width: commonRect.width - left - right,
            height: commonRect.height - top - bottom
        ).integral
    }

    public static func insets(
        commonRect: CGRect,
        cropRect: CGRect
    ) -> CropInsets {
        let crop = cropRect.standardized.integral
        guard crop.width >= 1, crop.height >= 1 else {
            return .zero
        }

        return CropInsets(
            left: crop.minX - commonRect.minX,
            right: commonRect.maxX - crop.maxX,
            top: crop.minY - commonRect.minY,
            bottom: commonRect.maxY - crop.maxY
        )
    }
}
