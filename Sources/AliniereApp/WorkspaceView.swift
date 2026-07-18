import AliniereCore
import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct WorkspaceView: View {
    @Bindable var model: AlignerViewModel

    var body: some View {
        HSplitView {
            AlignmentEditorView(model: model)
                .frame(minWidth: 420)

            PreviewPane(model: model)
                .frame(minWidth: 320)
        }
        .frame(minHeight: 360)
        .dropDestination(for: URL.self) { urls, _ in
            model.importImages(from: urls)
            return true
        }
    }
}

private struct AlignmentEditorView: View {
    @Bindable var model: AlignerViewModel
    @State private var dragStart: CGPoint?
    @State private var draftRect: CGRect?
    @State private var viewportOffset: CGSize = .zero

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(model.alignmentMode == .automaticPatch ? "Alignment Zone" : "Reference Point")
                    .font(.headline)
                Spacer()
                ZoomControls(value: $model.alignmentZoom)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)

            GeometryReader { proxy in
                ZStack {
                    Color.black.opacity(0.92)
                    if let frame = displayedFrame {
                        let imageSize = CGSize(width: frame.cgImage.width, height: frame.cgImage.height)
                        let imageRect = fittedRect(
                            imageSize: imageSize,
                            container: proxy.size,
                            zoom: model.alignmentZoom
                        ).offsetBy(dx: viewportOffset.width, dy: viewportOffset.height)
                        Image(nsImage: NSImage(
                            cgImage: frame.cgImage,
                            size: imageSize
                        ))
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: imageRect.width, height: imageRect.height)
                            .position(x: imageRect.midX, y: imageRect.midY)

                        if model.alignmentMode == .automaticPatch {
                            SelectionOverlay(
                                imageRect: imageRect,
                                imageSize: imageSize,
                                selectionRect: draftRect ?? model.selectionRect
                            )
                        } else {
                            ManualPointOverlay(
                                imageRect: imageRect,
                                imageSize: imageSize,
                                point: model.manualPoints[frame.id]
                            )
                        }
                    } else {
                        ContentUnavailableView(
                            "Import Frames",
                            systemImage: "photo.badge.plus",
                            description: Text("Select a detailed zone for automatic alignment.")
                        )
                    }
                }
                .viewportZoom { delta, location in
                    applyZoom(delta: delta, at: location, containerSize: proxy.size)
                }
                .contentShape(Rectangle())
                .onTapGesture(count: 2) {
                    resetViewport()
                }
                .gesture(editorGesture(in: proxy.size))
            }
            .clipShape(.rect(cornerRadius: 8))
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
            .onChange(of: model.selectedFrameID) {
                resetViewport()
            }
        }
    }

    private var displayedFrame: AppImageFrame? {
        let index = model.selectedFrameIndex
        guard model.frames.indices.contains(index) else { return nil }
        return model.frames[index]
    }

    private func editorGesture(in containerSize: CGSize) -> AnyGesture<DragGesture.Value> {
        AnyGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    guard model.alignmentMode == .automaticPatch,
                          let displayedFrame
                    else {
                        return
                    }
                    let imageSize = CGSize(width: displayedFrame.cgImage.width, height: displayedFrame.cgImage.height)
                    let imageRect = fittedRect(imageSize: imageSize, container: containerSize, zoom: model.alignmentZoom)
                        .offsetBy(dx: viewportOffset.width, dy: viewportOffset.height)
                    let start = dragStart ?? value.startLocation
                    dragStart = start
                    let rect = CGRect(
                        x: min(start.x, value.location.x),
                        y: min(start.y, value.location.y),
                        width: abs(value.location.x - start.x),
                        height: abs(value.location.y - start.y)
                    )
                    draftRect = viewRectToImageRect(rect, imageRect: imageRect, imageSize: imageSize)
                }
                .onEnded { value in
                    if model.alignmentMode == .automaticPatch {
                        if let selectionRect = draftRect ?? automaticSelectionRect(from: value, in: containerSize),
                           selectionRect.width >= 8,
                           selectionRect.height >= 8,
                           let displayedFrame {
                            model.updateSelection(selectionRect, anchorFrameID: displayedFrame.id)
                        }
                    } else if let displayedFrame {
                        let imageSize = CGSize(width: displayedFrame.cgImage.width, height: displayedFrame.cgImage.height)
                        let imageRect = fittedRect(imageSize: imageSize, container: containerSize, zoom: model.alignmentZoom)
                            .offsetBy(dx: viewportOffset.width, dy: viewportOffset.height)
                        let point = viewPointToImagePoint(value.location, imageRect: imageRect, imageSize: imageSize)
                        model.setManualPoint(point, for: displayedFrame.id)
                    }
                    dragStart = nil
                    draftRect = nil
                }
        )
    }

    private func automaticSelectionRect(from value: DragGesture.Value, in containerSize: CGSize) -> CGRect? {
        guard let displayedFrame else { return nil }
        let imageSize = CGSize(width: displayedFrame.cgImage.width, height: displayedFrame.cgImage.height)
        let imageRect = fittedRect(imageSize: imageSize, container: containerSize, zoom: model.alignmentZoom)
            .offsetBy(dx: viewportOffset.width, dy: viewportOffset.height)
        let start = dragStart ?? value.startLocation
        let viewRect = CGRect(
            x: min(start.x, value.location.x),
            y: min(start.y, value.location.y),
            width: abs(value.location.x - start.x),
            height: abs(value.location.y - start.y)
        )
        return viewRectToImageRect(viewRect, imageRect: imageRect, imageSize: imageSize)
    }

    private func applyZoom(delta: Double, at location: CGPoint?, containerSize: CGSize) {
        guard let displayedFrame else {
            model.alignmentZoom = clampZoom(model.alignmentZoom * delta)
            return
        }

        let imageSize = CGSize(width: displayedFrame.cgImage.width, height: displayedFrame.cgImage.height)
        let oldZoom = model.alignmentZoom
        let newZoom = clampZoom(oldZoom * delta)
        guard newZoom != oldZoom else { return }

        guard let location else {
            model.alignmentZoom = newZoom
            return
        }

        let oldBaseRect = fittedRect(imageSize: imageSize, container: containerSize, zoom: oldZoom)
            .offsetBy(dx: viewportOffset.width, dy: viewportOffset.height)
        guard oldBaseRect.contains(location) else {
            model.alignmentZoom = newZoom
            return
        }

        let anchorPoint = viewPointToImagePoint(location, imageRect: oldBaseRect, imageSize: imageSize)
        let newBaseRect = fittedRect(imageSize: imageSize, container: containerSize, zoom: newZoom)
        viewportOffset = CGSize(
            width: location.x - newBaseRect.minX - anchorPoint.x / imageSize.width * newBaseRect.width,
            height: location.y - newBaseRect.minY - anchorPoint.y / imageSize.height * newBaseRect.height
        )
        model.alignmentZoom = newZoom
    }

    private func resetViewport() {
        viewportOffset = .zero
        model.alignmentZoom = 1
    }
}

