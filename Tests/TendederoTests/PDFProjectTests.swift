import XCTest
@testable import Tendedero

/// A PDF put together from made-up files: pages keep the order they were
/// added in, pictures are never stretched or cut, every page operation can
/// be undone and redone step by step, and a project written to disk opens
/// again as it was.
final class PDFProjectTests: XCTestCase {
    private static let invoice = ProjectFile(kind: .pdf, name: "Rechnung.pdf", stored: "a.pdf", pageCount: 3, digest: "00")
    private static let receipt = ProjectFile(kind: .picture, name: "IMG_0001.HEIC", stored: "b.heic", pageCount: 1, digest: "01")
    private static let letter = ProjectFile(kind: .picture, name: "Scan.jpg", stored: "c.jpg", pageCount: 1, digest: "02")

    /// A PDF of three pages, a photo of a receipt and a scanned letter, added in that order.
    private static func project() -> PDFProject {
        var project = PDFProject(name: "Rechnung März", files: [invoice, receipt, letter])
        project.insert(invoice.pages(origin: .file))
        project.insert(receipt.pages(origin: .photo, kind: .receipt))
        project.insert(letter.pages(origin: .scan, kind: .letter))
        return project
    }

    private func labels(_ project: PDFProject) -> [String] {
        project.pages.map(project.label(of:))
    }

    func testMixedSourcesKeepTheirOrder() {
        let project = Self.project()
        XCTAssertEqual(labels(project), ["Rechnung.pdf · p. 1", "Rechnung.pdf · p. 2", "Rechnung.pdf · p. 3",
                                         "Photo · Receipt", "Scanned · Letter"])
        XCTAssertTrue(project.hasPictures)
        // A kind read later, by the picture's file.
        var read = project
        read.pages[3].source = .picture(file: Self.receipt.id, origin: .photo, kind: nil)
        XCTAssertEqual(read.label(of: read.pages[3]), "Photo")
        read.kinds[Self.receipt.id.uuidString] = .receipt
        XCTAssertEqual(read.label(of: read.pages[3]), "Photo · Receipt")
        // Added in the middle, after the second page.
        var more = project
        more.insert([ProjectPage(source: .blank(width: 595.28, height: 841.89))], at: 2)
        XCTAssertEqual(labels(more)[2], "Blank Page")
        XCTAssertEqual(labels(more)[3], "Rechnung.pdf · p. 3")
    }

    func testPicturesAreNeverStretchedOrCut() {
        let shapes: [(Int, Int)] = [(400, 2000), (3000, 2000), (1000, 1000), (2480, 3508), (5000, 300)]
        for paper in PaperSize.allCases {
            for (width, height) in shapes {
                let layout = paper.layout(width: width, height: height)
                let picture = layout.picture
                let aspect = Double(width) / Double(height)
                XCTAssertEqual(Double(picture.width / picture.height), aspect, accuracy: 0.0005,
                               "\(paper) \(width)×\(height) keeps its shape")
                let page = CGRect(origin: .zero, size: layout.page)
                XCTAssertTrue(page.insetBy(dx: -0.01, dy: -0.01).contains(picture), "\(paper) never cut")
                if paper == .original {
                    XCTAssertEqual(picture, page, "a page of the picture's own shape")
                    XCTAssertEqual(max(layout.page.width, layout.page.height), PaperSize.a4Size.height, accuracy: 0.01)
                } else {
                    let room = page.insetBy(dx: PaperSize.margin, dy: PaperSize.margin)
                    XCTAssertTrue(room.insetBy(dx: -0.01, dy: -0.01).contains(picture), "\(paper) keeps 10 mm round it")
                    XCTAssertEqual(picture.midX, page.midX, accuracy: 0.01)
                    XCTAssertEqual(picture.midY, page.midY, accuracy: 0.01)
                    XCTAssertEqual(layout.page.width > layout.page.height, width > height, "turned as the picture is")
                    // It touches the room on one side at least, as large as it can be.
                    let fills = abs(picture.width - room.width) < 0.01 || abs(picture.height - room.height) < 0.01
                    XCTAssertTrue(fills)
                }
            }
        }
        // A narrow receipt on A4 stays narrow, the whole height of the room.
        let receipt = PaperSize.a4.layout(width: 400, height: 2000)
        XCTAssertEqual(receipt.page, PaperSize.a4Size)
        XCTAssertLessThan(receipt.picture.width, 200)
    }

