import Testing
@testable import CalorieTracker

struct WeekChartScaleTests {
    @Test func ordinaryWeekKeepsTargetHeadroom() {
        #expect(WeekChart.scaleTop(target: 1785, highest: 1900) == 2499)
        #expect(WeekChart.scaleTop(target: 1785, highest: 0) == 2499)
    }

    @Test func tallestBarAlwaysLeavesRoomForItsLabel() {
        // Issue #20: 2,520 against a 1,785 target used to set the top at exactly 2,520.
        for highest in [2400, 2499, 2520, 4000] {
            let top = WeekChart.scaleTop(target: 1785, highest: highest)
            #expect(Double(top) >= Double(highest) * 1.12)
        }
    }
}
