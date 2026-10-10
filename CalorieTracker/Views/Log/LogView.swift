import SwiftUI
import SwiftData
import PhotosUI

/// The logging screen: a live "remaining" header, the conversation, and a composer
/// for text and photos.
struct LogView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase

    @State private var conversation: LogConversation?
    @State private var draft = ""
    @State private var photos: [Data] = []
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var showingLibrary = false
    @State private var showingCamera = false
    @State private var clipboardHasImage = UIPasteboard.general.hasImages
    @State private var showingSettings = false
    @State private var editing: UUID?
    @State private var hasKey = APIKeyStore().hasKey

    @State private var today = LocalDate.today(in: AppSettings().timeZone)
    @State private var targets = MacroTargets.defaults
    @State private var eaten = NutritionTotals.zero
    @State private var offeringReminder = false

    @FocusState private var composerFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                RemainingHeader(targets: targets, eaten: eaten)
                Divider().overlay(Palette.rule)
                if let conversation {
                    if conversation.items.isEmpty && !conversation.isSending {
                        // Centred in the space above the composer (the thread itself sits at the bottom).
                        ScrollView { emptyState.padding() }
                            .defaultScrollAnchor(.center)
                            .scrollBounceBehavior(.basedOnSize)
                            .scrollDismissesKeyboard(.immediately)
                            // Short content doesn't scroll, so a tap outside the examples closes the keyboard.
                            .contentShape(Rectangle())
                            .onTapGesture { composerFocused = false }
                    } else {
                        thread(conversation)
                    }
                    if let failure = conversation.failure { failureBanner(failure, conversation) }
                    else if offeringReminder { reminderOffer }
                    composer(conversation)
                }
            }
            .background(Palette.background)
            .navigationTitle("Calorie Log")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    // Words, not a pencil icon, which reads as "edit". Greyed out when there's
                    // nothing for Claude to forget.
                    Button("New chat") { startNewChat() }
                        .disabled(conversation.map { $0.isSending || $0.isFresh } ?? true)
                        .accessibilityHint("Claude stops seeing the messages so far. Your log isn't changed.")
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
        // Checking for an image doesn't read the clipboard, so it doesn't trigger the paste prompt.
        .onReceive(NotificationCenter.default.publisher(for: UIPasteboard.changedNotification)) { _ in
            clipboardHasImage = UIPasteboard.general.hasImages
        }
        .onAppear(perform: refresh) // entries may have been edited on another tab
        .task {
            if conversation == nil { conversation = LogConversation(context: context, store: .standard) }
            refresh()
        }
    }

    // MARK: Thread

    private func thread(_ conversation: LogConversation) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
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
                withAnimation(reduceMotion ? nil : .default) { proxy.scrollTo(conversation.items.last?.id, anchor: .bottom) }
            }
            .onChange(of: conversation.revision) { _, _ in
                // A card that was just accepted grows by a line; keep it in view.
                withAnimation(reduceMotion ? nil : .default) { proxy.scrollTo(conversation.items.last?.id, anchor: .bottom) }
            }
            .onChange(of: conversation.isSending) { _, sending in
                if sending { withAnimation(reduceMotion ? nil : .default) { proxy.scrollTo("sending", anchor: .bottom) } }
            }
        }
    }

    @ViewBuilder
    private func row(_ item: LogConversation.Item, _ conversation: LogConversation) -> some View {
        switch item.kind {
        case .user(let text, let photos, let notKept):
            VStack(alignment: .trailing, spacing: 6) {
                if !photos.isEmpty { PhotoStrip(photos: photos, size: 88) }
                if notKept > 0 {
                    Label(notKept == 1 ? "Photo (not kept)" : "\(notKept) photos (not kept)", systemImage: "photo")
                        .font(.barlow(.caption))
                        .foregroundStyle(.secondary)
                }
                if !text.isEmpty {
                    Text(text)
                        .padding(.horizontal, 14).padding(.vertical, 9)
                        .background(Palette.green, in: UnevenRoundedRectangle(topLeadingRadius: 18, bottomLeadingRadius: 18,
                                                                             bottomTrailingRadius: 6, topTrailingRadius: 18))
                        .foregroundStyle(Palette.onGreen)
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.leading, 40)
        case .assistant(let text):
            Text(text)
                .claudeBubble()
                .padding(.trailing, 40)
        case .logged(let line):
            SavedLine(text: line)
        case .local(let answer):
            VStack(alignment: .leading, spacing: 4) {
                Text(answer)
                Text("Worked out on your iPhone").font(.barlow(.caption2)).foregroundStyle(Palette.muted)
            }
            .claudeBubble()
            .padding(.trailing, 40)
        case .proposal(let id):
            if let proposal = conversation.proposals[id] {
                ProposalCard(proposal: proposal, today: today,
                             onAccept: { conversation.accept(id) },
                             onEdit: { editing = id },
                             onDismiss: { conversation.dismiss(id) })
            }
        case .notice(let text):
            Text(text).font(.barlow(.footnote)).foregroundStyle(Palette.muted)
                .frame(maxWidth: .infinity)
        case .newConversation:
            HStack {
                VStack { Divider() }
                Text("New chat · Claude won't see the messages above")
                    .font(.barlow(.caption)).foregroundStyle(Palette.muted)
                    .multilineTextAlignment(.center)
                    // The lines either side shrink first, so the text stays on one line when it fits.
                    .layoutPriority(1)
                VStack { Divider() }
            }
            .padding(.vertical, 4)
        }
    }

    private func startNewChat() {
        conversation?.startNewConversation()
        AccessibilityNotification.Announcement("New chat started. Claude won't see the messages above.").post()
    }

    /// The mark, the prompt, and three examples. Tapping a typed example puts it in the
    /// composer to edit or send (with a trailing space, so autocorrect leaves its last word
    /// alone); the photo one opens the camera (or the library).
    private var emptyState: some View {
        VStack(spacing: 18) {
            Image("BrandMark")
                .resizable()
                .frame(width: 56, height: 56)
                .accessibilityHidden(true)
            Text("Tell me what you ate, or send a photo.")
                .font(.barlow(.title3, weight: .semibold))
                .multilineTextAlignment(.center)
            VStack(spacing: 8) {
                example("“300 cal protein bar for a snack”", icon: "text.bubble") {
                    draft = "300 cal protein bar for a snack "; composerFocused = true
                }
                example("“Chicken burrito and chips for lunch”", icon: "text.bubble") {
                    draft = "Chicken burrito and chips for lunch "; composerFocused = true
                }
                example("A photo of a nutrition label or your plate", icon: "camera", tint: Palette.ochreInk) {
                    if CameraPicker.isAvailable { showingCamera = true } else { showingLibrary = true }
                }
            }
            // Keyboard dictation is the quickest way to describe a meal (issue #9).
            Label("Tip: tap the microphone on the keyboard and just say what you ate.", systemImage: "mic")
                .font(.barlow(.footnote)).foregroundStyle(Palette.muted)
                .multilineTextAlignment(.center)
            if !hasKey {
                Text("Add your AI key (from Anthropic) in Settings to start. You can already ask “calories left?”.")
                    .font(.barlow(.footnote)).foregroundStyle(Palette.ochreInk)
                    .multilineTextAlignment(.center)
            }
        }
        .foregroundStyle(Palette.ink)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    private func example(_ text: String, icon: String, tint: Color = Palette.green,
                         action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon).foregroundStyle(tint).accessibilityHidden(true)
                Text(text).multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .font(.barlow(.callout))
            .foregroundStyle(Palette.ink)
            .padding(.horizontal, 14).padding(.vertical, 12)
            .frame(minHeight: 48)
            .background(Palette.panel, in: .rect(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Palette.rule))
        }
        .buttonStyle(.plain)
    }

    private func failureBanner(_ failure: LogConversation.Failure, _ conversation: LogConversation) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 8) {
                Text(failure.message).font(.barlow(.footnote))
                HStack {
                    if failure.canRetry {
                        Button("Retry") { Task { await conversation.retry() } }
                    }
                    if failure.needsKey {
                        Button("Settings") { showingSettings = true }
                    } else if !failure.canRetry {
                        Button("New chat") { startNewChat() }
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

    /// Offered once, after the first food is logged (issue #12, D73). iOS asks for
    /// notification permission only if the user says yes.
    private var reminderOffer: some View {
        let time = ReminderPlan(minutes: AppSettings().reminderMinutes).timeText(in: AppSettings().timeZone)
        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: "bell").foregroundStyle(Palette.green).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 8) {
                Text("Want a daily reminder to log your food? It's skipped on days you've already logged. You can change it in Settings.")
                    .font(.barlow(.footnote))
                HStack {
                    Button("Remind me at \(time)") { answerReminderOffer(yes: true) }
                        .buttonStyle(.borderedProminent)
                    Button("No thanks") { answerReminderOffer(yes: false) }
                        .buttonStyle(.bordered)
                }
                .controlSize(.small)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Palette.panel)
    }

    private func answerReminderOffer(yes: Bool) {
        let settings = AppSettings()
        settings.reminderOffered = true
        withAnimation { offeringReminder = false }
        guard yes else { return }
        Task {
            guard await ReminderScheduler.requestPermission() else { return }
            settings.reminderEnabled = true
            await ReminderScheduler.reschedule(in: context, settings: settings)
        }
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
                    // A photo copied elsewhere, e.g. from Messages (issue #14). The text field only takes pasted text.
                    // The system Paste button reads the clipboard without an "Allow Paste?" prompt;
                    // a plain button reading it in code was refused on iOS 27.
                    if clipboardHasImage {
                        PasteButton(supportedContentTypes: [.image]) { providers in pastePhotos(providers) }
                    }
                } label: {
                    Image(systemName: "camera")
                        .font(.barlow(.title3))
                        .foregroundStyle(Palette.green)
                        .frame(width: 44, height: 44)
                        .background(Palette.panel, in: Circle())
                        .overlay(Circle().strokeBorder(Palette.rule))
                }
                .disabled(!conversation.acceptsPhotos || photos.count >= PhotoPrep.maxPhotosPerMessage)
                .accessibilityLabel("Add photo")

                TextField("What did you eat?", text: $draft, axis: .vertical)
                    .lineLimit(1...5)
                    // Grows with the text however it arrives (dictation included), up to five lines (issue #6).
                    .fixedSize(horizontal: false, vertical: true)
                    .focused($composerFocused)
                    .padding(.horizontal, 16).padding(.vertical, 11)
                    .background(Palette.panel, in: .rect(cornerRadius: 22))
                    .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(Palette.rule))

                Button {
                    send(conversation)
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 40))
                        .frame(width: 44, height: 44)
                }
                .tint(Palette.green)
                .disabled(conversation.isSending || (draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && photos.isEmpty))
                .accessibilityLabel("Send")
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Palette.background)
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

    private func pastePhotos(_ providers: [NSItemProvider]) {
        for provider in providers {
            _ = provider.loadDataRepresentation(for: .image) { data, _ in
                guard let data, let image = UIImage(data: data) else { return }
                Task { @MainActor in addPhoto(image) }
            }
        }
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
        offeringReminder = !settings.reminderOffered && !settings.reminderEnabled && eaten.entryCount > 0
        clipboardHasImage = UIPasteboard.general.hasImages
    }
}

