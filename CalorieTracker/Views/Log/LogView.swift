import SwiftUI
import SwiftData
import PhotosUI

/// The logging screen: a live "remaining" header, the conversation, and a composer
/// for text and photos.
struct LogView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase

    @State private var conversation: LogConversation?
    @State private var draft = ""
    @State private var photos: [Data] = []
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var showingLibrary = false
    @State private var showingCamera = false
    @State private var showingSettings = false
    @State private var editing: UUID?
    @State private var hasKey = APIKeyStore().hasKey

    @State private var today = LocalDate.today(in: AppSettings().timeZone)
    @State private var targets = MacroTargets.defaults
    @State private var eaten = NutritionTotals.zero

    @FocusState private var composerFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                RemainingHeader(targets: targets, eaten: eaten)
                Divider()
                if let conversation {
                    thread(conversation)
                    if let failure = conversation.failure { failureBanner(failure, conversation) }
                    composer(conversation)
                }
            }
            .navigationTitle("Log")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("New conversation", systemImage: "square.and.pencil") {
                        conversation?.startNewConversation()
                    }
                    .disabled(conversation?.isSending ?? true)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Settings", systemImage: "gearshape") { showingSettings = true }
                }
            }
        }
        .sheet(isPresented: $showingSettings, onDismiss: refresh) { SettingsView() }
        .sheet(item: $editing) { id in editSheet(id) }
        .fullScreenCover(isPresented: $showingCamera) {
            CameraPicker { image in addPhoto(image) }.ignoresSafeArea()
        }
        .photosPicker(isPresented: $showingLibrary, selection: $pickerItems,
                      maxSelectionCount: max(1, PhotoPrep.maxPhotosPerMessage - photos.count), matching: .images)
        .onChange(of: pickerItems) { _, items in loadPicked(items) }
        .onChange(of: conversation?.revision) { _, _ in refresh() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { refresh() } }
        .onAppear(perform: refresh) // entries may have been edited on another tab
        .task {
            if conversation == nil { conversation = LogConversation(context: context) }
            refresh()
        }
    }

    // MARK: Thread

    private func thread(_ conversation: LogConversation) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if conversation.items.isEmpty { emptyState }
                    ForEach(conversation.items) { item in
                        row(item, conversation).id(item.id)
                    }
                    if conversation.isSending {
                        ProgressView().padding(.leading, 6).id("sending")
                    }
                }
                .padding()
            }
            .defaultScrollAnchor(.bottom)
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: conversation.items.count) { _, _ in
                // A card needs the screen, and Accept should be one tap, not one to close the keyboard.
                if case .proposal = conversation.items.last?.kind { composerFocused = false }
                withAnimation { proxy.scrollTo(conversation.items.last?.id, anchor: .bottom) }
            }
            .onChange(of: conversation.revision) { _, _ in
                // A card that was just accepted grows by a line; keep it in view.
                withAnimation { proxy.scrollTo(conversation.items.last?.id, anchor: .bottom) }
            }
            .onChange(of: conversation.isSending) { _, sending in
                if sending { withAnimation { proxy.scrollTo("sending", anchor: .bottom) } }
            }
        }
    }

    @ViewBuilder
    private func row(_ item: LogConversation.Item, _ conversation: LogConversation) -> some View {
        switch item.kind {
        case .user(let text, let photos):
            VStack(alignment: .trailing, spacing: 6) {
                if !photos.isEmpty { PhotoStrip(photos: photos, size: 88) }
                if !text.isEmpty {
                    Text(text)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(Color.accentColor, in: .rect(cornerRadius: 16))
                        .foregroundStyle(.white)
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.leading, 40)
        case .assistant(let text):
            Text(text)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(.background.secondary, in: .rect(cornerRadius: 16))
                .padding(.trailing, 40)
        case .logged(let line):
            Label(line, systemImage: "checkmark.circle.fill")
                .font(.subheadline)
                .foregroundStyle(.primary)
                .symbolRenderingMode(.multicolor)
                .padding(.trailing, 24)
        case .local(let answer):
            VStack(alignment: .leading, spacing: 4) {
                Text(answer)
                Text("Worked out on your iPhone").font(.caption2).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(.background.secondary, in: .rect(cornerRadius: 16))
            .padding(.trailing, 40)
        case .proposal(let id):
            if let proposal = conversation.proposals[id] {
                ProposalCard(proposal: proposal, today: today,
                             onAccept: { conversation.accept(id) },
                             onEdit: { editing = id },
                             onDismiss: { conversation.dismiss(id) })
            }
        case .notice(let text):
            Text(text).font(.footnote).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
        case .newConversation:
            HStack {
                VStack { Divider() }
                Text("New conversation").font(.caption).foregroundStyle(.secondary).fixedSize()
                VStack { Divider() }
            }
            .padding(.vertical, 4)
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Tell me what you ate, or send a photo.")
                .font(.headline)
            Text("“300 cal protein bar for a snack”\n“Chicken burrito and chips for lunch”\nA photo of a nutrition label or your plate")
                .foregroundStyle(.secondary)
            if !hasKey {
                Text("Add your Anthropic API key in Settings to start. You can already ask “calories left?”.")
                    .font(.footnote).foregroundStyle(.orange)
                    .padding(.top, 4)
            }
        }
        .padding(.vertical, 24)
    }

    private func failureBanner(_ failure: LogConversation.Failure, _ conversation: LogConversation) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 8) {
                Text(failure.message).font(.footnote)
                HStack {
                    if failure.canRetry {
                        Button("Retry") { Task { await conversation.retry() } }
                    }
                    if failure.needsKey {
                        Button("Settings") { showingSettings = true }
                    } else if !failure.canRetry {
                        Button("New conversation") { conversation.startNewConversation() }
                    }
                }
                .buttonStyle(.bordered).controlSize(.small)
            }
            Spacer()
            Button("Close", systemImage: "xmark") { conversation.clearFailure() }
                .labelStyle(.iconOnly).foregroundStyle(.secondary)
        }
        .padding(12)
        .background(.orange.opacity(0.12))
    }

    // MARK: Composer

    private func composer(_ conversation: LogConversation) -> some View {
        VStack(spacing: 8) {
            if !photos.isEmpty {
                PhotoStrip(photos: photos, size: 56) { index in photos.remove(at: index) }
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(alignment: .bottom, spacing: 8) {
                Menu {
                    if CameraPicker.isAvailable {
                        Button("Take photo", systemImage: "camera") { showingCamera = true }
                    }
                    Button("Choose from library", systemImage: "photo.on.rectangle") { showingLibrary = true }
                } label: {
                    Image(systemName: "camera.fill")
                        .font(.title3)
                        .frame(width: 36, height: 36)
                }
                .disabled(!conversation.acceptsPhotos || photos.count >= PhotoPrep.maxPhotosPerMessage)
                .accessibilityLabel("Add photo")

                TextField("What did you eat?", text: $draft, axis: .vertical)
                    .lineLimit(1...5)
                    .focused($composerFocused)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(.background.secondary, in: .rect(cornerRadius: 18))

                Button {
                    send(conversation)
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 32))
                }
                .disabled(conversation.isSending || (draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && photos.isEmpty))
                .accessibilityLabel("Send")
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private func send(_ conversation: LogConversation) {
        // A word the keyboard is still suggesting isn't in `draft` yet. Ending editing
        // commits it, as Messages does, then the field is focused again.
        let wasFocused = composerFocused
        composerFocused = false
        Task {
            try? await Task.sleep(for: .milliseconds(50))
            let text = draft
            let attached = photos
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attached.isEmpty else { return }
            draft = ""
            photos = []
            composerFocused = wasFocused
            let taken = await conversation.send(text, photos: attached)
            if !taken {
                // Nothing went out (no key yet): give the text back.
                draft = text
                photos = attached
            }
            hasKey = APIKeyStore().hasKey
        }
    }

    private func addPhoto(_ image: UIImage) {
        guard photos.count < PhotoPrep.maxPhotosPerMessage, let data = PhotoPrep.jpeg(image) else { return }
        photos.append(data)
    }

    private func loadPicked(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        Task {
            for item in items {
                if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                    addPhoto(image)
                }
            }
            pickerItems = []
        }
    }

    // MARK: Edit and refresh

    @ViewBuilder
    private func editSheet(_ id: UUID) -> some View {
        if let conversation, let proposal = conversation.proposals[id], case .estimate(let entries) = proposal.kind {
            EntryEditView(original: entries.map(\.draft), timeZone: AppSettings().timeZone) { drafts in
                try conversation.acceptEdited(id, drafts: drafts)
            }
        }
    }

    private func refresh() {
        let settings = AppSettings()
        today = LocalDate.today(in: settings.timeZone)
        targets = (try? TargetStore.current(on: today, in: context)) ?? .defaults
        eaten = (try? DayTotalsIndex.load(from: today, through: today, in: context))?[today] ?? .zero
        hasKey = APIKeyStore().hasKey
    }
}

