import SwiftUI

enum InputMode: String, CaseIterable {
    case importJSON = "Import JSON"
    case manual = "Manual Entry"
}

/// Segmented control for switching between JSON import and manual entry modes.
struct FDLImportOrManualToggle: View {
    @Binding var mode: InputMode

    var body: some View {
        Picker("Input Mode", selection: $mode) {
            ForEach(InputMode.allCases, id: \.self) { mode in
                Text(mode.rawValue).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }
}
