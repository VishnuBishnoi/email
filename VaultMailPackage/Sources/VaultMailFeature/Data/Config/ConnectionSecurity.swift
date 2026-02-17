import Foundation

/// Connection security mode for IMAP and SMTP connections.
///
/// Spec ref: Multi-Provider IMAP spec, FR-MPROV-05
/// - `.tls`: Implicit TLS — TLS handshake immediately upon TCP connection (ports 993/465)
/// - `.starttls`: Connect plaintext, issue STARTTLS, upgrade to TLS (ports 143/587)
/// - `.none`: No encryption — `#if DEBUG` only per FR-MPROV-05
public enum ConnectionSecurity: String, Sendable, Codable, CaseIterable {
    /// Implicit TLS: TLS handshake starts immediately on connection.
    /// Used by IMAP port 993 and SMTP port 465.
    case tls

    /// STARTTLS: Connect plaintext, then upgrade to TLS after STARTTLS command.
    /// Used by IMAP port 143 and SMTP port 587.
    case starttls

    #if DEBUG
    /// No encryption. Only available in debug builds for local testing.
    case none
    #endif
}
