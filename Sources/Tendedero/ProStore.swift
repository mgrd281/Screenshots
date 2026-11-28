import AppKit
import Combine
import StoreKit

/// Snapfly Pro as the App Store tells it on this Mac: the ways to pay in the
/// store's own currency and words, whether Pro is on, and what the Pro window
/// shows while it asks, buys or restores. The App Store's last answer is kept
/// (`Plan.subscribedKey`), so what runs without the window, like the AI apps'
/// server, knows it too.
///
/// Only the Mac App Store edition can subscribe. The one from the website
/// never asks the App Store: its window says where Pro is bought. With the
/// made-up Pro window for the captures (`-SnapflyPro <phase>`), nothing here
/// asks the App Store either: the prices and the subscription are
/// `ProSample`'s.
@MainActor
final class ProStore: ObservableObject {
    static let shared = ProStore()

    /// The ways to pay, the year first.
    @Published private(set) var offers: [ProOffer] = []
    /// The tile chosen: the year at first.
    @Published var chosenID: String?
    /// Pro as the App Store last said it is on here.
    @Published private(set) var subscription: ProSubscription?
    /// One line over the buttons: restored, nothing found, or failed.
    @Published var note: String?
    /// What the window shows, worked out again after every change.
    @Published private(set) var phase: ProPhase = .loading
    /// Restore Purchases is asking the App Store.
    @Published private(set) var restoring = false

    var isSubscribed: Bool { subscription != nil }

    /// The offer Subscribe buys: the tile chosen, or the one chosen at first.
    var chosen: ProOffer? {
        offers.first { $0.id == chosenID } ?? ProOffers.preferred(in: offers)
    }

    /// How much less the year costs than twelve months, when it is worth saying.
    var savings: Int? { ProOffers.savings(in: offers) }

    /// Only the Mac App Store edition sells Pro.
    private let canBuy = Edition.appStore
    /// The prices are being asked for, or have not been asked for yet.
    private var loading = true
    /// A request for the prices is on its way, so a second one waits for it.
    private var asking = false
    /// The App Store's own sheet is open.
    private var buying = false
    /// Waiting for someone in the family to approve it (Ask to Buy).
    private var pending = false
    /// Subscribed in the window open now, for its welcome.
    private var justBought = false
    /// The App Store's products, by their identifiers, to buy and to read renewals from.
    private var products: [String: Product] = [:]
    /// Purchases finished elsewhere, approved later or renewed, as they come in.
    private var listener: Task<Void, Never>?
    /// The phase the made-up window shows; nil when the App Store answers.
    private var samplePhase: ProPhase? = ProSample.phase

    private init() {
        if ProSample.requested {
            offers = ProSample.offers
            chosenID = ProOffers.preferred(in: offers)?.id
            if ProSample.phase == .subscribed || ProSample.phase == .welcome {
                subscription = ProSample.subscription
            }
        }
        update()
    }

    // MARK: Asking the App Store

    /// At launch, in the App Store edition: listens for purchases made or
    /// approved elsewhere, and asks whether Pro is on, so the answer kept on
    /// the Mac stays current.
    func start() {
        guard canBuy, !ProSample.requested, listener == nil else { return }
        listener = Task { [weak self] in
            for await result in StoreKit.Transaction.updates {
                if case .verified(let transaction) = result { await transaction.finish() }
                await self?.refresh()
            }
        }
        Task { await refresh() }
    }

    /// As the Pro window opens: the prices, once, or again after they could
    /// not be had, and whether Pro is on.
    func prepare() async {
        guard canBuy, !ProSample.requested else { return }
        if offers.isEmpty { await load() }
        await refresh()
    }

