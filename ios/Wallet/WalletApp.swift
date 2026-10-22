import SwiftUI

/// The screens and how they lead to each other (SPEC.md §4): Start and Home; History, Top up and Pay
/// return to Home; Payment detail returns to History, wherever it was opened from (Home, History or a
/// receipt), as on the web and Android. Plain state, not a navigation stack: no edge swipe can take a
/// receipt back to Confirm, and there are no transition animations, as on the web and Android.
nonisolated enum Route: Hashable, Codable {
    case start
    case home(walletId: String)
    case history(walletId: String)
    case topUp(walletId: String)
    case pay(walletId: String)
    case payment(walletId: String, paymentId: String)
}

@main
struct WalletApp: App {
    private let api = ApiClient(config: ApiConfig.fromLaunch())

    var body: some Scene {
        WindowGroup {
            RootView(api: api)
        }
    }
}

/// K-08: the screen and Pay's state are kept in the scene's saved state (@SceneStorage). iOS saves it when
/// the app goes to the background and restores it when the system ended the app there, as Android does
/// with its saved state; after the user swipes the app away it is discarded (Apple's documentation). Killed
/// in the foreground, the app reopens with what was saved the last time it went to the background. Only Pay
/// keeps more than its screen: the other screens load what they show from the API.
struct RootView: View {
    let api: ApiClient
    @SceneStorage("route") private var savedRoute = Data()
    @SceneStorage("pay") private var savedPay = Data()

    private var route: Route { (try? JSONDecoder().decode(Route.self, from: savedRoute)) ?? .start }

    /// Pay's saved state; leaving Pay forgets it (`go`).
    private var pay: Binding<PayModel.Saved?> {
        Binding(get: { try? JSONDecoder().decode(PayModel.Saved.self, from: savedPay) },
                set: { savedPay = $0.flatMap { try? JSONEncoder().encode($0) } ?? Data() })
    }

    private func go(_ next: Route) {
        if case .pay = next {} else { savedPay = Data() }
        savedRoute = (try? JSONEncoder().encode(next)) ?? Data()
    }

    var body: some View {
        ZStack {
            WalletColors.bgPage.ignoresSafeArea()
            switch route {
            case .start:
                StartView(api: api) { go(.home(walletId: $0)) }
            case .home(let walletId):
                HomeView(api: api, walletId: walletId,
                         onTopUp: { go(.topUp(walletId: walletId)) },
                         onPay: { go(.pay(walletId: walletId)) },
                         onHistory: { go(.history(walletId: walletId)) },
                         onOpenPayment: { go(.payment(walletId: walletId, paymentId: $0)) },
                         onSwitchWallet: { go(.start) })
            case .history(let walletId):
                HistoryView(api: api, walletId: walletId,
                            onHome: { go(.home(walletId: walletId)) },
                            onPay: { go(.pay(walletId: walletId)) },
                            onOpenPayment: { go(.payment(walletId: walletId, paymentId: $0)) })
            case .topUp(let walletId):
                TopUpView(api: api, walletId: walletId,
                          onBack: { go(.home(walletId: walletId)) },
                          onDone: { go(.home(walletId: walletId)) })
            case .pay(let walletId):
                PayView(api: api, walletId: walletId, saved: pay,
                        onBack: { go(.home(walletId: walletId)) },
                        onDone: { go(.home(walletId: walletId)) },
                        onViewPayment: { go(.payment(walletId: walletId, paymentId: $0)) })
            case .payment(let walletId, let paymentId):
                PaymentDetailView(api: api, paymentId: paymentId,
                                  onBack: { go(.history(walletId: walletId)) })
            }
        }
        .id(route)                     // each visit to a screen starts from a fresh model
    }
}