    func testPageOperations() {
        var project = Self.project()
        let ids = project.pages.map(\.id)

        // One page moved, the others closing up.
        project.move(from: 3, to: 0)
        XCTAssertEqual(project.pages.map(\.id), [ids[3], ids[0], ids[1], ids[2], ids[4]])
        // Several moved together, in their order.
        project.move([ids[4], ids[0]], to: 1)
        XCTAssertEqual(project.pages.map(\.id), [ids[3], ids[0], ids[4], ids[1], ids[2]])

        // Turned a quarter at a time, round to upright again.
        project.turn([ids[1]])
        project.turn([ids[1]], by: 3)
        XCTAssertEqual(project.pages[project.index(of: ids[1])!].turns, 0)
        project.turn([ids[1]], by: -1)
        XCTAssertEqual(project.pages[project.index(of: ids[1])!].turns, 3)

        // A copy right after each page, turned as it is.
        let copies = project.duplicate([ids[1], ids[3]])
        XCTAssertEqual(copies.count, 2)
        XCTAssertEqual(project.pages.count, 7)
        XCTAssertEqual(project.pages[1].id, copies[0], "after the receipt")
        XCTAssertEqual(project.pages[1].source, project.pages[0].source)
        let second = project.index(of: ids[1])!
        XCTAssertEqual(project.pages[second + 1].id, copies[1])
        XCTAssertEqual(project.pages[second + 1].turns, 3)

        // Taken away, and an empty page put in.
        project.openPage = copies[0]
        project.remove(Set(copies))
        XCTAssertEqual(project.pages.map(\.id), [ids[3], ids[0], ids[4], ids[1], ids[2]])
        XCTAssertNil(project.openPage, "the page open went")
        let blank = project.insertBlank(at: 5, size: PaperSize.a4Size)
        XCTAssertEqual(project.pages.last?.id, blank)
        XCTAssertEqual(project.pages.last?.source, .blank(width: 595.28, height: 841.89))

        // Only the pages chosen, in the project's order, as for "Als PDF".
        let part = project.only([ids[2], ids[3]])
        XCTAssertEqual(part.pages.map(\.id), [ids[3], ids[2]])
        XCTAssertEqual(part.files, project.files)

        // A file no page shows any more.
        project.remove([ids[4]])
        XCTAssertEqual(project.unused.map(\.name), ["Scan.jpg"])
    }

    func testUndoAndRedoRestoreEveryStep() {
        var project = Self.project()
        var history = ProjectHistory()
        let ids = project.pages.map(\.id)
        var steps = [project.pages]
        let changes: [(inout PDFProject) -> Void] = [
            { $0.move(from: 0, to: 4) },
            { $0.turn([ids[2]]) },
            { _ = $0.duplicate([ids[3]]) },
            { $0.remove([ids[0], ids[1]]) },
            { _ = $0.insertBlank(at: 1, size: PaperSize.letterSize) },
            { $0.move([ids[4]], to: 0) },
        ]
        for change in changes {
            let before = project.pages
            change(&project)
            XCTAssertNotEqual(project.pages, before)
            history.record(before)
            steps.append(project.pages)
        }
        XCTAssertTrue(history.canUndo)
        XCTAssertFalse(history.canRedo)
        // Back, one step at a time, to how it began.
        for step in steps.dropLast().reversed() {
            guard let back = history.undo(project.pages) else { return XCTFail("nothing to undo") }
            project.pages = back
            XCTAssertEqual(project.pages, step)
        }
        XCTAssertNil(history.undo(project.pages))
        // Forward again, one step at a time, to the last.
        for step in steps.dropFirst() {
            guard let forward = history.redo(project.pages) else { return XCTFail("nothing to redo") }
            project.pages = forward
            XCTAssertEqual(project.pages, step)
        }
        XCTAssertNil(history.redo(project.pages))
        // A new change after an undo forgets what could be redone.
        project.pages = history.undo(project.pages)!
        history.record(project.pages)
        project.turn([ids[3]])
        XCTAssertFalse(history.canRedo)
    }

