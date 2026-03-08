import SwiftUI

enum UIStyle {
    static let sectionSpacing: CGFloat = 8
}

extension View {
    func denseControl() -> some View {
        controlSize(.small)
    }

    func secondarySectionHeader() -> some View {
        font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
    }

    func primarySectionHeader() -> some View {
        font(.subheadline.weight(.semibold))
    }
}