private struct SelectionOverlay: View {
    let imageRect: CGRect
    let imageSize: CGSize
    let selectionRect: CGRect?

    var body: some View {
        if let selectionRect {
            let rect = imageRectToViewRect(selectionRect, imageRect: imageRect, imageSize: imageSize)
            Rectangle()
                .stroke(.yellow, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                .background(.yellow.opacity(0.12))
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)
        }
    }
}

private struct ManualPointOverlay: View {
    let imageRect: CGRect
    let imageSize: CGSize
    let point: CGPoint?

    var body: some View {
        if let point {
            let viewPoint = imagePointToViewPoint(point, imageRect: imageRect, imageSize: imageSize)
            ZStack {
                Circle()
                    .stroke(.yellow, lineWidth: 2)
                    .frame(width: 18, height: 18)
                Rectangle()
                    .fill(.yellow)
                    .frame(width: 24, height: 1)
                Rectangle()
                    .fill(.yellow)
                    .frame(width: 1, height: 24)
            }
            .position(viewPoint)
        }
    }
}

private struct ZoomControls: View {
    @Binding var value: Double

    var body: some View {
        HStack(spacing: 6) {
            Button {
                value = max(0.1, value - 0.25)
            } label: {
                Image(systemName: "minus.magnifyingglass")
            }
            .disabled(value <= 0.1)
            .help("Zoom out")

            Text("\(Int((value * 100).rounded()))%")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .center)

            Button {
                value = min(4, value + 0.25)
            } label: {
                Image(systemName: "plus.magnifyingglass")
            }
            .disabled(value >= 4)
            .help("Zoom in")
        }
        .buttonStyle(.borderless)
    }
}

