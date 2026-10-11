//
//  AppleSignInButton.swift
//  Kotek
//
//  Apple's own button, sized to sit beside a `PillButton`, handing back the ID
//  token Supabase signs in with. Shared by the welcome screen and Settings.
//

import AuthenticationServices
import CryptoKit
import SwiftUI

struct AppleSignInButton: View {
    /// The ID token, and the raw nonce whose hash Apple sealed into it —
    /// Supabase re-hashes the raw one to check the token was minted for us.
    let onToken: (_ idToken: String, _ nonce: String) -> Void
    var onError: (Error) -> Void = { _ in }

    @State private var nonce = ""

    var body: some View {
        SignInWithAppleButton(.continue) { request in
            nonce = Self.randomNonce()
            // No name or email. The account is only somewhere to keep a
            // gangsa's progress, and asking for either is more to disclose in
            // the privacy label for nothing the app would show.
            request.requestedScopes = []
            request.nonce = Self.sha256(nonce)
        } onCompletion: { result in
            switch result {
            case let .success(authorization):
                guard
                    let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                    let data = credential.identityToken,
                    let token = String(data: data, encoding: .utf8)
                else { return }
                onToken(token, nonce)
            case let .failure(error):
                // Closing the sheet is a choice, not a failure.
                if (error as? ASAuthorizationError)?.code == .canceled { return }
                onError(error)
            }
        }
        .signInWithAppleButtonStyle(.white)
        .frame(width: 280, height: Theme.buttonHeight)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radius))
    }

    private static func randomNonce() -> String {
        (0 ..< 32).map { _ in String(format: "%02x", UInt8.random(in: 0 ... 255)) }.joined()
    }

    private static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
