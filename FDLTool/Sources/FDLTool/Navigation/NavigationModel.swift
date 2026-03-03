import Foundation
import SwiftUI

enum Tool: String, CaseIterable, Identifiable {
    case library = "FDL Library"
    case chartGenerator = "Framing Charts"
    case viewer = "FDL Viewer"
    case clipID = "Clip ID"
    case cameraDB = "Camera Database"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .library: return "folder"
        case .chartGenerator: return "viewfinder"
        case .viewer: return "eye"
        case .clipID: return "film"
        case .cameraDB: return "camera"
        }
    }

    /// Keyboard shortcut number (Cmd+1 through Cmd+5)
    var shortcutIndex: Int {
        switch self {
        case .library: return 1
        case .chartGenerator: return 2
        case .viewer: return 3
        case .clipID: return 4
        case .cameraDB: return 5
        }
    }

    var shortcutKey: KeyEquivalent {
        KeyEquivalent(Character("\(shortcutIndex)"))
    }
}
