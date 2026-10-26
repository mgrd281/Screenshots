import EventKit
import EventKitUI
import SwiftUI

/// The calendar's own form for a new event, filled in for a payment due
/// (`PaymentDue`): iOS shows it apart from Snapfly and adds the event only
/// when the owner taps Add, so Snapfly asks for no access to the calendar
/// and sees nothing in it. The day to pay by is a whole day, with an alert
/// at 9:00 the day before; the title names the company to pay, and the
/// notes hold the amount and the document's number, as the page writes
/// them. `done` is told whether the event was added.
struct PaymentReminderForm: UIViewControllerRepresentable {
    let due: PaymentDue.Found
    let done: (Bool) -> Void

    /// The event's title: "Musterfirma GmbH bezahlen", or "Zahlung fällig"
    /// where the page names no company.
    static func title(of due: PaymentDue.Found) -> String {
        due.payee.map { String(format: L("Pay %@"), $0) } ?? L("Payment Due")
    }

    /// The event's notes: the amount and the number, each on a line.
    static func notes(of due: PaymentDue.Found) -> String {
        [due.amount.map { String(format: L("Amount: %@"), $0) },
         due.reference.map { String(format: L("Invoice number: %@"), $0) }].compactMap { $0 }.joined(separator: "\n")
    }

    func makeUIViewController(context: Context) -> EKEventEditViewController {
        let store = EKEventStore()
        let event = EKEvent(eventStore: store)
        event.title = Self.title(of: due)
        event.notes = Self.notes(of: due)
        event.isAllDay = true
        let day = due.day.date(in: .current) ?? .now
        event.startDate = day
        event.endDate = day
        // 9:00 the day before, counted from the day's start.
        event.addAlarm(EKAlarm(relativeOffset: -15 * 60 * 60))
        let form = EKEventEditViewController()
        form.eventStore = store
        form.event = event
        form.editViewDelegate = context.coordinator
        return form
    }

    func updateUIViewController(_ form: EKEventEditViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(done: done) }

    final class Coordinator: NSObject, EKEventEditViewDelegate {
        let done: (Bool) -> Void

        init(done: @escaping (Bool) -> Void) {
            self.done = done
        }

        func eventEditViewController(_ controller: EKEventEditViewController, didCompleteWith action: EKEventEditViewAction) {
            done(action == .saved)
        }
    }
}
