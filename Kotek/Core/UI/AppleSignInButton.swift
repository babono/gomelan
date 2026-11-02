//
//  AppleSignInButton.swift
//  Kotek
//
//  Apple's own button, sized to sit beside an `AppButton`, handing back the ID
//  token Supabase signs in with. Shared by the welcome screen and Settings.
//

import AuthenticationServices
import CryptoKit
import SwiftUI

struct AppleSignInButton: View {
    /// The ID token, and the raw nonce whose hash Apple sealed into it —
    /// Supabase re-hashes the raw one to check the token was minted for us.
    /// The name only arrives the first time an Apple ID signs in to the app;
    /// every later sign-in, on any device, gets nil.
    let onToken: (_ idToken: String, _ nonce: String, _ fullName: String?) -> Void
    var onError: (Error) -> Void = { _ in }
    /// `.large` beside the welcome screen's hero buttons; inside a Settings
    /// page, among compact controls, a large one dwarfed everything near it.
    var size = AppButtonSize.large
    /// "Continue" where it starts the app; "Sign in" in Settings, where the
    /// player is already in and the shorter label leaves room beside it.
    var signIn = false

    @State private var nonce = ""

    var body: some View {
        SignInWithAppleButton(signIn ? .signIn : .continue) { request in
            nonce = Self.randomNonce()
            // The name prefills the profile step. No email: the account is
            // only somewhere to keep a gangsa's progress, and an address is
            // more to disclose in the privacy label for nothing the app shows.
            request.requestedScopes = [.fullName]
            request.nonce = Self.sha256(nonce)
        } onCompletion: { result in
            switch result {
            case let .success(authorization):
                guard
                    let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                    let data = credential.identityToken,
                    let token = String(data: data, encoding: .utf8)
                else { return }
                let name = credential.fullName.map {
                    PersonNameComponentsFormatter.localizedString(from: $0, style: .default)
                }
                onToken(token, nonce, name?.isEmpty == false ? name : nil)
            case let .failure(error):
                // Closing the sheet is a choice, not a failure.
                if (error as? ASAuthorizationError)?.code == .canceled { return }
                onError(error)
            }
        }
        .signInWithAppleButtonStyle(.white)
        // Apple's label scales with the button's height, so the width
        // follows it to keep the proportions.
        .frame(width: size.height * (signIn ? 4.6 : 5.4), height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: size == .large ? Theme.radius : size.height / 2))
    }

    private static func randomNonce() -> String {
        (0 ..< 32).map { _ in String(format: "%02x", UInt8.random(in: 0 ... 255)) }.joined()
    }

    private static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
