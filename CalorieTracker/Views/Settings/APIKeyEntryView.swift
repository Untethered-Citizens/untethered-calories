import SwiftUI

/// Paste an Anthropic API key, check it with Anthropic, then save it to the Keychain.
/// The check lists the models the key can use (free, no tokens) and picks the model if none is set.
/// Reused by onboarding.
struct APIKeyEntryView: View {
    var title: String
    var onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var key = ""
    @State private var checking = false
    @State private var failure: AnthropicError?
    @State private var saveError: String?

    private var cleaned: String { APIKeyStore.clean(key) }

    var body: some View {
        Form {
            Section {
                SecureField("sk-ant-…", text: $key)
                    .textContentType(.password)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .monospaced()
                    .disabled(checking)
                    .onChange(of: key) { failure = nil }
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    if !cleaned.isEmpty && !APIKeyStore.looksLikeAnthropicKey(cleaned) {
                        Text("This doesn't look like an Anthropic key. They start with \"sk-ant-\".")
                            .foregroundStyle(.orange)
                    }
                    Text("Create a key at platform.claude.com under Settings → API keys, then paste it here. Saving checks it with Anthropic, which costs nothing. It's stored only in this iPhone's Keychain.")
                }
            }

            if checking {
                Section {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Checking with Anthropic…").foregroundStyle(.secondary)
                    }
                }
            }

            if let failure {
                Section {
                    Text(failure.userMessage).foregroundStyle(.red)
                    if failure != .invalidKey {
                        Button("Save without checking") { store(models: nil) }
                    }
                }
            }
            if let saveError {
                Text(saveError).foregroundStyle(.red)
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { Task { await check() } }
                    .disabled(cleaned.isEmpty || checking)
            }
        }
    }

    private func check() async {
        checking = true
        failure = nil
        defer { checking = false }
        do {
            let models = try await AnthropicClient(apiKey: cleaned).listModels()
            store(models: models)
        } catch let error as AnthropicError {
            failure = error
        } catch {
            failure = .other(status: 0, message: "The reply from Anthropic couldn't be read.")
        }
    }

    /// Saves the key. With a model list, also settles the model choice.
    private func store(models: [AnthropicModel]?) {
        do {
            try APIKeyStore().save(cleaned)
        } catch {
            saveError = "Couldn't save the key to the Keychain."
            return
        }
        if let models {
            let settings = AppSettings()
            settings.modelID = ModelRecommendation.resolve(current: settings.modelID, in: models)
        }
        key = ""
        onSaved()
        dismiss()
    }
}

#Preview {
    NavigationStack { APIKeyEntryView(title: "Add key") {} }
}
