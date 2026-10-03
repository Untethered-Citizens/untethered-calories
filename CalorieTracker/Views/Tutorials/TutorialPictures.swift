import SwiftUI
import Charts

/// The picture at the top of each tutorial card, drawn in the app's palette so it matches
/// the real screens. All numbers are made up. Hidden from VoiceOver: the card text says it all.
struct TutorialPictureView: View {
    var picture: TutorialPicture

    var body: some View {
        switch picture {
        case .deficit: DeficitPicture()
        case .weekOfDeficit(let unit): WeekOfDeficitPicture(unit: unit)
        case .macros:
            MacroBars(protein: 112, carbs: 98, fat: 41, targets: .defaults)
        case .logExample: LogExamplePicture()
        case .sources: SourcesPicture()
        case .weightTrend: WeightTrendPicture()
        case .safety: Symbol("heart.text.square.fill", size: 72)
        case .keyConcept:
            IconRow(["iphone", "key.horizontal.fill", "bubble.left.and.text.bubble.right.fill"])
        case .direct: DirectPicture()
        case .cost: CostPicture()
        case .billing: BillingPicture()
        case .createKey: CreateKeyPicture()
        case .keySafety: KeySafetyPicture()
        case .oneKeyManyApps: OneKeyPicture()
        case .addKey: EmptyView()
        }
    }
}

// MARK: Weight tutorial

private struct DeficitPicture: View {
    var body: some View {
        HStack(alignment: .bottom, spacing: 36) {
            bar("Burned", height: 140) { Palette.greenSoft }
            VStack(spacing: 6) {
                ZStack(alignment: .bottom) {
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Palette.plum, style: StrokeStyle(lineWidth: 2, dash: [5, 4]))
                        .frame(width: 64, height: 140)
                        .overlay(alignment: .top) {
                            Text("deficit").font(.caption.bold()).foregroundStyle(Palette.plum).padding(.top, 6)
                        }
                    RoundedRectangle(cornerRadius: 6).fill(Palette.green).frame(width: 64, height: 104)
                }
                Text("Eaten").font(.footnote).foregroundStyle(Palette.muted)
            }
        }
    }

    private func bar(_ name: String, height: CGFloat, _ color: () -> Color) -> some View {
        VStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 6).fill(color()).frame(width: 64, height: height)
            Text(name).font(.footnote).foregroundStyle(Palette.muted)
        }
    }
}

private struct WeekOfDeficitPicture: View {
    var unit: WeightUnit

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 5) {
                ForEach(Array(["M", "T", "W", "T", "F", "S", "S"].enumerated()), id: \.offset) { _, day in
                    VStack(spacing: 4) {
                        Text("−500")
                            .font(.number(13, relativeTo: nil))
                            .foregroundStyle(Palette.panel)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(Palette.green, in: RoundedRectangle(cornerRadius: 6))
                        Text(day).font(.caption2).foregroundStyle(Palette.muted)
                    }
                }
            }
            Text("7 × 500 = 3,500 calories")
                .font(.number(18, relativeTo: nil))
                .foregroundStyle(Palette.ink)
            Text(unit == .kg ? "≈ 0.5 kg a week" : "≈ 1 lb a week")
                .font(.number(26, weight: .bold, relativeTo: nil))
                .foregroundStyle(Palette.green)
        }
    }
}

private struct LogExamplePicture: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var logged = false

    private let target = MacroTargets.defaults.calories
    private let meal = 290

    var body: some View {
        VStack(spacing: 10) {
            HStack(alignment: .lastTextBaseline, spacing: 8) {
                Text((logged ? target - meal : target).formatted())
                    .font(.number(40, weight: .bold, relativeTo: nil))
                    .foregroundStyle(Palette.ink)
                    .contentTransition(.numericText(countsDown: true))
                Text("calories left today").font(.footnote).foregroundStyle(Palette.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text("2 eggs and toast")
                .padding(.horizontal, 12).padding(.vertical, 8)
                .foregroundStyle(Palette.panel)
                .background(Palette.green, in: RoundedRectangle(cornerRadius: 14))
                .frame(maxWidth: .infinity, alignment: .trailing)
            Text("Logged Breakfast: \(meal) cal")
                .font(.subheadline)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .foregroundStyle(Palette.ink)
                .background(Palette.track, in: RoundedRectangle(cornerRadius: 14))
                .frame(maxWidth: .infinity, alignment: .leading)
                .opacity(logged ? 1 : 0)
        }
        .task {
            // Plays once when the card comes into view; Reduce Motion shows the end state.
            if reduceMotion { logged = true; return }
            try? await Task.sleep(for: .seconds(0.8))
            withAnimation(.easeOut(duration: 0.6)) { logged = true }
        }
    }
}

private struct SourcesPicture: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("This week").font(.headline).foregroundStyle(Palette.ink)
            GeometryReader { geometry in
                HStack(spacing: 2) {
                    Rectangle().fill(SourceFill(source: .label)).frame(width: geometry.size.width * 0.70)
                    Rectangle().fill(SourceFill(source: .estimate)).frame(width: geometry.size.width * 0.12)
                    Rectangle().fill(SourceFill(source: .photoEstimate))
                }
                .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            .frame(height: 34)
            SourceLegend()
            Text("30% of calories this week were estimates.")
                .font(.footnote)
                .foregroundStyle(Palette.muted)
        }
    }
}