private struct ViewportZoomModifier: ViewModifier {
    let onZoom: (Double, CGPoint?) -> Void

    func body(content: Content) -> some View {
        content.background(ZoomEventMonitor(onZoom: onZoom))
    }
}

private extension View {
    func viewportZoom(onZoom: @escaping (Double, CGPoint?) -> Void) -> some View {
        modifier(ViewportZoomModifier(onZoom: onZoom))
    }
}

private struct ZoomEventMonitor: NSViewRepresentable {
    let onZoom: (Double, CGPoint?) -> Void

    func makeNSView(context: Context) -> ZoomEventMonitorView {
        ZoomEventMonitorView()
    }

    func updateNSView(_ nsView: ZoomEventMonitorView, context: Context) {
        nsView.onZoom = onZoom
    }
}

private final class ZoomEventMonitorView: NSView {
    var onZoom: ((Double, CGPoint?) -> Void)?
    private var scrollMonitor: Any?
    private var magnifyMonitor: Any?

    override var isFlipped: Bool {
        true
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        guard let superview else { return }
        frame = superview.bounds
        autoresizingMask = [.width, .height]
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else {
            removeMonitors()
            return
        }
        installMonitors()
    }

    deinit {
        removeMonitors()
    }

    private func installMonitors() {
        guard scrollMonitor == nil, magnifyMonitor == nil else { return }

        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel]) { [weak self] event in
            guard let self, self.shouldHandle(event) else {
                return event
            }
            let amount = 1 + (abs(event.scrollingDeltaY) / 240.0)
            self.onZoom?(event.scrollingDeltaY > 0 ? 1 / amount : amount, self.convert(event.locationInWindow, from: nil))
            return nil
        }

        magnifyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.magnify]) { [weak self] event in
            guard let self, self.shouldHandle(event) else {
                return event
            }
            self.onZoom?(1 + Double(event.magnification), self.convert(event.locationInWindow, from: nil))
            return nil
        }
    }

    private func removeMonitors() {
        if let scrollMonitor {
            NSEvent.removeMonitor(scrollMonitor)
            self.scrollMonitor = nil
        }
        if let magnifyMonitor {
            NSEvent.removeMonitor(magnifyMonitor)
            self.magnifyMonitor = nil
        }
    }

    private func shouldHandle(_ event: NSEvent) -> Bool {
        guard let window else { return false }
        let location = convert(event.locationInWindow, from: nil)
        return bounds.contains(location) && window.contentView != nil
    }
}

private func clampZoom(_ value: Double) -> Double {
    min(4, max(0.1, value))
}

