import SwiftUI

/// Choose the Claude model from Anthropic's live list. The newest Sonnet is marked Recommended.
struct ModelPickerView: View {
    var onChange: () -> Void

    private let settings = AppSettings()

    @State private var models: [AnthropicModel] = []
    @State private var selected: String?
    @State private var failure: AnthropicError?
    @State private var loading = false

    private var recommendedID: String? { ModelRecommendation.recommended(in: models)?.id }

    /// Recommended first, then newest first.
    private var ordered: [AnthropicModel] {
        models.sorted { a, b in
            if a.id == recommendedID { return true }
            if b.id == recommendedID { return false }
            return a.createdAt > b.createdAt
        }
    }

    var body: some View {
        List {
            if loading && models.isEmpty {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Getting Anthropic's current models…").foregroundStyle(.secondary)
                }
            }
            if let failure {
                Section {
                    Text(failure.userMessage).foregroundStyle(.red)
                    Button("Try again") { Task { await load() } }
                }
            }
            if !models.isEmpty {
                Section {
                    ForEach(ordered) { model in
                        Button { choose(model) } label: { row(model) }
                            .tint(.primary)
                    }
                } footer: {
                    Text("Sonnet is recommended. It's accurate with descriptions, nutrition labels and meal photos, at a moderate cost per entry. Larger models cost more each time you log.")
                }
            }
        }
        .navigationTitle("Model")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
    }

    private func row(_ model: AnthropicModel) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(model.displayName)
                    if model.id == recommendedID {
                        Text("Recommended")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(.green.opacity(0.15), in: Capsule())
                            .foregroundStyle(.green)
                    }
                }
                Text(model.id).font(.caption).monospaced().foregroundStyle(.secondary)
            }
            Spacer()
            if model.id == selected {
                Image(systemName: "checkmark").foregroundStyle(.tint)
                    .accessibilityLabel("Selected")
            }
        }
        .contentShape(Rectangle())
    }

    private func load() async {
        selected = settings.modelID
        guard let key = try? APIKeyStore().load() else {
            failure = .invalidKey
            return
        }
        loading = true
        failure = nil
        defer { loading = false }
        do {
            models = try await AnthropicClient(apiKey: key).listModels()
            let resolved = ModelRecommendation.resolve(current: settings.modelID, in: models)
            if resolved != settings.modelID {
                settings.modelID = resolved
                selected = resolved
                onChange()
            }
        } catch let error as AnthropicError {
            failure = error
        } catch {
            failure = .other(status: 0, message: "The reply from Anthropic couldn't be read.")
        }
    }

    private func choose(_ model: AnthropicModel) {
        settings.modelID = model.id
        selected = model.id
        onChange()
    }
}
