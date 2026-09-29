import SwiftUI

/// A whole-number field that updates on every keystroke. `TextField(value:format:)` only
/// commits on Return or focus loss, and the number pad has no Return key, so a Save tapped
/// straight after typing would miss the new value. Zero shows as empty.
struct NumberField: View {
    var placeholder: String
    @Binding var value: Int
    var maxDigits = 5

    var body: some View {
        TextField(placeholder, text: Binding(
            get: { value == 0 ? "" : String(value) },
            set: { value = Int($0.filter(\.isNumber).prefix(maxDigits)) ?? 0 }))
            .keyboardType(.numberPad)
            .multilineTextAlignment(.trailing)
            .monospacedDigit()
    }
}

/// A labelled number row with a unit, for forms.
struct NumberRow: View {
    var label: String
    @Binding var value: Int
    var unit: String
    var maxDigits = 5

    var body: some View {
        LabeledContent(label) {
            HStack(spacing: 4) {
                NumberField(placeholder: "–", value: $value, maxDigits: maxDigits)
                Text(unit).foregroundStyle(.secondary)
            }
        }
    }
}

extension View {
    /// Adds a Done button above the keyboard. The number pad has no Return key of its own.
    /// Apply once per screen, not per field, or the button repeats.
    func keyboardDoneButton() -> some View {
        toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
                .bold()
            }
        }
        .scrollDismissesKeyboard(.interactively)
    }
}
