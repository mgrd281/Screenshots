import XCTest
@testable import Tendedero

/// The page a time stamp names: its whole address, without a user name or
/// password, and its host where only the website is wanted. Pure text, so
/// it runs anywhere, Linux too.
final class StampSiteTests: XCTestCase {
    func testTheWholeAddressIsKept() {
        let review = "https://businessapp.b2b.trustpilot.com/reviews?filter=1#review-42"
        XCTAssertEqual(StampSite.address(of: review), review)
        XCTAssertEqual(StampSite.address(of: "https://www.kaufland.de/shops/LLC/"), "https://www.kaufland.de/shops/LLC/")
    }

    func testAUserNameAndPasswordAreLeftOutOfTheAddress() {
        XCTAssertEqual(StampSite.address(of: "https://lena:geheim@shop.example.com:8443/reset?code=482913"),
                       "https://shop.example.com:8443/reset?code=482913")
    }

    func testTheAddressHasItsSchemeAndHostInLowerCase() {
        XCTAssertEqual(StampSite.address(of: "HTTPS://Mail.Google.COM./Inbox"), "https://mail.google.com/Inbox")
        XCTAssertEqual(StampSite.address(of: "  http://example.com  "), "http://example.com")
    }

    /// A stamp from before kept the host alone; it reads as the site's address.
    func testAHostAloneBecomesAnAddress() {
        XCTAssertEqual(StampSite.address(of: "www.kaufland.de"), "https://www.kaufland.de")
    }

    func testWhatIsNoWebsiteHasNoAddress() {
        XCTAssertNil(StampSite.address(of: "file:///Users/lena/Documents/Kontoauszug.pdf"))
        XCTAssertNil(StampSite.address(of: "about:blank"))
        XCTAssertNil(StampSite.address(of: "chrome://settings/passwords"))
        XCTAssertNil(StampSite.address(of: ""))
    }

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
