import AliniereCore
import AppKit
import SwiftUI

struct SidebarView: View {
    @Bindable var model: AlignerViewModel
    @Binding var showingImporter: Bool
    let prepareExport: () -> Void
    let prepareVideoExport: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Spacer()
                Button {
                    showingImporter = true
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.bordered)
                .help("Import frames")
            }

            FrameRail(model: model)

            Divider()

            ControlsView(model: model, prepareExport: prepareExport, prepareVideoExport: prepareVideoExport)
                .frame(maxHeight: .infinity, alignment: .top)

            Text(model.statusMessage)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(.regularMaterial)
        .dropDestination(for: URL.self) { urls, _ in
            model.importImages(from: urls)
            return true
        }
    }
}

private struct FrameRail: View {
    private let rowHeight: CGFloat = 80
    private let rowSpacing: CGFloat = 10
    private let listVerticalPadding: CGFloat = 4

    @Bindable var model: AlignerViewModel
    @State private var draggedFrameID: UUID?
    @State private var dropTargetFrameID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Frames")
                    .font(.headline)
                Spacer()
            }

            if model.frames.isEmpty {
                ContentUnavailableView(
                    "No Frames",
                    systemImage: "photo.on.rectangle",
                    description: Text("Drop or import images.")
                )
                .frame(maxWidth: .infinity, minHeight: 130)
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(Array(model.frames.enumerated()), id: \.element.id) { index, frame in
                            FrameRailRow(
                                model: model,
                                frame: frame,
                                index: index,
                                draggedFrameID: $draggedFrameID,
                                dropTargetFrameID: $dropTargetFrameID
                            )
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(maxHeight: rowHeight * 4 + rowSpacing * 3 + listVerticalPadding)
            }
        }
    }

}

private struct FrameRailRow: View {
    @Bindable var model: AlignerViewModel
    let frame: AppImageFrame
    let index: Int
    let draggedFrameID: Binding<UUID?>
    let dropTargetFrameID: Binding<UUID?>

    var body: some View {
        HStack(spacing: 10) {
            ZStack(alignment: .topLeading) {
                Image(nsImage: frame.thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 82, height: 60)
                    .clipShape(.rect(cornerRadius: 8))

                Text("\(index + 1)")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(.black.opacity(0.68))
                    .clipShape(.rect(cornerRadius: 5))
                    .padding(6)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(frame.name)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)

                Text("Frame \(index + 1)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            Image(systemName: "line.3.horizontal")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Button {
                model.removeFrame(frame.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help("Remove frame")
            .accessibilityLabel("Remove frame \(index + 1)")
        }
        .padding(10)
        .frame(height: 80)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(backgroundFill)
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(borderColor, lineWidth: 1)
        }
        .contentShape(.rect)
        .onTapGesture {
            model.selectFrame(frame.id)
        }
        .onDrag {
            draggedFrameID.wrappedValue = frame.id
            return NSItemProvider(object: frame.id.uuidString as NSString)
        }
        .onDrop(
            of: [.text],
            delegate: FrameRailDropDelegate(
                targetFrameID: frame.id,
                model: model,
                draggedFrameID: draggedFrameID,
                dropTargetFrameID: dropTargetFrameID
            )
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Frame \(index + 1), \(frame.name)")
        .padding(.trailing, 18)
    }

    private var backgroundFill: some View {
        Group {
            if model.selectedFrameID == frame.id {
                Color.accentColor.opacity(0.12)
            } else if dropTargetFrameID.wrappedValue == frame.id {
                Color.accentColor.opacity(0.08)
            } else {
                Color.clear
            }
        }
    }

    private var borderColor: Color {
        if dropTargetFrameID.wrappedValue == frame.id {
            return .accentColor
        }
        return model.selectedFrameID == frame.id ? .accentColor : .secondary.opacity(0.45)
    }
}

@MainActor
private struct FrameRailDropDelegate: DropDelegate {
    let targetFrameID: UUID
    let model: AlignerViewModel
    let draggedFrameID: Binding<UUID?>
    let dropTargetFrameID: Binding<UUID?>

    func dropEntered(info: DropInfo) {
        guard let draggedID = draggedFrameID.wrappedValue,
              draggedID != targetFrameID
        else {
            return
        }
        dropTargetFrameID.wrappedValue = targetFrameID
        model.moveFrame(id: draggedID, before: targetFrameID, realign: false)
    }

    func dropExited(info: DropInfo) {
        if dropTargetFrameID.wrappedValue == targetFrameID {
            dropTargetFrameID.wrappedValue = nil
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedFrameID.wrappedValue = nil
        dropTargetFrameID.wrappedValue = nil
        model.refreshAlignmentAfterFrameOrderChange()
        return true
    }
}

private struct ControlsView: View {
    @Bindable var model: AlignerViewModel
    let prepareExport: () -> Void
    let prepareVideoExport: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            AlignmentControls(model: model)
            CropControls(model: model)
            TimingControls(model: model)

            Divider()

            ExportControls(
                model: model,
                prepareExport: prepareExport,
                prepareVideoExport: prepareVideoExport
            )
        }
    }
}

private struct AlignmentControls: View {
    @Bindable var model: AlignerViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Alignment")
                    .font(.headline)
                Spacer()
                Picker("", selection: Binding(
                    get: { model.alignmentMode },
                    set: { model.setAlignmentMode($0) }
                )) {
                    Text("Auto").tag(AlignmentMode.automaticPatch)
                    Text("Manual").tag(AlignmentMode.manualPoints)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 160)
                .disabled(model.frames.isEmpty)
            }