extension UUID: @retroactive Identifiable {
    public var id: UUID { self }
}

/// The live header: calories left today, with the macros underneath.
struct RemainingHeader: View {
    var targets: MacroTargets
    var eaten: NutritionTotals

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize

    private var remaining: Remaining { Remaining(targets: targets, eaten: eaten) }

    var body: some View {
        VStack(spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(abs(remaining.calories).formatted())
                    .font(.number(40, relativeTo: .largeTitle))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text(remaining.isOverCalories ? "calories over today" : "calories left today")
                    .foregroundStyle(remaining.isOverCalories ? Palette.plum : Palette.muted)
                Spacer(minLength: 0)
            }
            progressBar
            Text("\(eaten.calories.formatted()) of \(targets.calories.formatted()) calories eaten")
                .font(.barlow(.footnote)).monospacedDigit().foregroundStyle(Palette.muted)
                .frame(maxWidth: .infinity, alignment: .leading)
            let macros = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
                : AnyLayout(HStackLayout(spacing: 8))
            macros {
                macro("Protein", remaining.protein)
                macro("Carbs", remaining.carbs)
                macro("Fat", remaining.fat)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 2)
        }
        .foregroundStyle(Palette.ink)
        .padding(.horizontal)
        .padding(.vertical, 10)
        .animation(reduceMotion ? nil : .default, value: eaten)
        // The chat needs the room more: past the first accessibility size, only the chat grows.
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .accessibilityElement(children: .combine)
    }

    /// Eaten against the target; plum once over.
    private var progressBar: some View {
        GeometryReader { geometry in
            let fraction = min(Double(eaten.calories) / Double(max(targets.calories, 1)), 1)
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.track)
                Capsule().fill(remaining.isOverCalories ? Palette.plum : Palette.green)
                    .frame(width: geometry.size.width * fraction)
            }
        }
        .frame(height: 8)
    }

    /// One macro's grams left, as a small panel (a plain line at the largest text sizes).
    @ViewBuilder
    private func macro(_ name: String, _ left: Int) -> some View {
        let value = Text(left >= 0 ? "\(left) g left" : "\(-left) g over")
            .monospacedDigit()
            .foregroundStyle(left >= 0 ? Palette.ink : Palette.plum)
        if typeSize.isAccessibilitySize {
            HStack(spacing: 4) {
                Text(name).foregroundStyle(Palette.muted)
                value
            }
            .font(.barlow(.footnote))
        } else {
            VStack(alignment: .leading, spacing: 0) {
                Text(name).font(.barlow(.caption)).foregroundStyle(Palette.muted)
                value.font(.number(19, relativeTo: .body))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(Palette.panel, in: .rect(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Palette.rule))
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

/// The one-line confirmation once something is saved.
struct SavedLine: View {
    var text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .symbolRenderingMode(.palette)
                .foregroundStyle(Palette.onGreen, Palette.green)
                .accessibilityHidden(true)
            Text(text)
        }
        .font(.barlow(.subheadline))
        .foregroundStyle(Palette.ink)
        .padding(.horizontal, 14).padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.panel, in: .rect(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Palette.rule))
    }
}

extension View {
    /// Claude's side of the conversation: a panel bubble with its tail at the bottom left.
    func claudeBubble() -> some View {
        let shape = UnevenRoundedRectangle(topLeadingRadius: 18, bottomLeadingRadius: 6,
                                           bottomTrailingRadius: 18, topTrailingRadius: 18)
        return padding(.horizontal, 14).padding(.vertical, 9)
            .foregroundStyle(Palette.ink)
            .background(Palette.panel, in: shape)
            .overlay(shape.strokeBorder(Palette.rule))
    }
}
