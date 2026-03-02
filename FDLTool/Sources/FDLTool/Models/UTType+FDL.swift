import UniformTypeIdentifiers

extension UTType {
    /// Dynamic UTType for .fdl extension files.
    /// Created without JSON conformance so NSOpenPanel can match any .fdl file.
    static let fdl: UTType = UTType(tag: "fdl", tagClass: .filenameExtension, conformingTo: nil)
        ?? UTType(importedAs: "com.ascmitc.framing-decision-list")
}
