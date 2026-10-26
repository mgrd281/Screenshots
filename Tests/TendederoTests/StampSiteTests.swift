import XCTest
@testable import Tendedero

/// The website a time stamp names: the host alone, whatever the rest of the
/// page's address holds. Pure text, so it runs anywhere, Linux too.
final class StampSiteTests: XCTestCase {
    func testOnlyTheHostIsKept() {
        let mail = "https://mail.google.com/mail/u/0/?token=a1B2c3#search/lena.hoffmann%40example.com"
        XCTAssertEqual(StampSite.host(of: mail), "mail.google.com")
        XCTAssertEqual(StampSite.host(of: "https://admin.shopify.com/store/muster/orders?query=Lena+Hoffmann"),
                       "admin.shopify.com")
    }

    func testWhoSignedInAndThePortAreLeftOut() {
        XCTAssertEqual(StampSite.host(of: "https://lena:geheim@shop.example.com:8443/reset?code=482913"),
                       "shop.example.com")
    }

    func testTheHostIsInLowerCaseWithoutItsLastDot() {
        XCTAssertEqual(StampSite.host(of: "HTTPS://Mail.Google.COM./"), "mail.google.com")
        XCTAssertEqual(StampSite.host(of: "  http://example.com  "), "example.com")
    }

    /// What a stamp keeps now is read the same way again.
    func testAHostAloneGivesItselfBack() {
        XCTAssertEqual(StampSite.host(of: "www.kaufland.de"), "www.kaufland.de")
        let once = StampSite.host(of: "https://www.kaufland.de/shops/LLC/")
        XCTAssertEqual(once, "www.kaufland.de")
        XCTAssertEqual(once.flatMap(StampSite.host(of:)), "www.kaufland.de")
    }

    func testWhatIsNoWebsiteNamesNothing() {
        XCTAssertNil(StampSite.host(of: "file:///Users/lena/Documents/Kontoauszug.pdf"))
        XCTAssertNil(StampSite.host(of: "about:blank"))
        XCTAssertNil(StampSite.host(of: "chrome://settings/passwords"))
        XCTAssertNil(StampSite.host(of: ""))
    }
}