    func testAProjectOpensAgainAsItWasWritten() throws {
        var project = Self.project()
        project.turn([project.pages[1].id])
        project.openPage = project.pages[2].id
        project.paper = .a4
        project.quality = .high
        project.kinds[Self.letter.id.uuidString] = .letter
        // What the owner covered by hand on a page: a box, a stroke and a place only offered.
        let page = project.pages[4].id
        project.covers[page.uuidString] = [
            KeptCover(rect: CGRect(x: 0.1, y: 0.8, width: 0.3, height: 0.04), shape: .box(CGRect(x: 0.1, y: 0.8, width: 0.3, height: 0.04), angle: 0)),
            KeptCover(rect: CGRect(x: 0.2, y: 0.4, width: 0.4, height: 0.05),
                      shape: .stroke([CGPoint(x: 0.22, y: 0.42), CGPoint(x: 0.58, y: 0.43)], width: 0.035)),
            KeptCover(rect: CGRect(x: 0.5, y: 0.1, width: 0.2, height: 0.03), shape: nil),
        ]
        let data = try JSONEncoder().encode(project)
        let read = try JSONDecoder().decode(PDFProject.self, from: data)
        XCTAssertEqual(read, project)
        XCTAssertEqual(read.openPage, project.openPage)
        XCTAssertEqual(read.paper, .a4)
        XCTAssertEqual(read.quality, .high)
        XCTAssertEqual(read.hand(on: page).count, 3, "every cover kept, shapes and all")
        XCTAssertTrue(read.hand(on: project.pages[0].id).isEmpty)
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("Lena"), "where, never a word")
        // Written before the paper and the quality were kept: their defaults.
        let older = Data("""
        {"id":"\(project.id.uuidString)","name":"Alt","created":800000000,"files":[],"pages":[]}
        """.utf8)
        let old = try JSONDecoder().decode(PDFProject.self, from: older)
        XCTAssertEqual(old.paper, .original)
        XCTAssertEqual(old.quality, .medium)
        XCTAssertEqual(old.modified, old.created)
        XCTAssertTrue(old.covers.isEmpty, "written before covers were kept: none")
    }

    /// A page turned a quarter: what the owner covered on it turns with it,
    /// its box standing for the shape drawn.
    func testACoverKeptTurnsWithItsPage() {
        let cover = KeptCover(rect: CGRect(x: 0.1, y: 0.7, width: 0.3, height: 0.1),
                              shape: .stroke([CGPoint(x: 0.12, y: 0.75), CGPoint(x: 0.38, y: 0.75)], width: 0.02))
        let turned = cover.turned(by: 1)
        XCTAssertNil(turned.shape)
        XCTAssertEqual(turned.rect, PDFPageGeometry.turned(cover.rect, quarters: 1))
        XCTAssertEqual(cover.turned(by: 4), cover, "a whole turn changes nothing")
        let back = cover.turned(by: 1).turned(by: 3).rect
        XCTAssertEqual(back.minX, cover.rect.minX, accuracy: 0.0001)
        XCTAssertEqual(back.minY, cover.rect.minY, accuracy: 0.0001)
        XCTAssertEqual(back.width, cover.rect.width, accuracy: 0.0001)
    }

    func testNames() {
        let date = DateComponents(calendar: Calendar(identifier: .gregorian), timeZone: TimeZone(identifier: "GMT"),
                                  year: 2026, month: 3, day: 9, hour: 12).date!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "GMT")!
        let project = Self.project()
        XCTAssertEqual(ProjectNaming.name(files: project.files, pages: project.pages, at: date), "Rechnung")
        XCTAssertEqual(ProjectNaming.name(files: [Self.receipt], pages: Self.receipt.pages(origin: .photo, kind: .receipt), at: date),
                       "Receipt")
        XCTAssertEqual(ProjectNaming.name(files: [], pages: [], at: date, calendar: calendar), "Document 09.03.2026")
        XCTAssertEqual(ProjectNaming.pages(1), "1 page")
        XCTAssertEqual(ProjectNaming.pages(6), "6 pages")
    }

    func testQualityAndSize() {
        // Never more pixels than a picture has.
        let small = ExportQuality.high.pixels(width: 800, height: 1200, filling: PaperSize.a4Size)
        XCTAssertEqual(small.width, 800)
        XCTAssertEqual(small.height, 1200)
        // Fewer where it has more than the quality needs, its shape kept.
        let large = ExportQuality.small.pixels(width: 4000, height: 6000, filling: CGSize(width: 400, height: 600))
        XCTAssertEqual(large.height, 1250)
        XCTAssertEqual(large.width, 833)
        XCTAssertEqual(ExportQuality.medium.pixels(for: PaperSize.a4Size).width, 1654)
        XCTAssertGreaterThan(ExportQuality.high.jpeg, ExportQuality.medium.jpeg)
        XCTAssertGreaterThan(ExportQuality.medium.jpeg, ExportQuality.small.jpeg)

        XCTAssertEqual(SizeEstimate.sample(count: 3), [0, 1, 2])
        XCTAssertEqual(SizeEstimate.sample(count: 300), [0, 100, 199, 299])
        XCTAssertEqual(SizeEstimate.sample(count: 0), [])
        XCTAssertEqual(SizeEstimate.bytes(sampled: [100_000, 300_000], count: 10), 2_000_000 + SizeEstimate.overhead)
        XCTAssertNil(SizeEstimate.bytes(sampled: [], count: 10))
        XCTAssertEqual(PaperSize.blank(region: "US"), PaperSize.letterSize)
        XCTAssertEqual(PaperSize.blank(region: "DE"), PaperSize.a4Size)
        XCTAssertEqual(PaperSize.blank(region: nil), PaperSize.a4Size)
    }
}

