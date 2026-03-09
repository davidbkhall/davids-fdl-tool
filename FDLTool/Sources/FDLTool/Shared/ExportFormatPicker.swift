import SwiftUI

enum ExportFormat: String, CaseIterable, Identifiable {
    case json = "FDL JSON"
    case svg = "SVG"
    case png = "PNG"
    case pdf = "PDF"
    case tiff = "TIFF"
    case arriXML = "ARRI XML"
    case sonyXML = "Sony XML"

    var id: String { rawValue }

    var fileExtension: String {
        switch self {
        case .json: return "fdl"
        case .svg: return "svg"
        case .png: return "png"
        case .pdf: return "pdf"
        case .tiff: return "tiff"
        case .arriXML, .sonyXML: return "xml"
        }
    }
}

struct ExportFormatPicker: View {
    @Binding var selectedFormat: ExportFormat
    var options: [ExportFormat] = ExportFormat.allCases
    var compactMenuStyle: Bool = false

    var body: some View {
        Group {
            if compactMenuStyle {
                Picker("Format", selection: $selectedFormat) {
                    ForEach(options) { format in
                        Text(format.rawValue).tag(format)
                    }
                }
                .pickerStyle(.menu)
            } else {
                Picker("Format", selection: $selectedFormat) {
                    ForEach(options) { format in
                        Text(format.rawValue).tag(format)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
    }
}
