import StoreKit
import AppStoreServerLibrary
import Combine

@MainActor
class PurchaseManager: ObservableObject {
    static let shared = PurchaseManager()
    
    @Published var hasActiveSubscription = false
    @Published var isLoading = false
    @Published var subscriptionEndDate: Date?
    @Published var showConfirmation = false

    private let productIdentifier = "com.echobot.monthlysubscription"
    private var product: Product?

    private let signedDataVerifier: SignedDataVerifier
    private let storeEnvironment: Environment
    private let bundleId: String
    private let appAppleId: Int64

    private init() {
        #if DEBUG
        self.storeEnvironment = .xcode
        print("Debug payment environment")
        #else
        self.storeEnvironment = .production
        #endif
        
        self.bundleId = Bundle.main.bundleIdentifier ?? ""
        self.appAppleId = 6502342037  // Replace with your app's Apple ID
        
        do {
            self.signedDataVerifier = try SignedDataVerifier(
                rootCertificates: [],
                bundleId: self.bundleId,
                appAppleId: self.appAppleId,
                environment: self.storeEnvironment,
                enableOnlineChecks: true
            )
        } catch {
            fatalError("Failed to initialize SignedDataVerifier: \(error)")
        }
        
        Task {
            await fetchProducts()
            await updateSubscriptionStatus()
        }
        
        setupTransactionListener()
        
        NotificationCenter.default.addObserver(self, selector: #selector(checkSubscriptionStatus), name: UIApplication.willEnterForegroundNotification, object: nil)
    }

    func fetchProducts() async {
        isLoading = true
        do {
            let products = try await Product.products(for: [productIdentifier])
            if let product = products.first {
                self.product = product
                print("Product fetched: \(product.displayName)")
            } else {
                print("No products found")
            }
        } catch {
            print("Failed to fetch products: \(error)")
        }
        isLoading = false
    }

    func purchaseSubscription() async {
        guard let product = self.product else {
            print("Product not found")
            return
        }
        
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verificationResult):
                print("Purchase initiated successfully")
            case .userCancelled:
                print("User cancelled the purchase")
            case .pending:
                print("Purchase is pending")
            @unknown default:
                print("Unknown purchase result")
            }
        } catch {
            print("Purchase failed: \(error)")
        }
    }

    func restorePurchases() async {
        do {
            try await AppStore.sync()
            await updateSubscriptionStatus()
        } catch {
            print("Restore failed: \(error)")
        }
    }

    @objc func checkSubscriptionStatus() {
        Task {
            await updateSubscriptionStatus()
        }
    }

    func updateSubscriptionStatus() async {
        do {
            for await result in Transaction.currentEntitlements {
                if case .verified(let transaction) = result,
                   transaction.productID == self.productIdentifier {
                    await self.validateTransaction(result)
                    return  // Exit after checking the first matching transaction
                }
            }
            // If we get here, no active subscription was found
            self.hasActiveSubscription = false
            print("No active subscription found")
            self.subscriptionEndDate = nil
        } catch {
            print("Failed to update subscription status: \(error)")
            self.hasActiveSubscription = false
            self.subscriptionEndDate = nil
        }
    }

    private func validateTransaction(_ transactionResult: StoreKit.VerificationResult<StoreKit.Transaction>) async {
        do {
            switch transactionResult {
            case .verified(let transaction):
                print("Verified Transaction: \(transaction)")
                
                let jwsRepresentation = transactionResult.jwsRepresentation
                print("JWS to validate: \(jwsRepresentation)")
                
                let verificationResult = await signedDataVerifier.verifyAndDecodeTransaction(signedTransaction: jwsRepresentation)
                
                switch verificationResult {
                case .valid(let decodedPayload):
                    if let expirationDate = decodedPayload.expiresDate,
                       expirationDate > Date() {
                        self.hasActiveSubscription = true
                        self.subscriptionEndDate = expirationDate
                        print("Valid subscription found, expires on: \(expirationDate)")
                    } else {
                        self.hasActiveSubscription = false
                        self.subscriptionEndDate = nil
                        print("Subscription has expired or no expiration date found")
                    }
                case .invalid(let error):
                    print("Transaction validation failed: \(error)")
                    self.hasActiveSubscription = false
                    self.subscriptionEndDate = nil
                }
                
            case .unverified(_, let verificationError):
                print("Unverified transaction: \(verificationError)")
                self.hasActiveSubscription = false
                self.subscriptionEndDate = nil
            }
        } catch {
            print("Transaction validation error: \(error)")
            self.hasActiveSubscription = false
            self.subscriptionEndDate = nil
        }
    }
    
    private func handlePurchased(_ verificationResult: StoreKit.VerificationResult<StoreKit.Transaction>) async {
        switch verificationResult {
        case .verified(let transaction):
            await validateTransaction(verificationResult)
            await transaction.finish()
            self.showConfirmation = true
        case .unverified(_, let error):
            print("Purchase verification failed: \(error)")
            // Handle unverified transaction
        }
    }

    private func setupTransactionListener() {
        Task.detached(priority: .background) {
            for await result in Transaction.updates {
                await self.handleTransactionUpdate(result)
            }
        }
    }

    private func handleTransactionUpdate(_ result: StoreKit.VerificationResult<StoreKit.Transaction>) async {
        await self.handlePurchased(result)
    }
}
