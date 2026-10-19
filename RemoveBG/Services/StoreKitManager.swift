import Combine
import Foundation
import StoreKit

struct SubscriptionOffer {
    let title: String
    let description: String
    let billingText: String

    init(product: Product) {
        title = product.displayName
        description = product.description
        if let period = product.subscription?.subscriptionPeriod {
            billingText = "\(product.displayPrice)\n/ \(period.formatted(product.subscriptionPeriodFormatStyle))"
        } else {
            billingText = product.displayPrice
        }
    }
}

@MainActor
final class StoreKitManager: ObservableObject {
    static let subscriptionProductID = "weeklybg"
    static let productIDs: Set<String> = [subscriptionProductID]

    @Published private(set) var subscriptionProduct: Product?
    @Published private(set) var products: [Product] = []
    @Published private(set) var isPremium = false
    @Published private(set) var isPurchasing = false
    @Published private(set) var hasLoadedProducts = false
    @Published private(set) var isLoadingProducts = false
    @Published private(set) var productLoadingError: String?
    @Published var errorMessage: String?

    private var transactionUpdatesTask: Task<Void, Never>?
    private var productLoadTask: Task<Void, Never>?

    init() {
        transactionUpdatesTask = listenForTransactions()
    }

    deinit {
        transactionUpdatesTask?.cancel()
        productLoadTask?.cancel()
    }

    var subscriptionOffer: SubscriptionOffer? {
        subscriptionProduct.map(SubscriptionOffer.init(product:))
    }

    var canPurchase: Bool { subscriptionProduct != nil && !isPurchasing }

    func loadProducts() async {
        if let productLoadTask {
            await productLoadTask.value
            return
        }
        guard subscriptionProduct == nil else { return }

        let task = Task { await fetchProducts() }
        productLoadTask = task
        defer { productLoadTask = nil }
        await task.value
    }

    private func fetchProducts() async {
        isLoadingProducts = true
        productLoadingError = nil
        defer {
            isLoadingProducts = false
            hasLoadedProducts = true
        }
        do {
            let loadedProducts = try await Product.products(for: Self.productIDs)
            products = loadedProducts.sorted { $0.price < $1.price }
            subscriptionProduct = products.first {
                $0.id == Self.subscriptionProductID && $0.type == .autoRenewable
            }
            if subscriptionProduct == nil {
                productLoadingError = "Subscriptions are currently unavailable. Please try again."
            }
        } catch {
            productLoadingError = "Could not load the subscription. Please try again."
        }
        await updatePurchasedProducts()
    }

    @discardableResult
    func purchaseSubscription() async -> Bool {
        guard !isPurchasing else { return false }
        isPurchasing = true
        defer { isPurchasing = false }

        if subscriptionProduct == nil { await loadProducts() }
        guard let subscriptionProduct else { return false }

        do {
            let result = try await subscriptionProduct.purchase()
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                await transaction.finish()
                await updatePurchasedProducts()
                return isPremium
            case .userCancelled, .pending:
                return false
            @unknown default:
                return false
            }
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func restorePurchases() async {
        do {
            try await AppStore.sync()
            await updatePurchasedProducts()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updatePurchasedProducts() async {
        var hasPremiumAccess = false
        for await result in Transaction.currentEntitlements {
            guard let transaction = try? checkVerified(result) else { continue }
            if Self.productIDs.contains(transaction.productID) {
                hasPremiumAccess = true
            }
        }
        isPremium = hasPremiumAccess
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified: throw PurchaseError.failedVerification
        case .verified(let safe): return safe
        }
    }

    private func listenForTransactions() -> Task<Void, Never> {
        Task { [weak self] in
            for await result in Transaction.updates {
                guard let self else { return }
                await self.handleTransactionUpdate(result)
            }
        }
    }

    private func handleTransactionUpdate(_ result: VerificationResult<Transaction>) async {
        guard let transaction = try? checkVerified(result) else { return }
        await transaction.finish()
        if Self.productIDs.contains(transaction.productID) {
            await updatePurchasedProducts()
        }
    }
}

enum PurchaseError: LocalizedError {
    case failedVerification

    var errorDescription: String? { "StoreKit transaction verification failed." }
}