private struct WeightTrendPicture: View {
    /// Two weeks of made-up daily weights: drifting down, with day-to-day noise.
    private static let daily: [Double] = [182.4, 183.1, 181.9, 182.6, 181.2, 182.0, 181.5,
                                          180.4, 181.6, 180.8, 179.9, 180.9, 179.6, 180.2]

    private static var average: [(day: Int, value: Double)] {
        (6..<daily.count).map { day in
            (day, daily[(day - 6)...day].reduce(0, +) / 7)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Chart {
                ForEach(Array(Self.daily.enumerated()), id: \.offset) { day, value in
                    PointMark(x: .value("Day", day), y: .value("Weight", value))
                        .foregroundStyle(Palette.muted)
                        .symbolSize(24)
                }
                ForEach(Self.average, id: \.day) { point in
                    LineMark(x: .value("Day", point.day), y: .value("Average", point.value))
                        .foregroundStyle(Palette.green)
                        .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round))
                        .interpolationMethod(.monotone)
                }
            }
            .chartYScale(domain: 179...184)
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .frame(height: 120)
            HStack(spacing: 16) {
                legend(Circle().fill(Palette.muted).frame(width: 8, height: 8), "Daily weigh-ins")
                legend(Capsule().fill(Palette.green).frame(width: 18, height: 4), "7-day average")
            }
            .font(.footnote)
            .foregroundStyle(Palette.muted)
        }
    }

    private func legend(_ mark: some View, _ text: String) -> some View {
        HStack(spacing: 6) { mark; Text(text) }
    }
}

// MARK: Key tutorial

private struct DirectPicture: View {
    var body: some View {
        HStack(spacing: 10) {
            Symbol("iphone", size: 48)
            Image(systemName: "arrow.right").font(.title2).foregroundStyle(Palette.muted)
            Image(systemName: "server.rack")
                .font(.system(size: 34))
                .foregroundStyle(Palette.muted.opacity(0.6))
                .overlay { Image(systemName: "xmark").font(.system(size: 44, weight: .light)).foregroundStyle(Palette.plum) }
            Image(systemName: "arrow.right").font(.title2).foregroundStyle(Palette.muted)
            Text("Anthropic")
                .font(.headline)
                .foregroundStyle(Palette.ink)
                .padding(.horizontal, 10).padding(.vertical, 8)
                .background(Palette.track, in: RoundedRectangle(cornerRadius: 10))
        }
        .minimumScaleFactor(0.7)
        .lineLimit(1)
    }
}

private struct CostPicture: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Usage and cost").font(.headline).foregroundStyle(Palette.ink)
            row("This month", "84 messages")
            row("Estimated cost", "about $0.70")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func row(_ name: String, _ value: String) -> some View {
        HStack {
            Text(name).foregroundStyle(Palette.muted)
            Spacer()
            Text(value).font(.number(20, relativeTo: nil)).foregroundStyle(Palette.ink)
        }
    }
}

private struct BillingPicture: View {
    var body: some View {
        HStack(spacing: 40) {
            labelled("creditcard.fill", "Add credit")
            labelled("gauge.with.needle.fill", "Spend limit")
        }
    }

    private func labelled(_ symbol: String, _ text: String) -> some View {
        VStack(spacing: 8) {
            Symbol(symbol, size: 52)
            Text(text).font(.footnote).foregroundStyle(Palette.muted)
        }
    }
}

private struct CreateKeyPicture: View {
    private var appName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "This app"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Create key").font(.headline).foregroundStyle(Palette.ink)
            field("Name", "\(appName) iPhone")
            field("Expires", "Never")
            HStack {
                Text("sk-ant-api03-••••••••").monospaced().foregroundStyle(Palette.ink)
                Spacer()
                Image(systemName: "doc.on.doc").foregroundStyle(Palette.green)
            }
            .padding(10)
            .background(Palette.track, in: RoundedRectangle(cornerRadius: 8))
        }
        .font(.subheadline)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func field(_ name: String, _ value: String) -> some View {
        HStack {
            Text(name).foregroundStyle(Palette.muted)
            Spacer()
            Text(value).foregroundStyle(Palette.ink)
        }
    }
}

private struct KeySafetyPicture: View {
    var body: some View {
        VStack(spacing: 14) {
            Symbol("lock.fill", size: 52)
            Text("sk-ant-…a1b2")
                .font(.title3.monospaced())
                .foregroundStyle(Palette.ink)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(Palette.track, in: Capsule())
        }
    }
}

private struct OneKeyPicture: View {
    var body: some View {
        HStack(spacing: 18) {
            phone
            VStack(spacing: 18) { phone; Symbol("key.horizontal.fill", size: 44); phone }
            phone
        }
    }

    private var phone: some View {
        Image(systemName: "iphone").font(.system(size: 30)).foregroundStyle(Palette.muted)
    }
}

// MARK: Pieces

private struct Symbol: View {
    var name: String
    var size: CGFloat

    init(_ name: String, size: CGFloat) {
        self.name = name
        self.size = size
    }

    var body: some View {
        Image(systemName: name)
            .font(.system(size: size))
            .foregroundStyle(Palette.green)
    }
}

private struct IconRow: View {
    var names: [String]

    init(_ names: [String]) { self.names = names }

    var body: some View {
        HStack(spacing: 14) {
            ForEach(Array(names.enumerated()), id: \.offset) { index, name in
                if index > 0 {
                    Image(systemName: "arrow.left.and.right").foregroundStyle(Palette.muted)
                }
                Symbol(name, size: 46)
            }
        }
    }
}
