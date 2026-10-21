import SwiftUI

/// A made-up document for What Is Covered: a doctor's bill, a chat or a
/// note, with every value of a kind chosen covered in the look chosen. The
/// words around a value stay shown. It is a picture of a document, so its
/// sizes are fixed (11, 12 and 13 pt) and it is scaled as a whole; white
/// paper in light and dark alike. A cover sweeps over its value from the
/// leading edge as its kind is turned on, and goes back the same way.
struct CoverSampleDocument: View {
    let sample: CoverStudioSample
    let chosen: Set<PrivateDetail>
    let style: CoverStyle
    /// The group whose sheet is open: its values ringed, the rest dimmed.
    var focus: CoverGroup?
    /// When each kind's cover starts, as a preset runs down the page.
    var delays: [PrivateDetail: Double] = [:]

    static let size = CGSize(width: 300, height: 270)

    var body: some View {
        Group {
            switch sample {
            case .bill: bill
            case .chat: chat
            case .note: note
            }
        }
        .padding(16)
        .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
        .background(SnapflyTokens.morePaper, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .environment(\.layoutDirection, .leftToRight)
        .animation(.easeOut(duration: 0.2), value: focus)
    }

    // MARK: The three documents

    private var bill: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 3) {
                words(L("Practice Dr."), size: 12, weight: .semibold)
                value("bill.doctor", "Paul Beispiel", size: 12, weight: .semibold)
            }
            HStack(spacing: 3) {
                value("bill.email", "praxis@beispiel.de")
                words("·")
                words(L("Tel."))
                value("bill.phone", "040 1234567")
            }
            rule
            HStack(spacing: 3) {
                value("bill.patient", "Erika Muster", weight: .semibold)
                words("·")
                words(L("born"))
                value("bill.birth", "01.02.1990")
            }
            value("bill.address", "Musterstraße 12, 20095 Hamburg")
            HStack(spacing: 3) {
                words(L("Invoice no."))
                value("bill.number", "302-1234567")
            }
            .padding(.top, 4)
            HStack(spacing: 3) {
                words(L("Date:"))
                value("bill.date", "12.03.2026")
            }
            HStack(spacing: 3) {
                words(L("Diagnosis:"))
                value("bill.diagnosis", L("Blood pressure raised"))
            }
            HStack(alignment: .bottom, spacing: 8) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        words(L("Amount"))
                        value("bill.amount", "149,90 €", size: 13, weight: .bold)
                    }
                    HStack(spacing: 3) {
                        words("IBAN")
                        value("bill.iban", "DE12 3456 7890 1234")
                    }
                    value("bill.link", "beispiel.de/zahlen", color: SnapflyTokens.morePaperLink)
                }
                Spacer(minLength: 0)
                mark("bill.qr", seed: 41) {
                    Image(systemName: "qrcode")
                        .font(.system(size: 40, weight: .regular))
                        .foregroundStyle(SnapflyTokens.morePaperText)
                }
            }
            .padding(.top, 4)
        }
    }

    private var chat: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                mark("chat.face", seed: 51, round: true) {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(Color(red: 0.62, green: 0.46, blue: 0.36), Color(red: 0.98, green: 0.86, blue: 0.74))
                        .frame(width: 32, height: 32)
                }
                VStack(alignment: .leading, spacing: 1) {
                    value("chat.name", "Max Mustermann", size: 13, weight: .semibold)
                    words(L("online"), size: 10, color: SnapflyTokens.morePaperLabel)
                }
            }
            rule
            bubble(mine: false) {
                words(L("Here’s my number:"))
                value("chat.phone", "+49 170 1234567")
            }
            bubble(mine: true) {
                words(L("Your parcel:"))
                value("chat.parcel", "JJD0003900071")
            }
            bubble(mine: false) {
                words(L("Follow me at"))
                value("chat.user", "@max_m")
            }
            bubble(mine: true) {
                words(L("Meet at"))
                value("chat.company", "Musterfirma GmbH")
                words("?")
            }
        }
    }

    private var note: some View {
        VStack(alignment: .leading, spacing: 9) {
            words(L("Notes"), size: 13, weight: .bold)
            words("12.03.2026", size: 10, color: SnapflyTokens.morePaperLabel)
            rule
            line(L("Tax ID"), "note.tax", "12 345 678 901")
            line(L("Wi-Fi code"), "note.wifi", "482 913")
            line(L("API key"), "note.key", "key_7f3a9c21")
            line(L("Server IP"), "note.ip", "192.168.178.24")
            line(L("Login"), "note.login", "max@beispiel.de")
        }
    }

    // MARK: Pieces

    private var rule: some View {
        Rectangle()
            .fill(SnapflyTokens.morePaperLine)
            .frame(height: 1)
            .opacity(focus == nil ? 1 : 0.35)
    }

    private func line(_ label: String, _ id: String, _ text: String) -> some View {
        HStack(spacing: 4) {
            words(label)
                .frame(width: 74, alignment: .leading)
            value(id, text, monospaced: true)
        }
    }

    @ViewBuilder
    private func bubble<Content: View>(mine: Bool, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 0) {
            if mine { Spacer(minLength: 30) }
            HStack(spacing: 3) { content() }
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(mine ? SnapflyTokens.moreBubbleOut : SnapflyTokens.moreBubbleIn,
                            in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            if !mine { Spacer(minLength: 30) }
        }
    }

    /// Words around a value: shown as they are, dimmed while a group's
    /// sheet is open.
    private func words(_ text: String, size: CGFloat = 11, weight: Font.Weight = .regular,
                       color: Color = SnapflyTokens.morePaperText) -> some View {
        Text(verbatim: text)
            .font(.system(size: size, weight: weight))
            .foregroundStyle(color)
            .lineLimit(1)
            .fixedSize()
            .opacity(focus == nil ? 1 : 0.35)
    }

    /// A value, under its cover while its kind is chosen.
    private func value(_ id: String, _ text: String, size: CGFloat = 11, weight: Font.Weight = .regular,
                       color: Color = SnapflyTokens.morePaperText, monospaced: Bool = false) -> some View {
        mark(id, seed: Self.seed(id)) {
            Text(verbatim: text)
                .font(.system(size: size, weight: weight, design: monospaced ? .monospaced : .default))
                .foregroundStyle(color)
                .lineLimit(1)
                .fixedSize()
        }
    }

    /// Anything on the paper that a kind covers: a value, the face, the code.
    private func mark<Content: View>(_ id: String, seed: Int, round: Bool = false,
                                     @ViewBuilder content: () -> Content) -> some View {
        let kind = sample.fields.first { $0.id == id }?.kind ?? .names
        let inFocus = focus.map { $0.kinds.contains(kind) }
        return content()
            .overlay {
                SampleCover(style: style, kind: kind, on: chosen.contains(kind), delay: delays[kind] ?? 0,
                            seed: seed, round: round)
                    .padding(.horizontal, round ? 0 : -2)
                    .padding(.vertical, round ? 0 : -1)
            }
            .overlay {
                if inFocus == true {
                    RoundedRectangle(cornerRadius: round ? 20 : 4, style: .continuous)
                        .strokeBorder(SnapflyTokens.moreFocusRing, lineWidth: 2)
                        .padding(-4)
                        .transition(.opacity)
                }
            }
            .opacity(inFocus == false ? 0.35 : 1)
    }

    /// Each value's covers drawn the same way every time.
    private static func seed(_ id: String) -> Int {
        id.unicodeScalars.reduce(7) { ($0 &* 31 &+ Int($1.value)) % 9973 }
    }
}

/// A value's cover in the look chosen, as a covered copy draws it on white
/// paper (`CoverSwatch`). It sweeps in from the leading edge in 0.35 s and
/// back in 0.25 s; with Reduce Motion it fades in 0.15 s.
private struct SampleCover: View {
    let style: CoverStyle
    let kind: PrivateDetail
    let on: Bool
    let delay: Double
    let seed: Int
    let round: Bool
    @Environment(\.moreStill) private var still

    var body: some View {
        CoverSwatch(style: style, kind: kind, seed: seed)
            .clipShape(round ? AnyShape(Circle()) : AnyShape(Rectangle()))
            .scaleEffect(x: on || still ? 1 : 0.001, anchor: .leading)
            // Gone entirely while off, not a hairline at the value's edge.
            .opacity(on ? 1 : 0)
            .animation(still ? MoreMotion.fade : on ? .easeOut(duration: 0.35).delay(delay)
                       : .easeOut(duration: 0.25).delay(delay), value: on)
            .allowsHitTesting(false)
    }
}