private struct PreviewPane: View {
    @Bindable var model: AlignerViewModel
    @State private var panStartOffset: CGSize?
    @State private var viewportOffset: CGSize = .zero

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Loop Preview")
                    .font(.headline)
                Button {
                    model.isPlaying.toggle()
                } label: {
                    Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                }
                .buttonStyle(.borderless)
                .help(model.isPlaying ? "Pause preview" : "Play preview")
                Spacer()
                if let crop = model.exportCropRect {
                    Text("\(Int(crop.width)) x \(Int(crop.height))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                ZoomControls(value: $model.previewZoom)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)

            GeometryReader { proxy in
                ZStack {
                    Color.black.opacity(0.92)
                    if let frame = model.previewFrame,
                       let crop = model.exportCropRect {
                        let commonCrop = model.commonCropRect
                        let displayedCrop = displayedPreviewRect(for: frame)
                        PreviewImage(
                            frame: frame,
                            cropRect: displayedCrop,
                            containerSize: proxy.size,
                            zoom: model.previewZoom,
                            viewportOffset: viewportOffset
                        )
                        if let commonCrop {
                            CropOverlay(
                                model: model,
                                cropRect: crop,
                                displayedCropRect: displayedCrop,
                                commonCropRect: commonCrop,
                                containerSize: proxy.size,
                                zoom: model.previewZoom,
                                viewportOffset: viewportOffset
                            )
                        }
                    } else {
                        ContentUnavailableView(
                            "No Preview",
                            systemImage: "play.rectangle",
                            description: Text("Import and align at least two frames.")
                        )
                    }
                }
                .viewportZoom { delta, location in
                    applyZoom(delta: delta, at: location, containerSize: proxy.size)
                }
                .onTapGesture(count: 2) {
                    resetViewport()
                }
                .gesture(panGesture())
            }
            .clipShape(.rect(cornerRadius: 8))
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
            .onReceive(Timer.publish(every: max(model.globalDelay, 0.04), on: .main, in: .common).autoconnect()) { _ in
                if model.isPlaying {
                    model.advancePlayback()
                }
            }
        }
    }

    private func applyZoom(delta: Double, at location: CGPoint?, containerSize: CGSize) {
        guard let frame = model.previewFrame else {
            model.previewZoom = clampZoom(model.previewZoom * delta)
            return
        }

        let imageSize = displayedPreviewRect(for: frame).size
        let oldZoom = model.previewZoom
        let newZoom = clampZoom(oldZoom * delta)
        guard newZoom != oldZoom else { return }

        guard let location else {
            model.previewZoom = newZoom
            return
        }

        let oldBaseRect = fittedRect(imageSize: imageSize, container: containerSize, zoom: oldZoom)
            .offsetBy(dx: viewportOffset.width, dy: viewportOffset.height)
        guard oldBaseRect.contains(location) else {
            model.previewZoom = newZoom
            return
        }

        let anchorPoint = viewPointToImagePoint(location, imageRect: oldBaseRect, imageSize: imageSize)
        let newBaseRect = fittedRect(imageSize: imageSize, container: containerSize, zoom: newZoom)
        viewportOffset = CGSize(
            width: location.x - newBaseRect.minX - anchorPoint.x / imageSize.width * newBaseRect.width,
            height: location.y - newBaseRect.minY - anchorPoint.y / imageSize.height * newBaseRect.height
        )
        model.previewZoom = newZoom
    }

    private func displayedPreviewRect(for frame: AppImageFrame) -> CGRect {
        let fullFrameRect = CGRect(
            x: 0,
            y: 0,
            width: frame.cgImage.width,
            height: frame.cgImage.height
        )
        guard let cropRect = model.exportCropRect else { return fullFrameRect }
        guard model.cropPolicy == .manual else { return cropRect }

        let alignedBounds = model.alignedBoundsRect ?? fullFrameRect
        return alignedBounds.union(cropRect).integral
    }

    private func resetViewport() {
        viewportOffset = .zero
        panStartOffset = nil
        model.previewZoom = 1
    }

    private func panGesture() -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard model.previewZoom > 1.01 else { return }
                if panStartOffset == nil {
                    panStartOffset = viewportOffset
                }
                let startOffset = panStartOffset ?? .zero
                viewportOffset = CGSize(
                    width: startOffset.width + value.translation.width,
                    height: startOffset.height + value.translation.height
                )
            }
            .onEnded { _ in
                panStartOffset = nil
            }
    }
}

private struct PreviewImage: View {
    let frame: AppImageFrame
    let cropRect: CGRect
    let containerSize: CGSize
    let zoom: Double
    let viewportOffset: CGSize

