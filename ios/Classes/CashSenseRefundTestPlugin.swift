import Flutter
import StoreKit
import UIKit

public class CashSenseRefundTestPlugin: NSObject, FlutterPlugin {
    private var presenting = false
    private let productIDs: Set<String> = [
        "cashsense.app.premium.monthly", "cashsense.app.premium.annual",
        "cashsense.app.premium.lifetime"
    ]

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "cashsense/sandbox_refund", binaryMessenger: registrar.messenger())
        registrar.addMethodCallDelegate(CashSenseRefundTestPlugin(), channel: channel)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard call.method == "transactions" || call.method == "request" else {
            result(FlutterMethodNotImplemented)
            return
        }
        guard #available(iOS 16.0, *) else {
            result(FlutterError(code: "unsupported", message: "Sandbox refund testing requires iOS 16 or later.", details: nil))
            return
        }
        guard let args = call.arguments as? [String: Any],
              let ownerText = args["owner"] as? String,
              let owner = UUID(uuidString: ownerText) else {
            result(FlutterError(code: "owner_required", message: "Sign in to your CashSense test account.", details: nil))
            return
        }
        Task { @MainActor in
            do {
                let transactions = await self.eligibleTransactions(owner: owner)
                if call.method == "transactions" {
                    result(transactions.map { transaction in
                        ["id": String(transaction.id), "productId": transaction.productID,
                         "purchaseDate": ISO8601DateFormatter().string(from: transaction.purchaseDate)]
                    })
                    return
                }
                guard !self.presenting else {
                    result(FlutterError(code: "busy", message: "A refund sheet is already open.", details: nil))
                    return
                }
                guard let id = args["transactionId"] as? String,
                      let transaction = transactions.first(where: { String($0.id) == id }) else {
                    result(FlutterError(code: "not_eligible", message: "This sandbox purchase is unavailable, already revoked, or belongs to another CashSense account.", details: nil))
                    return
                }
                guard let scene = UIApplication.shared.connectedScenes
                    .compactMap({ $0 as? UIWindowScene })
                    .first(where: { $0.activationState == .foregroundActive && $0.windows.contains(where: { $0.isKeyWindow }) }) else {
                    result(FlutterError(code: "no_scene", message: "Bring CashSense to the foreground and try again.", details: nil))
                    return
                }
                self.presenting = true
                defer { self.presenting = false }
                let status = try await transaction.beginRefundRequest(in: scene)
                switch status {
                case .success: result("submitted")
                case .userCancelled: result("cancelled")
                @unknown default: result("unknown")
                }
            } catch {
                result(FlutterError(code: "refund_request_failed", message: error.localizedDescription, details: nil))
            }
        }
    }

    @available(iOS 16.0, *)
    private func eligibleTransactions(owner: UUID) async -> [StoreKit.Transaction] {
        var transactions: [StoreKit.Transaction] = []
        for await verification in StoreKit.Transaction.all {
            guard case .verified(let transaction) = verification,
                  transaction.environment == .sandbox,
                  productIDs.contains(transaction.productID),
                  transaction.appAccountToken == owner,
                  transaction.revocationDate == nil else { continue }
            transactions.append(transaction)
        }
        return transactions.sorted { $0.purchaseDate > $1.purchaseDate }
    }
}
