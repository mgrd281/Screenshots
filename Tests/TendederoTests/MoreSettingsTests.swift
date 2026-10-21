import XCTest
@testable import Tendedero

/// The iPhone's More tab moved its settings onto pages of their own, under
/// the keys they always had: a value kept by an earlier Snapfly reads the
/// same, and one set now is kept where it was. And the Cover Style preview
/// leaves the digits the covering leaves.
final class MoreSettingsTests: XCTestCase {
    private let keys = ["coverStyle", "keepLastDigits", "strongestCover", "intelligenceOff"]
    private var saved: [String: Any] = [:]

    override func setUp() {
        for key in keys {
            if let value = UserDefaults.standard.object(forKey: key) { saved[key] = value }
        }
    }

    override func tearDown() {
        for key in keys {
            if let value = saved[key] {
                UserDefaults.standard.set(value, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
    }

    func testValuesKeptBeforeReadTheSame() {
        let defaults = UserDefaults.standard
        defaults.set("pixels", forKey: "coverStyle")
        defaults.set(true, forKey: "keepLastDigits")
        defaults.set(true, forKey: "strongestCover")
        defaults.set(true, forKey: "intelligenceOff")
        XCTAssertEqual(CoverStyle.current, .pixels)
        XCTAssertTrue(Finder.keepsLastDigits)
        XCTAssertTrue(Finder.strongest)
        XCTAssertFalse(Finder.usesIntelligence)
    }

    func testValuesSetNowAreKeptWhereTheyWere() {
        let defaults = UserDefaults.standard
        CoverStyle.current = .dots
        Finder.keepsLastDigits = false
        Finder.strongest = false
        Finder.usesIntelligence = true
        XCTAssertEqual(defaults.string(forKey: "coverStyle"), "dots")
        XCTAssertEqual(defaults.object(forKey: "keepLastDigits") as? Bool, false)
        XCTAssertEqual(defaults.object(forKey: "strongestCover") as? Bool, false)
        XCTAssertEqual(defaults.object(forKey: "intelligenceOff") as? Bool, false)
    }

    func testWithNothingKeptTheDefaultsAreAsBefore() {
        keys.forEach(UserDefaults.standard.removeObject(forKey:))
        XCTAssertEqual(CoverStyle.current, .ink)
        XCTAssertFalse(Finder.keepsLastDigits)
        XCTAssertFalse(Finder.strongest)
        XCTAssertTrue(Finder.usesIntelligence)
    }

    func testThePreviewLeavesTheDigitsTheCoveringLeaves() {
        let lines = CoverSampleLine.invoice
        let name = lines[0], iban = lines[1], phone = lines[2]
        XCTAssertEqual(iban.split(keepsLastDigits: false, strongest: false).kept, "")
        XCTAssertEqual(iban.split(keepsLastDigits: true, strongest: false).kept, "30 00")
        XCTAssertEqual(iban.split(keepsLastDigits: true, strongest: false).covered, "DE89 3704 0044 0532 01")
        XCTAssertEqual(phone.split(keepsLastDigits: true, strongest: false).kept, "4567")
        XCTAssertEqual(name.split(keepsLastDigits: true, strongest: false).kept, "", "a name keeps nothing")
        // Strongest protection covers whole lines, the last four digits too.
        XCTAssertEqual(iban.split(keepsLastDigits: true, strongest: true).kept, "")
        XCTAssertEqual(phone.split(keepsLastDigits: true, strongest: true).covered, phone.value)
        // As the covering itself works it out.
        let value = iban.value as NSString
        let range = Finder.keepingLastDigits(NSRange(location: 0, length: value.length), in: iban.value)
        XCTAssertEqual(range.map { value.substring(with: $0) }, iban.split(keepsLastDigits: true, strongest: false).covered)
    }
}