    var body: some View {
        let fitted = fittedRect(imageSize: cropRect.size, container: containerSize, zoom: zoom)
            .offsetBy(dx: viewportOffset.width, dy: viewportOffset.height)
        let scale = fitted.width / cropRect.width
        ZStack(alignment: .topLeading) {
            Image(nsImage: NSImage(cgImage: frame.cgImage, size: CGSize(width: frame.cgImage.width, height: frame.cgImage.height)))
                .resizable()
                .interpolation(.high)
                .frame(
                    width: CGFloat(frame.cgImage.width) * scale,
                    height: CGFloat(frame.cgImage.height) * scale
                )
                .offset(
                    x: (frame.offset.width - cropRect.minX) * scale,
                    y: (frame.offset.height - cropRect.minY) * scale
                )
        }
        .frame(width: fitted.width, height: fitted.height, alignment: .topLeading)
        .clipped()
        .position(x: fitted.midX, y: fitted.midY)
    }
}

private struct CropOverlay: View {
    @Bindable var model: AlignerViewModel
    let cropRect: CGRect
    let displayedCropRect: CGRect
    let commonCropRect: CGRect
    let containerSize: CGSize
    let zoom: Double
    let viewportOffset: CGSize

    var body: some View {
        let fitted = fittedRect(imageSize: displayedCropRect.size, container: containerSize, zoom: zoom)
            .offsetBy(dx: viewportOffset.width, dy: viewportOffset.height)
        let localCrop = cropRect.offsetBy(dx: -displayedCropRect.minX, dy: -displayedCropRect.minY)
        let cropViewRect = imageRectToViewRect(localCrop, imageRect: fitted, imageSize: displayedCropRect.size)
        ZStack {
            if model.cropPolicy == .manual {
                Rectangle()
                    .stroke(.white.opacity(0.95), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                    .frame(width: cropViewRect.width, height: cropViewRect.height)
                    .position(x: cropViewRect.midX, y: cropViewRect.midY)
                    .allowsHitTesting(false)

                CropEdgeHandle(
                    edge: .left,
                    cropRect: cropViewRect,
                    displayRect: fitted,
                    displayedCropRect: displayedCropRect,
                    model: model,
                    commonCropRect: commonCropRect
                )
                CropEdgeHandle(
                    edge: .right,
                    cropRect: cropViewRect,
                    displayRect: fitted,
                    displayedCropRect: displayedCropRect,
                    model: model,
                    commonCropRect: commonCropRect
                )
                CropEdgeHandle(
                    edge: .top,
                    cropRect: cropViewRect,
                    displayRect: fitted,
                    displayedCropRect: displayedCropRect,
                    model: model,
                    commonCropRect: commonCropRect
                )
                CropEdgeHandle(
                    edge: .bottom,
                    cropRect: cropViewRect,
                    displayRect: fitted,
                    displayedCropRect: displayedCropRect,
                    model: model,
                    commonCropRect: commonCropRect
                )
            } else {
                Rectangle()
                    .stroke(.white.opacity(0.85), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                    .frame(width: fitted.width, height: fitted.height)
                    .position(x: fitted.midX, y: fitted.midY)
                    .allowsHitTesting(false)
            }
        }
    }
}

private struct CropEdgeHandle: View {
    let edge: CropEdge
    let cropRect: CGRect
    let displayRect: CGRect
    let displayedCropRect: CGRect
    @Bindable var model: AlignerViewModel
    let commonCropRect: CGRect
    @State private var startInset: Double?

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.white.opacity(0.001))
                .frame(width: hitSize.width, height: hitSize.height)
                .position(edgePosition)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            if startInset == nil {
                                startInset = currentInset
                            }
                            let delta = pixelDelta(from: value.translation)
                            model.setManualCropInset(edge, value: (startInset ?? currentInset) + delta)
                        }
                        .onEnded { _ in
                            startInset = nil
                        }
                )
                .help(helpText)
        }
    }

    private var visibleSize: CGSize {
        switch edge {
        case .left, .right:
            CGSize(width: 1, height: max(24, cropRect.height))
        case .top, .bottom:
            CGSize(width: max(24, cropRect.width), height: 1)
        }
    }

    private var hitSize: CGSize {
        switch edge {
        case .left, .right:
            CGSize(width: 18, height: max(24, cropRect.height))
        case .top, .bottom:
            CGSize(width: max(24, cropRect.width), height: 18)
        }
    }

    private var edgePosition: CGPoint {
        switch edge {
        case .left:
            CGPoint(x: cropRect.minX, y: cropRect.midY)
        case .right:
            CGPoint(x: cropRect.maxX, y: cropRect.midY)
        case .top:
            CGPoint(x: cropRect.midX, y: cropRect.minY)
        case .bottom:
            CGPoint(x: cropRect.midX, y: cropRect.maxY)
        }
    }

    private var currentInset: Double {
        switch edge {
        case .left:
            model.manualCropInsets.left
        case .right:
            model.manualCropInsets.right
        case .top:
            model.manualCropInsets.top
        case .bottom:
            model.manualCropInsets.bottom
        }
    }

    private var helpText: String {
        switch edge {
        case .left:
            "Drag to trim the left edge"
        case .right:
            "Drag to trim the right edge"
        case .top:
            "Drag to trim the top edge"
        case .bottom:
            "Drag to trim the bottom edge"
        }
    }

    private func pixelDelta(from translation: CGSize) -> Double {
        switch edge {
        case .left:
            return Double(translation.width / displayRect.width * displayedCropRect.width)
        case .right:
            return Double(-translation.width / displayRect.width * displayedCropRect.width)
        case .top:
            return Double(translation.height / displayRect.height * displayedCropRect.height)
        case .bottom:
            return Double(-translation.height / displayRect.height * displayedCropRect.height)
        }
    }
}

