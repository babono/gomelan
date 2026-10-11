//
//  AppleReauthorization.swift
//  Kotek
//
//  One more trip through the Apple sheet before an account is deleted. Not for
//  signing in: the point is the fresh `authorizationCode`, which the
//  delete-account function trades for a token it can revoke — the app never
//  keeps one from sign-in. It doubles as the "are you really sure".
//
//  Driven by hand rather than through `SignInWithAppleButton`, because the
//  request follows a confirmation dialog instead of a tap on Apple's button.
//

import AuthenticationServices
import UIKit

final class AppleReauthorization: NSObject {
    private var continuation: CheckedContinuation<String?, Error>?

    /// The code, or nil if the player closed the sheet.
    func authorizationCode() async throws -> String? {
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = []
        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            controller.performRequests()
        }
    }
}

extension AppleReauthorization: ASAuthorizationControllerDelegate {
    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        let code = (authorization.credential as? ASAuthorizationAppleIDCredential)?
            .authorizationCode
            .flatMap { String(data: $0, encoding: .utf8) }
        continuation?.resume(returning: code)
        continuation = nil
    }

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        if (error as? ASAuthorizationError)?.code == .canceled {
            continuation?.resume(returning: nil)
        } else {
            continuation?.resume(throwing: error)
        }
        continuation = nil
    }
}

extension AppleReauthorization: ASAuthorizationControllerPresentationContextProviding {
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        if let key = scenes.flatMap(\.windows).first(where: \.isKeyWindow) { return key }
        // Only reachable with no key window, which a Settings tap rules out.
        return ASPresentationAnchor(windowScene: scenes[0])
    }
}