/// Where things on a PDF page are once it is shown turned, its words read
/// straight from its text, and whether it is signed.
final class PDFPageGeometryTests: XCTestCase {
    private func assertClose(_ a: CGPoint, _ b: CGPoint, _ message: String = "", line: UInt = #line) {
        XCTAssertEqual(a.x, b.x, accuracy: 0.0001, message, line: line)
        XCTAssertEqual(a.y, b.y, accuracy: 0.0001, message, line: line)
    }

    func testRotationsAddUp() {
        XCTAssertEqual(PDFPageGeometry.rotation(page: 0, turns: 0), 0)
        XCTAssertEqual(PDFPageGeometry.rotation(page: 90, turns: 1), 180)
        XCTAssertEqual(PDFPageGeometry.rotation(page: 270, turns: 3), 180)
        XCTAssertEqual(PDFPageGeometry.rotation(page: 0, turns: -1), 270)
        XCTAssertEqual(PDFPageGeometry.rotation(page: 360, turns: 4), 0)
    }

    func testCornersGoWhereTheTurnedPageShowsThem() {
        // A4 upright, its box not at the origin, as a cropped page's is.
        let box = CGRect(x: 10, y: 20, width: 600, height: 800)
        let topLeft = CGPoint(x: 10, y: 820), bottomLeft = CGPoint(x: 10, y: 20)
        let s: CGFloat = 2
        // Upright.
        var map = PDFPageGeometry.map(box: box, rotation: 0, scale: s)
        assertClose(map.apply(bottomLeft), .zero)
        assertClose(map.apply(topLeft), CGPoint(x: 0, y: 1600))
        // A quarter clockwise: the top left goes to the top right, the bottom left to the top left.
        map = PDFPageGeometry.map(box: box, rotation: 90, scale: s)
        XCTAssertEqual(PDFPageGeometry.shown(box, rotation: 90), CGSize(width: 800, height: 600))
        assertClose(map.apply(topLeft), CGPoint(x: 1600, y: 1200))
        assertClose(map.apply(bottomLeft), CGPoint(x: 0, y: 1200))
        // Half round: the top left to the bottom right.
        map = PDFPageGeometry.map(box: box, rotation: 180, scale: s)
        assertClose(map.apply(topLeft), CGPoint(x: 1200, y: 0))
        // Three quarters: the top left to the bottom left, the bottom left to the bottom right.
        map = PDFPageGeometry.map(box: box, rotation: 270, scale: s)
        assertClose(map.apply(topLeft), .zero)
        assertClose(map.apply(bottomLeft), CGPoint(x: 1600, y: 0))
    }

