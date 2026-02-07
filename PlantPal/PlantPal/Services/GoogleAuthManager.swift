import Foundation
import GoogleSignIn
import UIKit
import Combine

@MainActor
final class GoogleAuthManager: ObservableObject {
    @Published var isSignedIn = false
    @Published var accessToken: String?
    @Published var errorMessage: String?

    func signIn() async {
        errorMessage = nil

        guard let presentingViewController = topViewController() else {
            errorMessage = "Unable to find a presenting view controller."
            return
        }

        let clientID = Bundle.main.object(forInfoDictionaryKey: "GOOGLE_CLIENT_ID") as? String
        guard let clientID, !clientID.isEmpty else {
            errorMessage = "Missing GOOGLE_CLIENT_ID in Info.plist."
            return
        }

        let configuration = GIDConfiguration(clientID: clientID)
        GIDSignIn.sharedInstance.configuration = configuration

        do {
            let result = try await GIDSignIn.sharedInstance.signIn(
                withPresenting: presentingViewController,
                hint: nil,
                additionalScopes: ["https://www.googleapis.com/auth/calendar.events"]
            )
            let user = result.user
            accessToken = user.accessToken.tokenString
            isSignedIn = true
        } catch {
            errorMessage = error.localizedDescription
            isSignedIn = false
        }
    }

    private func topViewController() -> UIViewController? {
        guard let scene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
            let root = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController else {
            return nil
        }
        return root
    }
}
