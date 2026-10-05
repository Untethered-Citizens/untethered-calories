import SwiftUI

/// "Today" as the app defines it, kept current when the app comes back to the
/// foreground and when the date changes.
@Observable
final class DayClock {
    private(set) var today = LocalDate.today(in: AppSettings().timeZone)

    func refresh() {
        let now = LocalDate.today(in: AppSettings().timeZone)
        if now != today { today = now }
    }
}

/// A big condensed number with a two-line unit beside it.
struct HeroNumber: View {
    /// Redraws when the text size changes, so scaled numbers follow it.
    @Environment(\.dynamicTypeSize) private var typeSize
    var value: String
    var unit: String
    var over = false
    var size: CGFloat = 96

    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: 10) {
            Text(value)
                .font(.number(size, relativeTo: .largeTitle))
                .foregroundStyle(over ? Palette.plum : Palette.ink)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
            Text(unit)
                .font(.barlow(.callout))
                .foregroundStyle(Palette.muted)
        }
        .accessibilityElement(children: .combine)
    }
}

/// One bar the width of the target, split into a segment per entry in meal order and
/// styled by source, so the day's confidence shows at a glance. Over target, the scale
/// grows and a tick marks the target.
struct BudgetStrip: View {
    var entries: [EntryDraft]
    var target: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    private var total: Int { entries.reduce(0) { $0 + $1.calories } }
    private var scale: Int { max(target, total, 1) }

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 5).fill(Palette.track)
                HStack(spacing: 0) {
                    ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in
                        Rectangle()
                            .fill(SourceFill(source: entry.source))
                            .frame(width: max(0, CGFloat(entry.calories) / CGFloat(scale) * width - 2))
                            .padding(.trailing, 2)
                    }
                }
                .frame(width: width, alignment: .leading)
                .scaleEffect(x: shown ? 1 : 0, anchor: .leading)
                .clipShape(RoundedRectangle(cornerRadius: 5))
                if total > target {
                    let x = CGFloat(target) / CGFloat(scale) * width
                    Rectangle().fill(Palette.ink).frame(width: 2, height: 30).offset(x: x - 1)
                    Text("target").font(.barlow(.caption)).foregroundStyle(Palette.muted)
                        .fixedSize().position(x: x, y: -16)
                }
            }
        }
        .frame(height: 18)
        .padding(.top, total > target ? 22 : 0)
        .onAppear {
            if reduceMotion { shown = true } else { withAnimation(.easeOut(duration: 0.6)) { shown = true } }
        }
        .accessibilityHidden(true)
    }
}

struct SourceLegend: View {
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        // One line normally; a column at the largest sizes, so no word is split.
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(spacing: 16))
        layout {
            ForEach(Source.allCases, id: \.self) { source in
                HStack(spacing: 6) {
                    SourceSwatch(source: source, size: 12, radius: 3)
                    Text(source == .photoEstimate ? "Photo estimate" : source.rawValue)
                }
            }
        }
        .font(.barlow(.footnote))
        .foregroundStyle(Palette.muted)
        .accessibilityElement(children: .combine)
    }
}

struct SectionHeading: View {
    /// Redraws when the text size changes, so scaled numbers follow it.
    @Environment(\.dynamicTypeSize) private var typeSize
    var title: String
    /// Inside a card the card's padding is enough; on the open background it needs room above.
    var inCard = false
    var body: some View {
        Text(title)
            .font(.condensed(inCard ? 24 : 26))
            .foregroundStyle(Palette.ink)
            .padding(.top, inCard ? 0 : 12)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Protein, carbs and fat as bars against their targets. A bar turns plum when over.
struct MacroBars: View {
    /// Redraws when the text size changes, so scaled numbers follow it.
    @Environment(\.dynamicTypeSize) private var typeSize
    var protein: Double
    var carbs: Double
    var fat: Double
    var targets: MacroTargets

    @ScaledMetric(relativeTo: .body) private var nameWidth = 64.0

    var body: some View {
        VStack(spacing: 10) {
            row("Protein", protein, targets.protein)
            row("Carbs", carbs, targets.carbs)
            row("Fat", fat, targets.fat)
        }
    }

    private func row(_ name: String, _ value: Double, _ target: Int) -> some View {
        let rounded = Int(value.rounded())
        let over = rounded > target
        let fraction = target > 0 ? min(value / Double(target), 1) : 0
        let bar = GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.track)
                Capsule().fill(over ? Palette.plum : Palette.green)
                    .frame(width: geometry.size.width * fraction)
            }
        }
        .frame(height: 8)
        let amount = Text("\(rounded)").font(.number(20)) + Text(" / \(target) g").font(.barlow(.subheadline)).foregroundStyle(Palette.muted)
        return Group {
            if typeSize.isAccessibilitySize {
                // Too big to share a line: name and amount above, bar below.
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(name).fontWeight(.medium)
                        Spacer()
                        amount
                    }
                    bar
                }
            } else {
                HStack(spacing: 12) {
                    Text(name).fontWeight(.medium).frame(width: nameWidth, alignment: .leading)
                    bar
                    amount.frame(minWidth: 92, alignment: .trailing)
                }
            }
        }
        .foregroundStyle(Palette.ink)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name): \(rounded) of \(target) grams\(over ? ", over target" : "")")
    }
}