private func fittedRect(imageSize: CGSize, container: CGSize, zoom: Double = 1) -> CGRect {
    guard imageSize.width > 0, imageSize.height > 0, container.width > 0, container.height > 0 else {
        return .zero
    }
    let scale = min(container.width / imageSize.width, container.height / imageSize.height) * zoom
    let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
    return CGRect(
        x: (container.width - size.width) / 2,
        y: (container.height - size.height) / 2,
        width: size.width,
        height: size.height
    )
}

private func viewRectToImageRect(_ rect: CGRect, imageRect: CGRect, imageSize: CGSize) -> CGRect {
    let clipped = rect.intersection(imageRect)
    guard !clipped.isNull else { return .zero }
    return CGRect(
        x: (clipped.minX - imageRect.minX) / imageRect.width * imageSize.width,
        y: (clipped.minY - imageRect.minY) / imageRect.height * imageSize.height,
        width: clipped.width / imageRect.width * imageSize.width,
        height: clipped.height / imageRect.height * imageSize.height
    ).integral
}

private func imageRectToViewRect(_ rect: CGRect, imageRect: CGRect, imageSize: CGSize) -> CGRect {
    CGRect(
        x: imageRect.minX + rect.minX / imageSize.width * imageRect.width,
        y: imageRect.minY + rect.minY / imageSize.height * imageRect.height,
        width: rect.width / imageSize.width * imageRect.width,
        height: rect.height / imageSize.height * imageRect.height
    )
}

private func viewPointToImagePoint(_ point: CGPoint, imageRect: CGRect, imageSize: CGSize) -> CGPoint {
    let x = min(max(point.x, imageRect.minX), imageRect.maxX)
    let y = min(max(point.y, imageRect.minY), imageRect.maxY)
    return CGPoint(
        x: (x - imageRect.minX) / imageRect.width * imageSize.width,
        y: (y - imageRect.minY) / imageRect.height * imageSize.height
    )
}

private func imagePointToViewPoint(_ point: CGPoint, imageRect: CGRect, imageSize: CGSize) -> CGPoint {
    CGPoint(
        x: imageRect.minX + point.x / imageSize.width * imageRect.width,
        y: imageRect.minY + point.y / imageSize.height * imageRect.height
    )
}