            if model.alignmentMode == .automaticPatch {
                Text("Drag on the image to draw the alignment zone.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(model.frames.isEmpty
                    ? "Click on the image to select a reference point"
                    : "Select each frame, then click its matching reference point.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct CropControls: View {
    @Bindable var model: AlignerViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Crop")
                    .font(.headline)
                Spacer()
                Picker("", selection: $model.cropPolicy) {
                    Text("Auto").tag(CropPolicy.commonArea)
                    Text("Manual").tag(CropPolicy.manual)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 160)
                .onChange(of: model.cropPolicy) {
                    if model.cropPolicy == .manual {
                        model.beginManualCrop()
                    } else {
                        model.useAutomaticCrop()
                    }
                }
            }

            if let crop = model.exportCropRect {
                Text("Crop \(Int(crop.width)) x \(Int(crop.height))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            if model.cropPolicy == .manual {
                CropInsetControls(model: model)
            }
        }
    }
}

private struct TimingControls: View {
    @Bindable var model: AlignerViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Frame duration")
                Slider(value: $model.globalDelay, in: 0.04...0.5, step: 0.01)
                    .accessibilityLabel("Frame duration")
                Text(model.globalDelay, format: .number.precision(.fractionLength(2)))
                    .monospacedDigit()
                    .frame(width: 44, alignment: .trailing)
            }
            .onChange(of: model.globalDelay) {
                model.setGlobalDelay(model.globalDelay)
            }

            HStack {
                Text("MP4 length")
                Slider(value: $model.mp4Duration, in: 1...15, step: 0.5)
                    .accessibilityLabel("MP4 length")
                Text("\(model.mp4Duration, format: .number.precision(.fractionLength(model.mp4Duration.truncatingRemainder(dividingBy: 1) == 0 ? 0 : 1)))s")
                    .monospacedDigit()
                    .frame(width: 44, alignment: .trailing)
            }
        }
    }
}

private struct ExportControls: View {
    @Bindable var model: AlignerViewModel
    let prepareExport: () -> Void
    let prepareVideoExport: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Export")
                    .font(.headline)

                Text("Choose GIF for easy sharing or MP4 for better quality.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 8) {
                Button {
                    prepareExport()
                } label: {
                    Label("Export GIF", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.large)
                .disabled(model.frames.count < 2)
                .help("Export GIF")

                Button {
                    prepareVideoExport()
                } label: {
                    Label("Export MP4", systemImage: "film")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.large)
                .disabled(model.frames.count < 2)
                .help("Export MP4")
            }
        }
    }
}

private struct CropInsetControls: View {
    @Bindable var model: AlignerViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                CropInsetField(title: "Left", edge: .left, model: model)
                CropInsetField(title: "Right", edge: .right, model: model)
            }
            HStack(spacing: 8) {
                CropInsetField(title: "Top", edge: .top, model: model)
                CropInsetField(title: "Bottom", edge: .bottom, model: model)
            }
        }
    }
}

private struct CropInsetField: View {
    let title: String
    let edge: CropEdge
    @Bindable var model: AlignerViewModel
    @State private var draftValue = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            TextField("", text: $draftValue)
            .focused($isFocused)
            .multilineTextAlignment(.trailing)
            .frame(width: 52)
            .textFieldStyle(.roundedBorder)
            .onChange(of: draftValue) {
                draftValue = sanitized(draftValue)
            }
            .onAppear {
                syncDraft()
            }
            .onChange(of: currentValue) {
                if !isFocused {
                    syncDraft()
                }
            }
            .onChange(of: isFocused) {
                if !isFocused {
                    commitDraft()
                    syncDraft()
                }
            }
            .onSubmit {
                commitDraft()
                syncDraft()
            }

            VStack(spacing: 1) {
                Button {
                    adjust(by: 1)
                } label: {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 9, weight: .semibold))
                        .frame(width: 16, height: 12)
                }
                .buttonStyle(.borderless)
                .help("Increase \(title.lowercased()) crop")

                Button {
                    adjust(by: -1)
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .frame(width: 16, height: 12)
                }
                .buttonStyle(.borderless)
                .help("Decrease \(title.lowercased()) crop")
            }
        }
    }

    private var currentValue: Double {
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

    private func adjust(by amount: Double) {
        model.setManualCropInset(edge, value: currentValue + amount)
        syncDraft()
    }

    private func commitDraft() {
        guard let value = Double(draftValue) else { return }
        model.setManualCropInset(edge, value: value.rounded())
    }

    private func syncDraft() {
        draftValue = String(Int(currentValue.rounded()))
    }

    private func sanitized(_ value: String) -> String {
        var result = ""
        for (index, character) in value.enumerated() {
            if character.isNumber {
                result.append(character)
            } else if character == "-" && index == 0 && result.isEmpty {
                result.append(character)
            }
        }
        return String(result.prefix(6))
    }
}