/// A small square of a source's fill, for legends and tags.
struct SourceSwatch: View {
    var source: Source
    var size: CGFloat
    var radius: CGFloat

    var body: some View {
        Rectangle().fill(SourceFill(source: source))
            .frame(width: size, height: size)
            .clipShape(.rect(cornerRadius: radius))
    }
}

/// A source tag: a swatch of the source's fill and its name, so it reads without colour.
struct SourceTag: View {
    var source: Source
    var body: some View {
        HStack(spacing: 5) {
            SourceSwatch(source: source, size: 10, radius: 2)
                .accessibilityHidden(true)
            Text(source.shortName)
        }
        .font(.barlow(.caption, weight: .semibold))
        .lineLimit(1)
        .fixedSize()
        .foregroundStyle(source.tagColor)
        .padding(.horizontal, 8).padding(.vertical, 2)
        .overlay(Capsule().strokeBorder(Palette.rule))
    }
}

/// One entry in a meals list: meal and source, big calories, what it was, macros.
struct MealRow: View {
    /// Redraws when the text size changes, so scaled numbers follow it.
    @Environment(\.dynamicTypeSize) private var typeSize
    var draft: EntryDraft

    var body: some View {
        // At the largest sizes everything gets its own line, so no word or tag is split.
        let big = typeSize.isAccessibilitySize
        let outer = big ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
                        : AnyLayout(HStackLayout(alignment: .center, spacing: 14))
        let heading = big ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
                          : AnyLayout(HStackLayout(spacing: 8))
        outer {
            VStack(alignment: .leading, spacing: 2) {
                heading {
                    Text(draft.meal.rawValue).fontWeight(.semibold)
                    HStack(spacing: 8) {
                        SourceTag(source: draft.source)
                        if draft.containsAlcohol {
                            Image(systemName: "wineglass").font(.barlow(.caption)).foregroundStyle(Palette.muted)
                                .accessibilityLabel("Contains alcohol")
                        }
                    }
                }
                Text(draft.description).font(.barlow(.subheadline))
                Text("\(draft.protein) g P · \(draft.carbs) g C · \(draft.fat) g F")
                    .font(.barlow(.footnote, weight: .medium)).monospacedDigit().foregroundStyle(Palette.muted)
            }
            if !big { Spacer(minLength: 0) }
            (Text(draft.calories.formatted()).font(.number(22, relativeTo: .title2))
             + Text(" cal").font(.barlow(.footnote, weight: .medium)).foregroundStyle(Palette.muted))
                .fixedSize()
        }
        .foregroundStyle(Palette.ink)
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

extension View {
    /// A row inside a dashboard card (an inset-grouped section): the panel colour, with
    /// the card's padding. Separators only between meals.
    func cardRow(separator: Bool = false) -> some View {
        listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
            .listRowBackground(Palette.panel)
            .listRowSeparator(separator ? .visible : .hidden)
            .listRowSeparatorTint(Palette.rule)
    }

    /// Content that sits on the screen background between cards, aligned with their edges.
    /// The vertical inset keeps it clear of the section's rounded corners, which clip.
    func openRow() -> some View {
        listRowInsets(EdgeInsets(top: 12, leading: 4, bottom: 12, trailing: 4))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }

    /// A dashboard list row: no default inset background or separator.
    func dashboardRow(separator: Bool = false) -> some View {
        listRowInsets(EdgeInsets(top: 6, leading: 18, bottom: 6, trailing: 18))
            .listRowBackground(Palette.background)
            .listRowSeparator(separator ? .visible : .hidden)
            .listRowSeparatorTint(Palette.rule)
    }
}
