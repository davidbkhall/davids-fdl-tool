import Foundation
import SwiftUI
import UniformTypeIdentifiers

@MainActor
class ViewerViewModel: ObservableObject {
    // Document state
    @Published var loadedDocument: FDLDocument?
    @Published var validationResult: ValidationResult?
    @Published var loadedFileName: String?
    @Published var loadedFilePath: String?
    @Published var rawJSON: String?

    // Image overlay state
    @Published var referenceImage: NSImage?
    @Published var referenceImagePath: String?
    @Published var overlayPNGBase64: String?
    @Published var showLabels = true
    @Published var overlayOpacity: Double = 1.0
    @Published var useNativeOverlay = true
    @Published var isGeneratingOverlay = false

    // UI state
    @Published var errorMessage: String?

    // MARK: - Open FDL

    func openFile(pythonBridge: PythonBridge) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType.json]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "Select an FDL JSON file"

        if panel.runModal() == .OK, let url = panel.url {
            loadFromURL(url, pythonBridge: pythonBridge)
        }
    }

    func loadFromURL(_ url: URL, pythonBridge: PythonBridge) {
        loadedFileName = url.lastPathComponent
        loadedFilePath = url.path

        // Clear previous state
        referenceImage = nil
        referenceImagePath = nil
        overlayPNGBase64 = nil

        do {
            let data = try Data(contentsOf: url)
            rawJSON = String(data: data, encoding: .utf8)
        } catch {
            errorMessage = "Failed to read file: \(error.localizedDescription)"
            return
        }

        Task {
            do {
                // Parse
                let parseResponse = try await pythonBridge.callForResult("fdl.parse", params: [
                    "path": url.path,
                ])
                if let fdlDict = parseResponse["fdl"] as? [String: Any] {
                    let data = try JSONSerialization.data(withJSONObject: fdlDict)
                    loadedDocument = try JSONDecoder().decode(FDLDocument.self, from: data)
                }

                // Validate
                let valResponse = try await pythonBridge.callForResult("fdl.validate", params: [
                    "path": url.path,
                ])
                let valData = try JSONSerialization.data(withJSONObject: valResponse)
                validationResult = try JSONDecoder().decode(ValidationResult.self, from: valData)
            } catch {
                errorMessage = "Failed to process FDL: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Load from Library Entry

    func loadFromEntry(_ entry: FDLEntry, pythonBridge: PythonBridge) {
        let filePath = LibraryStore.projectDirectoryURL(projectID: entry.projectID)
            .appendingPathComponent("\(entry.id).fdl.json")
        loadFromURL(filePath, pythonBridge: pythonBridge)
    }

    // MARK: - Reference Image

    func openReferenceImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image, .png, .jpeg, .tiff]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "Select a reference image"

        if panel.runModal() == .OK, let url = panel.url {
            loadReferenceImage(from: url)
        }
    }

    func loadReferenceImage(from url: URL) {
        guard let image = NSImage(contentsOf: url) else {
            errorMessage = "Failed to load image: \(url.lastPathComponent)"
            return
        }
        referenceImage = image
        referenceImagePath = url.path
        overlayPNGBase64 = nil
    }

    func clearReferenceImage() {
        referenceImage = nil
        referenceImagePath = nil
        overlayPNGBase64 = nil
    }

    // MARK: - Python Overlay Generation

    func generatePythonOverlay(pythonBridge: PythonBridge) {
        guard let imagePath = referenceImagePath, let rawJSON = rawJSON else { return }
        guard let fdlDict = try? JSONSerialization.jsonObject(with: Data(rawJSON.utf8)) as? [String: Any] else { return }

        isGeneratingOverlay = true
        Task {
            do {
                let response = try await pythonBridge.callForResult("image.load_and_overlay", params: [
                    "image_path": imagePath,
                    "fdl_data": fdlDict,
                ])
                overlayPNGBase64 = response["png_base64"] as? String
                useNativeOverlay = false
            } catch {
                errorMessage = "Overlay generation failed: \(error.localizedDescription)"
            }
            isGeneratingOverlay = false
        }
    }

    // MARK: - Export Overlay

    func exportOverlay(pythonBridge: PythonBridge) {
        guard referenceImagePath != nil else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "overlay_\(loadedFileName ?? "fdl").png"

        guard panel.runModal() == .OK, let dest = panel.url else { return }

        // If we have a Python-generated overlay, use it; otherwise generate one
        if let b64 = overlayPNGBase64, let data = Data(base64Encoded: b64) {
            do {
                try data.write(to: dest)
            } catch {
                errorMessage = "Export failed: \(error.localizedDescription)"
            }
        } else {
            guard let imagePath = referenceImagePath, let rawJSON = rawJSON else { return }
            guard let fdlDict = try? JSONSerialization.jsonObject(with: Data(rawJSON.utf8)) as? [String: Any] else { return }

            Task {
                do {
                    let response = try await pythonBridge.callForResult("image.load_and_overlay", params: [
                        "image_path": imagePath,
                        "fdl_data": fdlDict,
                    ])
                    if let b64 = response["png_base64"] as? String, let data = Data(base64Encoded: b64) {
                        try data.write(to: dest)
                    }
                } catch {
                    errorMessage = "Export failed: \(error.localizedDescription)"
                }
            }
        }
    }

    // MARK: - Close

    func closeDocument() {
        loadedDocument = nil
        validationResult = nil
        loadedFileName = nil
        loadedFilePath = nil
        rawJSON = nil
        referenceImage = nil
        referenceImagePath = nil
        overlayPNGBase64 = nil
    }
}
