import Foundation
import Testing
@testable import CalorieTracker

struct AppLinksTests {
    @Test func linksAreHTTPSOnTheSiteWithNoTracking() {
        for url in AppLinks.all {
            #expect(url.scheme == "https")
            #expect(url.host() == "untetheredcalories.com")
            #expect(url.query() == nil)
            #expect(url.fragment() == nil)
        }
    }

    @Test func versionTextShowsVersionAndBuild() {
        #expect(AppLinks.versionText(info: ["CFBundleShortVersionString": "1.0", "CFBundleVersion": "12"]) == "1.0 (12)")
        #expect(AppLinks.versionText(info: nil) == "? (?)")
    }
}
