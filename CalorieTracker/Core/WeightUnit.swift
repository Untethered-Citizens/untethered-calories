import Foundation

/// Display unit for body weight. Weights are stored in lb; conversion happens only for display.
enum WeightUnit: String, CaseIterable, Identifiable, Sendable {
    case lb, kg

    var id: String { rawValue }

    static let kgPerLb = 0.45359237

    /// Converts a stored lb value to this unit.
    func fromPounds(_ pounds: Double) -> Double {
        self == .lb ? pounds : pounds * WeightUnit.kgPerLb
    }

    /// Converts a value in this unit back to lb for storage.
    func toPounds(_ value: Double) -> Double {
        self == .lb ? value : value / WeightUnit.kgPerLb
    }
}
