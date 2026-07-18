import AliniereCore
import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var model = AlignerViewModel()
    @State private var showingImporter = false

    var body: some View {
        HSplitView {
            SidebarView(
                model: model,
                showingImporter: $showingImporter,
                prepareExport: exportGIF,
                prepareVideoExport: exportMP4
            )
            .frame(minWidth: 330, idealWidth: 360, maxWidth: 440)

            WorkspaceView(model: model)
                .frame(minWidth: 760)
        }
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: model.supportedTypes,
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                model.importImages(from: urls)
            }
        }
        .fileDialogMessage("Choose frame images.")
        .fileDialogConfirmationLabel("Import Frames")
        .alert("Something went sideways", isPresented: Binding(
            get: { model.exportError != nil },
            set: { if !$0 { model.exportError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.exportError ?? "")
        }
    }

    private func exportGIF() {
        guard let url = saveURL(defaultName: "wiggly.gif", contentType: .gif) else {
            return
        }
        model.exportGIF(to: url)
    }

    private func exportMP4() {
        guard let url = saveURL(defaultName: "wiggly.mp4", contentType: .mpeg4Movie) else {
            return
        }
        Task {
            await model.exportVideo(to: url)
        }
    }

    private func saveURL(defaultName: String, contentType: UTType) -> URL? {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [contentType]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.nameFieldStringValue = sanitizeFilename(defaultName)
        panel.title = "Export \(contentType == .gif ? "GIF" : "MP4")"
        panel.prompt = "Export"

        return panel.runModal() == .OK ? panel.url : nil
    }

    private func sanitizeFilename(_ text: String) -> String {
        let invalid = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleaned = trimmed.unicodeScalars.map { scalar -> Character in
            invalid.contains(scalar) ? "-" : Character(scalar)
        }
        let result = String(cleaned).trimmingCharacters(in: .punctuationCharacters)
        return result.isEmpty ? "wiggly" : result
    }
}
