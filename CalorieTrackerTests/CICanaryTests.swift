import Testing

// Temporary: fails on purpose to prove CI turns red. Removed before merge (#53).
struct CICanaryTests {
    @Test func failsOnPurpose() {
        #expect(1 + 1 == 3)
    }
}
