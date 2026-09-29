import SwiftUI

/// Paste an Anthropic API key and save it to the Keychain.
/// Reused by onboarding. The live validation call is added in the next step.
struct APIKeyEntryView: View {
    var title: String
    var onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var key = ""
    @State private var error: String?

    private var cleaned: String { APIKeyStore.clean(key) }

    var body: some View {
        Form {
            Section {
                SecureField("sk-ant-…", text: $key)
                    .textContentType(.password)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .monospaced()
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    if !cleaned.isEmpty && !APIKeyStore.looksLikeAnthropicKey(cleaned) {
                        Text("This doesn't look like an Anthropic key. They start with \"sk-ant-\".")
                            .foregroundStyle(.orange)
                    }
                    if let error {
                        Text(error).foregroundStyle(.red)
                    }
                    Text("Create a key at console.anthropic.com under API Keys, then paste it here. It's stored only in this iPhone's Keychain.")
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", action: save)
                    .disabled(cleaned.isEmpty)
            }
        }
    }

    private func save() {
        do {
            try APIKeyStore().save(cleaned)
            key = ""
            onSaved()
            dismiss()
        } catch {
            self.error = "Couldn't save the key to the Keychain."
        }
    }
}

#Preview {
    NavigationStack { APIKeyEntryView(title: "Add key") {} }
}
