import SwiftUI
import UIKit

/// The system share sheet, for files: Save to Files, AirDrop, Mail and so on.
struct ShareSheet: UIViewControllerRepresentable {
    var items: [URL]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// Files waiting to be shared, so a sheet can be driven by `.sheet(item:)`.
struct ExportFiles: Identifiable {
    let id = UUID()
    var urls: [URL]
}