    func testRectanglesAreMeasuredOnThePageAsShown() {
        let box = CGRect(x: 0, y: 0, width: 600, height: 800)
        // A word at the top left of the page.
        let word = CGRect(x: 60, y: 720, width: 120, height: 20)
        let upright = PDFPageGeometry.normalized(word, box: box, rotation: 0)
        XCTAssertEqual(upright.minX, 0.1, accuracy: 0.0001)
        XCTAssertEqual(upright.minY, 0.9, accuracy: 0.0001)
        XCTAssertEqual(upright.width, 0.2, accuracy: 0.0001)
        // Turned a quarter clockwise, it is at the top right, standing.
        let turned = PDFPageGeometry.normalized(word, box: box, rotation: 90)
        XCTAssertEqual(turned.minX, 720.0 / 800, accuracy: 0.0001)
        XCTAssertEqual(turned.maxY, 1 - 60.0 / 600, accuracy: 0.0001)
        XCTAssertEqual(turned.width, 20.0 / 800, accuracy: 0.0001)
        XCTAssertEqual(turned.height, 120.0 / 600, accuracy: 0.0001)
        // The same as turning the upright measure.
        let again = PDFPageGeometry.turned(upright, quarters: 1)
        XCTAssertEqual(again.minX, turned.minX, accuracy: 0.0001)
        XCTAssertEqual(again.minY, turned.minY, accuracy: 0.0001)
        // As a scanned page's corners turn (`ScanQuad.turned`).
        let corner = ScanQuad(topLeft: CGPoint(x: 0.1, y: 0.9), topRight: CGPoint(x: 0.3, y: 0.9),
                              bottomRight: CGPoint(x: 0.3, y: 0.85), bottomLeft: CGPoint(x: 0.1, y: 0.85)).turned(1)
        XCTAssertEqual(corner.corners.map(\.x).min()!, PDFPageGeometry.turned(CGRect(x: 0.1, y: 0.85, width: 0.2, height: 0.05),
                                                                              quarters: 1).minX, accuracy: 0.0001)
    }

    func testTheTextIsReadInLinesAndWords() {
        // A made-up address block, each letter 0.01 wide on its line.
        let text = "Erika Mustermann\nIBAN DE02 1203 0000 0000 2020 51\n\nMusterstraße 12"
        var places: [Int: CGRect] = [:]
        var line = 0, column = 0
        for (index, unit) in Array(text.utf16).enumerated() {
            if unit == 0x0A {
                line += 1
                column = 0
                continue
            }
            places[index] = CGRect(x: 0.1 + CGFloat(column) * 0.01, y: 0.9 - CGFloat(line) * 0.03, width: 0.01, height: 0.02)
            column += 1
        }
        let lines = PDFTextLayer.lines(text) { places[$0] }
        XCTAssertEqual(lines.map(\.string), ["Erika Mustermann", "IBAN DE02 1203 0000 0000 2020 51", "Musterstraße 12"])
        XCTAssertEqual(lines[0].words.count, 2)
        XCTAssertEqual(lines[0].words[1].range, NSRange(location: 6, length: 10))
        XCTAssertEqual(lines[0].words[1].box.minX, 0.16, accuracy: 0.0001)
        XCTAssertEqual(lines[0].box.width, 0.16, accuracy: 0.0001)
        XCTAssertEqual(lines[1].words.count, 7)
        XCTAssertEqual(lines[2].box.minY, 0.9 - 0.09, accuracy: 0.0001)
        XCTAssertTrue(PDFTextLayer.holdsText(text))
        XCTAssertFalse(PDFTextLayer.holdsText("Seite 1"))
    }