extension UUID: @retroactive Identifiable {
    public var id: UUID { self }
}

/// The live header: calories left today, with the macros underneath.
struct RemainingHeader: View {
    var targets: MacroTargets
    var eaten: NutritionTotals

    private var remaining: Remaining { Remaining(targets: targets, eaten: eaten) }

    var body: some View {
        VStack(spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(abs(remaining.calories).formatted())
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text(remaining.isOverCalories ? "over" : "left")
                    .foregroundStyle(remaining.isOverCalories ? .orange : .secondary)
                Spacer()
                Text("\(eaten.calories.formatted()) of \(targets.calories.formatted())")
                    .font(.subheadline).monospacedDigit().foregroundStyle(.secondary)
            }
            ProgressView(value: Double(min(eaten.calories, targets.calories)), total: Double(max(targets.calories, 1)))
                .tint(remaining.isOverCalories ? .orange : .accentColor)
            HStack {
                macro("Protein", remaining.protein)
                Spacer()
                macro("Carbs", remaining.carbs)
                Spacer()
                macro("Fat", remaining.fat)
            }
            .font(.footnote)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .animation(.default, value: eaten)
        .accessibilityElement(children: .combine)
    }

    private func macro(_ name: String, _ left: Int) -> some View {
        HStack(spacing: 4) {
            Text(name).foregroundStyle(.secondary)
            Text(left >= 0 ? "\(left) g left" : "\(-left) g over")
                .monospacedDigit()
                .foregroundStyle(left >= 0 ? Color.primary : Color.orange)
        }
    }
}

/// A row of photo thumbnails, with an optional remove button on each.
struct PhotoStrip: View {
    var photos: [Data]
    var size: CGFloat
    var onRemove: ((Int) -> Void)?

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(photos.enumerated()), id: \.offset) { index, data in
                if let image = UIImage(data: data) {
                    Image(uiImage: image)
                        .resizable().scaledToFill()
                        .frame(width: size, height: size)
                        .clipShape(.rect(cornerRadius: 10))
                        .overlay(alignment: .topTrailing) {
                            if let onRemove {
                                Button("Remove photo", systemImage: "xmark.circle.fill") { onRemove(index) }
                                    .labelStyle(.iconOnly)
                                    .foregroundStyle(.white, .black.opacity(0.6))
                                    .padding(2)
                            }
                        }
                }
            }
        }
    }
}
