import XCTest
@testable import Tendedero

/// A photo handed from the Mac to the iPhone: its length, then its bytes,
/// and read back the same.
final class PhotoHandoffTests: XCTestCase {
    func testTheLengthReadsBackAsWritten() {
        let header = PhotoHandoff.header(for: 1_234_567)
        XCTAssertEqual(header.count, 8)
        XCTAssertEqual(PhotoHandoff.length(of: header), 1_234_567)
        // The largest byte first.
        XCTAssertEqual(Array(PhotoHandoff.header(for: 258)), [0, 0, 0, 0, 0, 0, 1, 2])
    }

    func testALengthThatIsNoneOrTooMuchIsRefused() {
        XCTAssertNil(PhotoHandoff.length(of: PhotoHandoff.header(for: 0)))
        XCTAssertNil(PhotoHandoff.length(of: PhotoHandoff.header(for: PhotoHandoff.largest + 1)))
        XCTAssertNil(PhotoHandoff.length(of: Data([1, 2, 3])))
        XCTAssertEqual(PhotoHandoff.length(of: PhotoHandoff.header(for: PhotoHandoff.largest)), PhotoHandoff.largest)
    }

    func testAPhotoGoesThroughWhole() throws {
        // Larger than one piece of the copying, so it goes in several.
        let photo = Data((0..<200_000).map { UInt8($0 % 251) })
        let output = OutputStream(toMemory: ())
        output.open()
        XCTAssertTrue(PhotoHandoff.framed(photo, into: output))
        let written = try XCTUnwrap(output.property(forKey: .dataWrittenToMemoryStreamKey) as? Data)
        output.close()
        XCTAssertEqual(written.count, 8 + photo.count)
        XCTAssertEqual(PhotoHandoff.receive(from: InputStream(data: written)), photo)
    }

    func testNothingIsNotSent() {
        let output = OutputStream(toMemory: ())
        output.open()
        XCTAssertFalse(PhotoHandoff.framed(Data(), into: output))
        output.close()
    }

    func testAStreamThatEndsEarlyGivesNothing() {
        let photo = Data(repeating: 7, count: 1000)
        let cut = PhotoHandoff.header(for: photo.count) + photo.prefix(500)
        XCTAssertNil(PhotoHandoff.receive(from: InputStream(data: cut)))
        XCTAssertNil(PhotoHandoff.receive(from: InputStream(data: Data())))
    }
}
