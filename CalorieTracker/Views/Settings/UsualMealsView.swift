import SwiftUI
import SwiftData

/// Settings → Usual meals: the meals the chat logs by name (D54).
struct UsualMealsView: View {
    @Query(sort: \UsualMeal.name) private var meals: [UsualMeal]
    @Environment(\.modelContext) private var context
    @State private var deleting: UsualMeal?
    @State private var error: String?

    var body: some View {
        List {
            Group {
                if meals.isEmpty {
                    ContentUnavailableView {
                        Label("No usual meals yet", systemImage: "fork.knife")
                    } description: {
                        Text("After logging something you eat often, tell the Log chat \"save that as my usual breakfast\". Then just say \"usual breakfast\" to log it.")
                    }
                } else {
                    Section {
                        ForEach(meals) { usual in
                            NavigationLink {
                                UsualMealEditView(usual: usual)
                            } label: {
                                row(usual)
                            }
                            .swipeActions {
                                Button("Delete", systemImage: "trash", role: .destructive) { deleting = usual }
                                    .tint(.red)
                            }
                        }
                    } footer: {
                        Text("Say a meal's name in the Log chat to log it with these exact numbers. Editing or deleting a meal doesn't change anything already logged.")
                    }
                }
                if let error {
                    Text(error).foregroundStyle(Palette.plum)
                }
            }
            .listRowBackground(Palette.panel)
        }
        .themedBackground()
        .navigationTitle("Usual meals")
        .confirmationDialog("Delete \"\(deleting?.name ?? "")\"?", isPresented: Binding(
            get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                guard let usual = deleting else { return }
                do { try UsualMealStore.delete(usual, in: context) }
                catch { self.error = "Couldn't delete: \(error.localizedDescription)" }
                deleting = nil
            }
        } message: {
            Text("Meals already logged with it stay as they are.")
        }
    }

    private func row(_ usual: UsualMeal) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(usual.name)
                Spacer()
                Text("\(usual.calories) cal").monospacedDigit()
            }
            Text("\(usual.meal.rawValue) · \(usual.source.rawValue) · \(usual.protein)p \(usual.carbs)c \(usual.fat)f")
                .font(.barlow(.footnote))
                .foregroundStyle(.secondary)
        }
    }
}

/// Edit one usual meal. The source is shown but can't change.
struct UsualMealEditView: View {
    let usual: UsualMeal

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var edit: UsualMealStore.Edit
    @State private var phrasesText: String
    @State private var problem: String?

    init(usual: UsualMeal) {
        self.usual = usual
        _edit = State(initialValue: UsualMealStore.Edit(usual))
        _phrasesText = State(initialValue: usual.triggerPhrases.joined(separator: ", "))
    }

    var body: some View {
        Form {
            Group {
                Section {
                    TextField("Name", text: $edit.name)
                    TextField("Other names, separated by commas", text: $phrasesText, axis: .vertical)
                } header: {
                    Text("Name")
                } footer: {
                    Text("Any of these names logs the meal, for example \"my normal lunch\".")
                }
                Section("What it is") {
                    TextField("Description", text: $edit.description, axis: .vertical)
                    Picker("Meal", selection: $edit.meal) {
                        ForEach(Meal.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    Toggle("Contains alcohol", isOn: $edit.containsAlcohol)
                }
                Section {
                    NumberRow(label: "Calories", value: $edit.calories, unit: "cal")
                    NumberRow(label: "Protein", value: $edit.protein, unit: "g")
                    NumberRow(label: "Carbs", value: $edit.carbs, unit: "g")
                    NumberRow(label: "Fat", value: $edit.fat, unit: "g")
                    LabeledContent("Source", value: usual.source.rawValue)
                } header: {
                    Text("Numbers")
                } footer: {
                    Text("The source stays as it was first measured, so an estimate is never shown as a label.")
                }
                if let problem {
                    Section { Text(problem).foregroundStyle(Palette.plum) }
                }
            }
            .listRowBackground(Palette.panel)
        }
        .themedBackground()
        .navigationTitle(usual.name)
        .navigationBarTitleDisplayMode(.inline)
        .keyboardDoneButton()
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", action: save)
            }
        }
    }

    private func save() {
        var final = edit
        final.triggerPhrases = UsualMealStore.phrases(from: phrasesText)
        do {
            try UsualMealStore.update(usual, with: final, in: context)
            dismiss()
        } catch let found as UsualMealStore.Problem {
            problem = found.message
        } catch {
            problem = "Couldn't save: \(error.localizedDescription)"
        }
    }
}
