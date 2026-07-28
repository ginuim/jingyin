import StoreKit

@MainActor
final class EntitlementStore: ObservableObject {
    static let lifetimeProductID = "com.reaidea.jingyin.lifetime"

    @Published private(set) var lifetimeProduct: Product?
    @Published private(set) var isUnlocked = false
    @Published private(set) var isReady = false
    @Published private(set) var isLoading = false
    @Published private(set) var isPurchasing = false
    @Published private(set) var errorMessage: String?

    private var updatesTask: Task<Void, Never>?

    var access: ExportAccess {
        isUnlocked ? .lifetime : .free
    }

    var displayPrice: String? {
        lifetimeProduct?.displayPrice
    }

    init() {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-storekitUnlocked") {
            isUnlocked = true
            isReady = true
        }
        #endif
        updatesTask = observeTransactionUpdates()
    }

    deinit {
        updatesTask?.cancel()
    }

    func prepare() async {
        if !isReady {
            await refreshEntitlements()
        }
        await loadProduct()
    }

    func loadProduct() async {
        guard lifetimeProduct == nil, !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            lifetimeProduct = try await Product.products(
                for: [Self.lifetimeProductID]
            ).first
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @discardableResult
    func purchaseLifetime() async -> Bool {
        if lifetimeProduct == nil {
            await loadProduct()
        }
        guard let lifetimeProduct else { return false }

        isPurchasing = true
        errorMessage = nil
        defer { isPurchasing = false }

        do {
            let result = try await lifetimeProduct.purchase()
            switch result {
            case let .success(verification):
                let transaction = try Self.verified(verification)
                await transaction.finish()
                await refreshEntitlements()
                return isUnlocked
            case .pending, .userCancelled:
                return false
            @unknown default:
                return false
            }
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func restorePurchases() async -> Bool {
        isPurchasing = true
        errorMessage = nil
        defer { isPurchasing = false }

        do {
            try await AppStore.sync()
            await refreshEntitlements()
            return isUnlocked
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func clearError() {
        errorMessage = nil
    }

    private func refreshEntitlements() async {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-storekitUnlocked") {
            isUnlocked = true
            isReady = true
            return
        }
        #endif

        var hasLifetimeAccess = false
        for await result in Transaction.currentEntitlements {
            guard case let .verified(transaction) = result,
                  transaction.productID == Self.lifetimeProductID,
                  transaction.revocationDate == nil else {
                continue
            }
            hasLifetimeAccess = true
        }
        isUnlocked = hasLifetimeAccess
        isReady = true
    }

    private func observeTransactionUpdates() -> Task<Void, Never> {
        Task { [weak self] in
            for await result in Transaction.updates {
                guard case let .verified(transaction) = result else { continue }
                await transaction.finish()
                await self?.refreshEntitlements()
            }
        }
    }

    private nonisolated static func verified<T>(
        _ result: VerificationResult<T>
    ) throws -> T {
        switch result {
        case let .verified(value):
            return value
        case .unverified:
            throw EntitlementError.failedVerification
        }
    }
}

private enum EntitlementError: LocalizedError {
    case failedVerification

    var errorDescription: String? {
        "The App Store transaction could not be verified."
    }
}
