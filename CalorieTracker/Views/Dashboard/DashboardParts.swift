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
    var value: String
    var unit: String
    var over = false
    var size: CGFloat = 104

    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: 10) {
            Text(value)
                .font(.number(size, weight: .bold))
                .foregroundStyle(over ? Palette.plum : Palette.ink)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
            Text(unit)
                .font(.callout)
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
                RoundedRectangle(cornerRadius: 4).fill(Palette.track)
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
                .clipShape(RoundedRectangle(cornerRadius: 4))
                if total > target {
                    let x = CGFloat(target) / CGFloat(scale) * width
                    Rectangle().fill(Palette.ink).frame(width: 2, height: 46).offset(x: x - 1)
                    Text("target").font(.caption).foregroundStyle(Palette.muted)
                        .fixedSize().position(x: x, y: -16)
                }
            }
        }
        .frame(height: 34)
        .padding(.top, total > target ? 22 : 0)
        .onAppear {
            if reduceMotion { shown = true } else { withAnimation(.easeOut(duration: 0.6)) { shown = true } }
        }
        .accessibilityHidden(true)
    }
}

struct SourceLegend: View {
    var body: some View {
        HStack(spacing: 16) {
            ForEach(Source.allCases, id: \.self) { source in
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 2).fill(SourceFill(source: source)).frame(width: 14, height: 10)
                    Text(source == .photoEstimate ? "Photo estimate" : source.rawValue)
                }
            }
        }
        .font(.footnote)
        .foregroundStyle(Palette.muted)
        .accessibilityElement(children: .combine)
    }
}

struct SectionHeading: View {
    var title: String
    var body: some View {
        Text(title)
            .font(.system(size: 26, weight: .semibold).width(.condensed))
            .foregroundStyle(Palette.ink)
            .padding(.top, 12)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Protein, carbs and fat as bars against their targets. A bar turns plum when over.
struct MacroBars: View {
    var protein: Double
    var carbs: Double
    var fat: Double
    var targets: MacroTargets

    var body: some View {
        VStack(spacing: 6) {
            row("Protein", protein, targets.protein)
            row("Carbs", carbs, targets.carbs)
            row("Fat", fat, targets.fat)
        }
    }

    private func row(_ name: String, _ value: Double, _ target: Int) -> some View {
        let rounded = Int(value.rounded())
        let over = rounded > target
        let fraction = target > 0 ? min(value / Double(target), 1) : 0
        return HStack(spacing: 12) {
            Text(name).fontWeight(.medium).frame(width: 64, alignment: .leading)
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Palette.track)
                    Capsule().fill(over ? Palette.plum : Palette.green)
                        .frame(width: geometry.size.width * fraction)
                }
            }
            .frame(height: 10)
            (Text("\(rounded)").font(.number(20))
             + Text(" / \(target) g").font(.subheadline).foregroundStyle(Palette.muted))
                .frame(minWidth: 92, alignment: .trailing)
        }
        .foregroundStyle(Palette.ink)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name): \(rounded) of \(target) grams\(over ? ", over target" : "")")
    }
}

struct SourceTag: View {
    var source: Source
    var body: some View {
        Text(source.shortName)
            .font(.caption.weight(.medium))
            .foregroundStyle(source.tagColor)
            .padding(.horizontal, 7).padding(.vertical, 1)
            .overlay(Capsule().strokeBorder(source.tagColor))
    }
}

/// One entry in a meals list: meal and source, big calories, what it was, macros.
struct MealRow: View {
    var draft: EntryDraft

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(draft.meal.rawValue).fontWeight(.semibold)
                    SourceTag(source: draft.source)
                    if draft.containsAlcohol {
                        Image(systemName: "wineglass").font(.caption).foregroundStyle(Palette.muted)
                            .accessibilityLabel("Contains alcohol")
                    }
                }
                Text(draft.description).font(.subheadline).foregroundStyle(Palette.muted)
                Text("\(draft.protein)p · \(draft.carbs)c · \(draft.fat)f")
                    .font(.footnote).monospacedDigit().foregroundStyle(Palette.muted)
            }
            Spacer(minLength: 0)
            Text(draft.calories.formatted()).font(.number(24))
        }
        .foregroundStyle(Palette.ink)
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

extension View {
    /// A dashboard list row: no default inset background or separator.
    func dashboardRow(separator: Bool = false) -> some View {
        listRowInsets(EdgeInsets(top: 6, leading: 18, bottom: 6, trailing: 18))
            .listRowBackground(Palette.background)
            .listRowSeparator(separator ? .visible : .hidden)
            .listRowSeparatorTint(Palette.rule)
    }
}