    /// The products, made into offers in the store's own words. Without an
    /// answer the offers stay empty, and the window says so.
    private func load() async {
        guard !asking else { return }
        asking = true
        loading = true
        update()
        defer {
            asking = false
            loading = false
            update()
        }
        do {
            let found = try await Product.products(for: ProProducts.ids)
            var made: [ProOffer] = []
            var byID: [String: Product] = [:]
            for product in found {
                guard let info = product.subscription else { continue }
                byID[product.id] = product
                made.append(await offer(for: product, info: info))
            }
            products = byID
            offers = ProOffers.sorted(made)
            if !offers.contains(where: { $0.id == chosenID }) {
                chosenID = ProOffers.preferred(in: offers)?.id
            }
        } catch {
            log.error("Pro: the App Store gave no prices: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// One product as a way to pay: its period, its price, what a year comes
    /// to each month, and the free trial when this Apple account may still
    /// have it.
    private func offer(for product: Product, info: Product.SubscriptionInfo) async -> ProOffer {
        let length = info.subscriptionPeriod
        let period: ProOffer.Period
        if length.value == 1, length.unit == .year {
            period = .year
        } else if length.value == 1, length.unit == .month {
            period = .month
        } else if length.value == 1, length.unit == .week {
            period = .week
        } else {
            period = .other(length.formatted(product.subscriptionPeriodFormatStyle))
        }
        let perMonth: String? = period == .year ? (product.price / 12).formatted(product.priceFormatStyle) : nil
        var trial: String? = nil
        if let intro = info.introductoryOffer, intro.paymentMode == .freeTrial {
            let eligible = await info.isEligibleForIntroOffer
            if eligible { trial = intro.period.formatted(product.subscriptionPeriodFormatStyle) }
        }
        return ProOffer(id: product.id, period: period, price: product.price, displayPrice: product.displayPrice,
                        perMonth: perMonth, trial: trial)
    }

    /// Whether Pro is on: the App Store's verified subscription to one of
    /// Snapfly's products, not taken back, the one that lasts longest. The
    /// answer is kept for what runs without the window.
    func refresh() async {
        guard canBuy, !ProSample.requested else { return }
        var found: ProSubscription?
        for await result in StoreKit.Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  ProProducts.ids.contains(transaction.productID),
                  transaction.revocationDate == nil,
                  !transaction.isUpgraded else { continue }
            let renews = await renewal(of: transaction)
            let candidate = ProSubscription(productID: transaction.productID, transactionID: transaction.id,
                                            ends: transaction.expirationDate, renews: renews)
            if let kept = found, (kept.ends ?? .distantFuture) >= (candidate.ends ?? .distantFuture) { continue }
            found = candidate
        }
        // The window closed while asking: a list cut short says nothing, so the last answer stays.
        guard !Task.isCancelled else { return }
        // Approved by the family while the window waited: welcomed as bought.
        if found != nil, pending {
            pending = false
            justBought = true
        }
        subscription = found
        UserDefaults.standard.set(isSubscribed, forKey: Plan.subscribedKey)
        update()
    }

    /// Whether the subscription renews at the end of its period, from its
    /// product's status; nil when the App Store does not say.
    private func renewal(of transaction: StoreKit.Transaction) async -> Bool? {
        guard let info = products[transaction.productID]?.subscription,
              let statuses = try? await info.status else { return nil }
        for status in statuses {
            guard case .verified(let owner) = status.transaction,
                  owner.originalID == transaction.originalID || owner.productID == transaction.productID else { continue }
            guard case .verified(let renewing) = status.renewalInfo else { return nil }
            return renewing.willAutoRenew
        }
        return nil
    }

    // MARK: Buying and restoring

    /// Subscribes to the offer chosen through the App Store's own sheet:
    /// over the Pro window from macOS 15.2, where StoreKit takes the window,
    /// and where StoreKit places it before that.
    func subscribe(in window: NSWindow?) async {
        guard phase.canSubscribe, let offer = chosen else { return }
        note = nil
        if ProSample.requested {
            // Made up: the sheet's time, then the welcome, so a recording shows the lock opening.
            samplePhase = .buying
            update()
            try? await Task.sleep(for: .seconds(1.2))
            subscription = ProSample.subscription
            samplePhase = .welcome
            update()
            return
        }
        guard canBuy, let product = products[offer.id] else { return }
        buying = true
        update()
        do {
            let result: Product.PurchaseResult
            if #available(macOS 15.2, *), let window {
                result = try await product.purchase(confirmIn: window)
            } else {
                result = try await product.purchase()
            }
            await handle(result)
        } catch {
            if !Self.cancelled(error) {
                log.error("Pro: the purchase failed: \(error.localizedDescription, privacy: .public)")
                note = Self.failed
            }
        }
        buying = false
        update()
    }

    /// What the App Store's sheet answered.
    private func handle(_ result: Product.PurchaseResult) async {
        switch result {
        case .success(.verified(let transaction)):
            await transaction.finish()
            justBought = true
            await refresh()
            // The entitlement not listed yet: the verified purchase itself says Pro is on.
            if subscription == nil, ProProducts.ids.contains(transaction.productID) {
                subscription = ProSubscription(productID: transaction.productID, transactionID: transaction.id,
                                               ends: transaction.expirationDate, renews: nil)
                UserDefaults.standard.set(true, forKey: Plan.subscribedKey)
            }
        case .success(.unverified(_, _)):
            note = Self.failed
        case .pending:
            pending = true
        case .userCancelled:
            break
        @unknown default:
            break
        }
    }

    /// Restore Purchases: the App Store asks for the Apple account, then
    /// says whether Pro is on for it.
    func restore() async {
        guard !restoring else { return }
        note = nil
        if ProSample.requested {
            note = L("Snapfly Pro is restored.")
            return
        }
        guard canBuy else { return }
        restoring = true
        defer { restoring = false }
        do {
            try await AppStore.sync()
            await refresh()
            note = isSubscribed ? L("Snapfly Pro is restored.") : L("No Snapfly Pro was found for this Apple account.")
        } catch {
            if !Self.cancelled(error) {
                log.error("Pro: restoring failed: \(error.localizedDescription, privacy: .public)")
                note = Self.failed
            }
        }
    }

    /// The window closed: its welcome, its note and a wait for the family's
    /// approval are over; a purchase approved later still comes in.
    func closed() {
        justBought = false
        pending = false
        note = nil
        if samplePhase == .welcome { samplePhase = .subscribed }
        update()
    }

    // MARK: Helpers

    private static var failed: String {
        L("The App Store could not finish the purchase. Try again.")
    }

    /// The owner said no in the App Store's own sheet or sign-in: nothing to say.
    private static func cancelled(_ error: Error) -> Bool {
        if let storeError = error as? StoreKitError, case .userCancelled = storeError { return true }
        return error is CancellationError
    }

    private func update() {
        let next = samplePhase ?? ProPhase.of(canBuy: canBuy, keeps: Plan.keepsEverything(), subscribed: isSubscribed,
                                              justBought: justBought, pending: pending, buying: buying,
                                              loading: loading, hasOffers: !offers.isEmpty)
        if next != phase { phase = next }
    }
}
