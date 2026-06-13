import Combine
import Foundation
import StoreKit

@MainActor
final class StoreKitManager: ObservableObject {
    static let annualProductID = "annual"
    static let productIDs: Set<String> = [
        annualProductID
    ]

    @Published private(set) var annualProduct: Product?
    @Published private(set) var products: [Product] = []
    @Published private(set) var isPremium = false
    @Published private(set) var isPurchasing = false
    @Published private(set) var hasLoadedProducts = false
    @Published var errorMessage: String?

    private var transactionUpdatesTask: Task<Void, Never>?

    init() {
        transactionUpdatesTask = listenForTransactions()
    }

    deinit {
        transactionUpdatesTask?.cancel()
    }

    var annualPriceText: String {
        annualProduct?.displayPrice ?? "$29.99"
    }

    var annualSubtitleText: String {
        "\(annualPriceText) / year"
    }

    var monthlyPriceText: String {
        guard let annualProduct else {
            return "Only $2.49\nper month"
        }

        let monthlyPrice = annualProduct.price / Decimal(12)
        let formattedPrice = monthlyPrice.formatted(annualProduct.priceFormatStyle)
        return "Only \(formattedPrice)\nper month"
    }

    func loadProducts() async {
        do {
            let products = try await Product.products(for: Self.productIDs)
            self.products = products.sorted { $0.price < $1.price }
            annualProduct = products.first { $0.id == Self.annualProductID }
            if annualProduct == nil {
                errorMessage = "Annual StoreKit product is not available. Check the StoreKit configuration in the active scheme."
            }
            await updatePurchasedProducts()
            hasLoadedProducts = true
        } catch {
            errorMessage = error.localizedDescription
            await updatePurchasedProducts()
            hasLoadedProducts = true
        }
    }

    @discardableResult
    func purchaseAnnual() async -> Bool {
        guard !isPurchasing else {
            return false
        }

        isPurchasing = true
        defer { isPurchasing = false }
        guard let annualProduct else {
            await loadProducts()
            guard self.annualProduct != nil else {
                errorMessage = "Annual StoreKit product is not loaded. Check that test.storekit is selected for the active run scheme."
                return false
            }
            return await purchaseLoadedAnnual()
        }

        return await purchase(annualProduct)
    }

    private func purchaseLoadedAnnual() async -> Bool {
        guard let annualProduct else { return false }
        return await purchase(annualProduct)
    }

    private func purchase(_ annualProduct: Product) async -> Bool {
        do {
            let result = try await annualProduct.purchase()

            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                isPremium = true
                await transaction.finish()
                return true
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
        case .unverified:
            throw PurchaseError.failedVerification
        case .verified(let safe):
            return safe
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
        do {
            let transaction = try checkVerified(result)
            if Self.productIDs.contains(transaction.productID) {
                isPremium = true
            }
            await transaction.finish()
        } catch {}
    }
}

enum PurchaseError: LocalizedError {
    case failedVerification

    var errorDescription: String? {
        "StoreKit transaction verification failed."
    }
}
