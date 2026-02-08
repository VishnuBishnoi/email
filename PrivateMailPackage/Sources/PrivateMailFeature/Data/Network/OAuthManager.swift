import AuthenticationServices
import CryptoKit
import Foundation

/// OAuth 2.0 manager for Gmail authentication with PKCE.
///
/// Handles the full OAuth authorization flow, token exchange,
/// and automatic refresh with retry and exponential backoff.
///
/// Spec ref: Account Management spec FR-ACCT-03, FR-ACCT-04
@MainActor
public final class OAuthManager: NSObject, OAuthManagerProtocol, ASWebAuthenticationPresentationContextProviding {

    private let clientId: String
    private let urlSession: URLSession

    /// Creates an OAuthManager.
    /// - Parameters:
    ///   - clientId: Google OAuth 2.0 client ID (injected, not hardcoded).
    ///   - urlSession: URLSession for token requests. Defaults to `.shared`.
    public init(clientId: String, urlSession: URLSession = .shared) {
        self.clientId = clientId
        self.urlSession = urlSession
        super.init()
    }

    // MARK: - OAuthManagerProtocol

    public func authenticate() async throws -> OAuthToken {
        let codeVerifier = generateCodeVerifier()
        let codeChallenge = generateCodeChallenge(from: codeVerifier)
        let redirectURI = "\(AppConstants.oauthRedirectScheme):/oauth2redirect"

        var components = URLComponents(string: AppConstants.googleAuthEndpoint)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: AppConstants.oauthScope),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent"),
        ]

        guard let authURL = components.url else {
            throw OAuthError.invalidAuthorizationCode
        }

        let callbackURL = try await startAuthSession(
            url: authURL,
            callbackScheme: AppConstants.oauthRedirectScheme
        )

        guard let code = extractAuthorizationCode(from: callbackURL) else {
            throw OAuthError.invalidAuthorizationCode
        }

        return try await exchangeCodeForToken(
            code: code,
            codeVerifier: codeVerifier,
            redirectURI: redirectURI
        )
    }

    public func refreshToken(_ token: OAuthToken) async throws -> OAuthToken {
        guard !token.refreshToken.isEmpty else {
            throw OAuthError.noRefreshToken
        }

        for attempt in 0..<AppConstants.oauthRetryCount {
            if attempt > 0 {
                let delay = AppConstants.oauthRetryBaseDelay * pow(2.0, Double(attempt - 1))
                try await Task.sleep(for: .seconds(delay))
            }

            do {
                return try await performTokenRefresh(refreshToken: token.refreshToken)
            } catch {
                if attempt == AppConstants.oauthRetryCount - 1 {
                    throw OAuthError.maxRetriesExceeded
                }
            }
        }

        throw OAuthError.maxRetriesExceeded
    }

    public nonisolated func formatXOAUTH2String(email: String, accessToken: String) -> String {
        let authString = "user=\(email)\u{01}auth=Bearer \(accessToken)\u{01}\u{01}"
        return Data(authString.utf8).base64EncodedString()
    }

    // MARK: - ASWebAuthenticationPresentationContextProviding

    public func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        #if os(iOS)
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow } ?? UIWindow()
        #elseif os(macOS)
        NSApplication.shared.windows.first ?? NSWindow()
        #endif
    }

    // MARK: - Private: Auth Session

    private func startAuthSession(url: URL, callbackScheme: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: callbackScheme
            ) { callbackURL, error in
                if let error {
                    if (error as NSError).code == ASWebAuthenticationSessionError.canceledLogin.rawValue {
                        continuation.resume(throwing: OAuthError.authenticationCancelled)
                    } else {
                        continuation.resume(throwing: OAuthError.networkError(error.localizedDescription))
                    }
                    return
                }

                guard let callbackURL else {
                    continuation.resume(throwing: OAuthError.invalidAuthorizationCode)
                    return
                }

                continuation.resume(returning: callbackURL)
            }

            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            session.start()
        }
    }

    private func extractAuthorizationCode(from url: URL) -> String? {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        return components?.queryItems?.first { $0.name == "code" }?.value
    }

    // MARK: - Private: Token Exchange

    private func exchangeCodeForToken(
        code: String,
        codeVerifier: String,
        redirectURI: String
    ) async throws -> OAuthToken {
        let body = [
            "code": code,
            "client_id": clientId,
            "redirect_uri": redirectURI,
            "grant_type": "authorization_code",
            "code_verifier": codeVerifier,
        ]

        return try await postTokenRequest(body: body)
    }

    private func performTokenRefresh(refreshToken: String) async throws -> OAuthToken {
        let body = [
            "refresh_token": refreshToken,
            "client_id": clientId,
            "grant_type": "refresh_token",
        ]

        let newToken = try await postTokenRequest(body: body, existingRefreshToken: refreshToken)
        return newToken
    }

    private func postTokenRequest(
        body: [String: String],
        existingRefreshToken: String? = nil
    ) async throws -> OAuthToken {
        guard let url = URL(string: AppConstants.googleTokenEndpoint) else {
            throw OAuthError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15 // Prevent hanging on network issues

        let bodyString = body.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.value)" }
            .joined(separator: "&")
        request.httpBody = bodyString.data(using: .utf8)

        let (data, response) = try await urlSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OAuthError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            if body["grant_type"] == "refresh_token" {
                throw OAuthError.tokenRefreshFailed(errorBody)
            } else {
                throw OAuthError.tokenExchangeFailed(errorBody)
            }
        }

        return try parseTokenResponse(data, existingRefreshToken: existingRefreshToken)
    }

    private func parseTokenResponse(_ data: Data, existingRefreshToken: String? = nil) throws -> OAuthToken {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let accessToken = json["access_token"] as? String,
              let expiresIn = json["expires_in"] as? Int
        else {
            throw OAuthError.invalidResponse
        }

        // Google refresh responses may not include refresh_token
        let refreshToken = (json["refresh_token"] as? String) ?? existingRefreshToken ?? ""
        let tokenType = (json["token_type"] as? String) ?? "Bearer"
        let scope = (json["scope"] as? String) ?? AppConstants.oauthScope

        return OAuthToken(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: Date().addingTimeInterval(TimeInterval(expiresIn)),
            tokenType: tokenType,
            scope: scope
        )
    }

    // MARK: - Private: PKCE

    /// Generates a cryptographically random code verifier (43-128 chars).
    func generateCodeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URLEncodedString()
    }

    /// Generates a code challenge from a code verifier using SHA256.
    func generateCodeChallenge(from verifier: String) -> String {
        let data = Data(verifier.utf8)
        let hash = SHA256.hash(data: data)
        return Data(hash).base64URLEncodedString()
    }
}

// MARK: - Data Extension for Base64URL

extension Data {
    /// Base64URL encoding (RFC 4648 §5) without padding.
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