    func testWordsFarApartOnOneRowAreLinesOfTheirOwn() {
        // The name on the left and the invoice's number on the right, as the
        // text may give them on one row; then the same on a page turned.
        let text = "Erika Mustermann Rechnungsnr. RE-2026-0412"
        let units = Array(text.utf16)
        let right = 17
        func place(_ index: Int, turned: Bool) -> CGRect {
            let along = index < right ? 0.1 + CGFloat(index) * 0.01 : 0.6 + CGFloat(index - right) * 0.01
            return turned ? CGRect(x: 0.8, y: 1 - along - 0.01, width: 0.02, height: 0.01)
                : CGRect(x: along, y: 0.8, width: 0.01, height: 0.02)
        }
        for turned in [false, true] {
            let lines = PDFTextLayer.lines(text) { units.indices.contains($0) ? place($0, turned: turned) : nil }
            XCTAssertEqual(lines.map(\.string), ["Erika Mustermann", "Rechnungsnr. RE-2026-0412"])
            XCTAssertEqual(lines[1].words.map(\.range), [NSRange(location: 0, length: 12), NSRange(location: 13, length: 12)])
            XCTAssertEqual(lines[1].words[0].box, place(right, turned: turned)
                .union(place(right + 11, turned: turned)))
        }
        // Words a little apart stay one line.
        let near = PDFTextLayer.lines("Summe 120,00") { CGRect(x: 0.1 + CGFloat($0) * 0.015, y: 0.5, width: 0.01, height: 0.02) }
        XCTAssertEqual(near.map(\.string), ["Summe 120,00"])
    }

    func testLinesReadFromThePictureAddOnlyWhatTheTextLacks() {
        let text = [CGRect(x: 0.1, y: 0.9, width: 0.5, height: 0.02), CGRect(x: 0.1, y: 0.8, width: 0.4, height: 0.02)]
        let read = [CGRect(x: 0.1, y: 0.9, width: 0.48, height: 0.02),
                    CGRect(x: 0.2, y: 0.4, width: 0.3, height: 0.05),
                    CGRect(x: 0.45, y: 0.8, width: 0.2, height: 0.02)]
        // The first is the text's own line; the second, a photo on the page; the third half off it.
        XCTAssertEqual(PDFTextLayer.added(read: read, over: text), [1, 2])
    }

    func testASignedFileIsKnownByItsBytes() {
        let plain = Data("%PDF-1.7\n1 0 obj << /Type /Catalog >> endobj\n%%EOF".utf8)
        let signed = Data("""
        %PDF-1.7
        5 0 obj << /Type /Sig /Filter /Adobe.PPKLite /SubFilter /adbe.pkcs7.detached /ByteRange [0 100 200 50] /Contents <00> >> endobj
        %%EOF
        """.utf8)
        XCTAssertTrue(PDFFacts.isPDF(plain))
        XCTAssertFalse(PDFFacts.isPDF(Data("GIF89a".utf8)))
        XCTAssertFalse(PDFFacts.isSigned(plain))
        XCTAssertTrue(PDFFacts.isSigned(signed))
        // An empty signature field, never signed, has no byte range.
        XCTAssertFalse(PDFFacts.isSigned(Data("%PDF-1.7 << /FT /Sig /T (Unterschrift) >>".utf8)))
    }
}
