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

        // Launch the ASWebAuthenticationSession via AuthSessionLauncher,
        // which uses Unmanaged<StreamBox> pointers to pass the AsyncStream
        // continuation through without any Swift actor isolation inference.
        // This avoids the dispatch_assert_queue_fail crash when Safari's XPC
        // calls the completion handler on a background thread.
        let callbackURL = try await AuthSessionRunner.start(
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

    // MARK: - Private

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

// MARK: - ObjC Auth Session Launcher

/// Objective-C compatible helper that creates and starts an ASWebAuthenticationSession
/// entirely in ObjC-land, bypassing Swift 6's actor isolation inference.
///
/// **The fundamental problem**: In Swift 6, `ASWebAuthenticationSession`'s
/// completion handler is called by Safari's XPC on a background thread.
/// Swift's concurrency system infers `@MainActor` isolation on closures
/// through multiple vectors:
///   1. Conforming to `ASWebAuthenticationPresentationContextProviding`
///      (which has `NS_SWIFT_UI_ACTOR` in the SDK header)
///   2. Capturing any `@MainActor`-isolated reference
///   3. Nesting inside a closure that has `@MainActor` context
///   4. Creating `@MainActor` types inside the parent closure scope
///
/// All previous attempts to fix this in pure Swift failed because Swift's
/// type system is too aggressive at inferring `@MainActor` isolation.
///
/// **The solution**: Use `@objc` exposed callback + `Unmanaged` pointer
/// to pass the stream continuation through without Swift type inference.
/// The completion handler is defined as a plain ObjC block that calls
/// a static C-like function, completely invisible to Swift's actor system.

/// Thread-safe box for passing the AsyncStream continuation through
/// Unmanaged pointers, completely opaque to Swift's actor isolation.
private final class StreamBox: @unchecked Sendable {
    let continuation: AsyncStream<Result<URL, Error>>.Continuation

    init(_ continuation: AsyncStream<Result<URL, Error>>.Continuation) {
        self.continuation = continuation
    }
}

// MARK: - AuthSessionLauncher

/// Launches `ASWebAuthenticationSession` using ObjC-style patterns that
/// completely bypass Swift 6's actor isolation inference.
///
/// The key trick: the completion handler is created as an `@Sendable`
/// closure that captures only a raw `Unmanaged<StreamBox>` pointer.
/// Since `Unmanaged` is a plain value type with no actor annotations,
/// Swift cannot infer `@MainActor` isolation on the closure.
private enum AuthSessionLauncher {

    /// Creates, configures, and starts an ASWebAuthenticationSession on
    /// the main thread. Returns the callback URL via the provided stream
    /// continuation.
    ///
    /// - Important: This function must be called from any thread.
    ///   The session is dispatched to main internally.
    static func launch(
        url: URL,
        callbackScheme: String,
        continuation: AsyncStream<Result<URL, Error>>.Continuation
    ) {
        // Pack the continuation into an opaque Unmanaged pointer.
        // This makes it invisible to Swift's actor isolation inference.
        let box = StreamBox(continuation)
        let unmanagedBox = Unmanaged.passRetained(box)

        DispatchQueue.main.async {
            // Create the completion handler as a standalone block.
            // It captures ONLY the Unmanaged pointer (a plain value type).
            // No @MainActor references. No protocol conformances.
            // No nested @MainActor closures. Swift CANNOT infer actor isolation.
            let completionHandler: ASWebAuthenticationSession.CompletionHandler = { callbackURL, error in
                // Retrieve and release the box
                let resultBox = unmanagedBox.takeRetainedValue()
                let cont = resultBox.continuation

                if let error {
                    if (error as NSError).code == ASWebAuthenticationSessionError.canceledLogin.rawValue {
                        cont.yield(.failure(OAuthError.authenticationCancelled))
                    } else {
                        cont.yield(.failure(OAuthError.networkError(error.localizedDescription)))
                    }
                } else if let callbackURL {
                    cont.yield(.success(callbackURL))
                } else {
                    cont.yield(.failure(OAuthError.invalidAuthorizationCode))
                }
                cont.finish()
            }

            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: callbackScheme,
                completionHandler: completionHandler
            )

            // For the presentation context, we use OAuthManager's static
            // method via a minimal NSObject that does NOT inherit @MainActor
            // from protocol conformance. Instead we use the session's own
            // built-in behavior — on macOS 12+/iOS 15+, if no
            // presentationContextProvider is set, the system picks the
            // key window automatically.
            //
            // On older OS versions or if needed, we set a provider.
            // The provider is created HERE on the main thread, set on
            // the session, but NEVER captured in the completion handler.
            let provider = _AnchorProvider()
            session.presentationContextProvider = provider

            session.prefersEphemeralWebBrowserSession = false

            // Retain the session and provider in associated objects
            // so they survive until the callback fires.
            objc_setAssociatedObject(session, &_sessionKey, session, .OBJC_ASSOCIATION_RETAIN)
            objc_setAssociatedObject(session, &_providerKey, provider, .OBJC_ASSOCIATION_RETAIN)

            session.start()
            NSLog("[OAuth] ASWebAuthenticationSession started")
        }
    }

    private nonisolated(unsafe) static var _sessionKey: UInt8 = 0
    private nonisolated(unsafe) static var _providerKey: UInt8 = 0
}

// MARK: - _AnchorProvider

/// Minimal presentation context provider.
/// Created on the main thread, set on the session, but NEVER captured
/// in the completion handler closure. The completion handler only sees
/// the Unmanaged<StreamBox> pointer.
private final class _AnchorProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        #if os(iOS)
        return UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow } ?? UIWindow()
        #elseif os(macOS)
        return NSApplication.shared.windows.first ?? NSWindow()
        #endif
    }
}

// MARK: - AuthSessionRunner

/// Public-facing async interface for launching an OAuth session.
/// Internally delegates to `AuthSessionLauncher` which uses ObjC-style
/// patterns to avoid Swift 6 actor isolation issues.
private enum AuthSessionRunner {

    static func start(
        url: URL,
        callbackScheme: String
    ) async throws -> URL {
        let stream = AsyncStream<Result<URL, Error>> { continuation in
            AuthSessionLauncher.launch(
                url: url,
                callbackScheme: callbackScheme,
                continuation: continuation
            )
        }

        for await result in stream {
            return try result.get()
        }

        throw OAuthError.authenticationCancelled
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
