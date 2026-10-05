import SwiftUI
import SwiftData

/// Shown when daily totals have passed the retention setting: export a copy, delete them,
/// or decide later. Nothing is deleted any other way (D52).
struct RetentionPromptView: View {
    var dueCount: Int
    var keepDays: Int
    var today: LocalDate

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var export: ExportFiles?
    @State private var error: String?

    private let settings = AppSettings()

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("\(dueCount) \(dueCount == 1 ? "day" : "days") of daily totals are older than your \(RetentionPromptView.label(keepDays)) setting, from before \(LogText().dayName(Retention.cutoff(today: today, keepDays: keepDays), template: "MMM d, yyyy")).")
                Text("Export a copy first if you want to keep them. Deleting can't be undone. You can change how long totals are kept in Settings.")
                    .foregroundStyle(.secondary)
                if let error {
                    Text(error).foregroundStyle(Palette.plum)
                }
                Spacer()
                Button {
                    do { export = ExportFiles(urls: try DataExport.files(from: context, unit: settings.weightUnit, today: today)) }
                    catch { self.error = "Couldn't create the export: \(error.localizedDescription)" }
                } label: {
                    Label("Export CSV", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Palette.green)
                Button(role: .destructive) {
                    do {
                        try Retention.prune(today: today, keepDays: keepDays, in: context)
                        settings.lastRetentionPrompt = today
                        dismiss()
                    } catch { self.error = "Couldn't delete: \(error.localizedDescription)" }
                } label: {
                    Text("Delete \(dueCount) \(dueCount == 1 ? "day" : "days")").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .padding(20)
            .themedBackground()
            .navigationTitle("Old daily totals")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Not now") {
                        settings.lastRetentionPrompt = today
                        dismiss()
                    }
                }
            }
            .sheet(item: $export) { ShareSheet(items: $0.urls) }
        }
        .presentationDetents([.medium, .large])
        .interactiveDismissDisabled()
    }

    static func label(_ days: Int) -> String {
        switch days {
        case 365: "1-year"
        case 730: "2-year"
        default: "\(days)-day"
        }
    }
}
