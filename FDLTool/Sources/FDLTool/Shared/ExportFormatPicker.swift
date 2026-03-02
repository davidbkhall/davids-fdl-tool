import SwiftUI

enum ExportFormat: String, CaseIterable, Identifiable {
    case json = "FDL JSON"
    case svg = "SVG"
    case png = "PNG"

    var id: String { rawValue }

    var fileExtension: String {
        switch self {
        case .json: return "fdl.json"
        case .svg: return "svg"
        case .png: return "png"
        }
    }
}

struct ExportFormatPicker: View {
    @Binding var selectedFormat: ExportFormat

    var body: some View {
        Picker("Format", selection: $selectedFormat) {
            ForEach(ExportFormat.allCases) { format in
                Text(format.rawValue).tag(format)
            }
        }
        .pickerStyle(.segmented)
    }
}
