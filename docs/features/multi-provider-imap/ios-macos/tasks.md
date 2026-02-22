---
title: "Multi-Provider IMAP — iOS/macOS Task Breakdown"
platform: iOS, macOS
plan-ref: docs/features/multi-provider-imap/ios-macos/plan.md
version: "1.0.0"
status: locked
updated: 2026-02-17
---

# Multi-Provider IMAP — iOS/macOS Task Breakdown

> Each task references its plan ID, spec section, and acceptance criteria. Status values: `todo`, `in-progress`, `done`, `blocked`.

---

## Phase 1: Data Layer Foundation

### IOS-MP-01: Provider Configuration Registry

- **Status**: `todo`
- **Spec ref**: Multi-Provider IMAP spec, FR-MPROV-01
- **Validation ref**: AC-MP-01
- **Plan phase**: Phase 1
- **Description**: Implement a built-in registry of known email providers (Gmail, Outlook, Yahoo, iCloud) with pre-configured server settings, auth mechanisms, connection limits, IDLE refresh intervals, folder name maps, and `requiresSentAppend` flags. Include domain-to-provider lookup.
- **Deliverables**:
  - [ ] `EmailProvider.swift` — `EmailProvider` enum (`.gmail`, `.outlook`, `.yahoo`, `.icloud`, `.custom`)
  - [ ] `ConnectionSecurity.swift` — `ConnectionSecurity` enum (`.tls`, `.starttls`)
  - [ ] `AuthMechanism.swift` — `AuthMechanism` enum (`.xoauth2`, `.plain`)
  - [ ] `ProviderConfiguration.swift` — struct containing all provider fields (imapHost, imapPort, smtpHost, smtpPort, authMechanism, maxConnections, idleRefreshInterval, folderNameMap, excludedFolders, requiresSentAppend, oauthConfig)
  - [ ] `ProviderRegistry.swift` — static registry with built-in entries for Gmail, Outlook, Yahoo, iCloud, and `custom` defaults; domain lookup method
  - [ ] Unit tests for domain-to-provider resolution and fallback to `.custom`
- **Notes**: Registry is static data shipped with the app. `oauthConfig` is nil for PLAIN providers (Yahoo, iCloud). Custom providers use conservative defaults (maxConnections=5, idleRefresh=20min).

### IOS-MP-02: SASL PLAIN Authentication

- **Status**: `todo`
- **Spec ref**: Multi-Provider IMAP spec, FR-MPROV-02
- **Validation ref**: AC-MP-02
- **Plan phase**: Phase 1
- **Description**: Extend IMAP and SMTP clients to support SASL PLAIN authentication in addition to existing XOAUTH2. PLAIN credentials MUST only be sent over TLS-encrypted connections.
- **Deliverables**:
  - [ ] `PLAINAuthenticator.swift` — PLAIN token format: `base64("\0" + username + "\0" + password)`
  - [ ] Extend `IMAPClient.swift` — add `authenticatePLAIN(email:password:)` method; MUST verify TLS is active before sending credentials
  - [ ] Extend `SMTPClient.swift` / `SMTPSession.swift` — add PLAIN auth support; MUST verify TLS is active
  - [ ] Capability detection: inspect `AUTH=PLAIN` in IMAP `CAPABILITY` and SMTP `EHLO` responses
  - [ ] Auth mechanism selection logic per FR-MPROV-02 (registry first, then capability detection)
  - [ ] Extend `KeychainManager.swift` — add `apppassword.{accountId}` key pattern for app password storage
  - [ ] Unit tests for PLAIN token encoding, mechanism selection, and TLS enforcement
- **Notes**: PLAIN credentials are app-specific passwords (not the user's primary password). MUST NOT send PLAIN over unencrypted connections. Error messages differ from OAuth: "Invalid email or app password."

### IOS-MP-03: STARTTLS Transport Support

- **Status**: `todo`
- **Spec ref**: Multi-Provider IMAP spec, FR-MPROV-05
- **Validation ref**: AC-MP-03
- **Plan phase**: Phase 1
- **Description**: Implement STARTTLS connection upgrading for IMAP (port 143) and SMTP (port 587). NWConnection does not natively support in-place TLS upgrade, so an alternative socket approach is needed.
- **Deliverables**:
  - [ ] Spike: evaluate `NWConnection` TLS upgrade vs `CFStream` vs POSIX socket + Security.framework (OQ-02)
  - [ ] `STARTTLSConnection.swift` — connect plaintext, send STARTTLS command, upgrade to TLS, re-issue CAPABILITY/EHLO
  - [ ] IMAP STARTTLS: TCP connect (143) → CAPABILITY → STARTTLS → TLS handshake → re-CAPABILITY → AUTH
  - [ ] SMTP STARTTLS: TCP connect (587) → EHLO → STARTTLS → TLS handshake → re-EHLO → AUTH
  - [ ] Certificate validation enforcement (TLS 1.2+, reject self-signed per NFR-SYNC-05)
  - [ ] Abort if server does not advertise STARTTLS in capabilities
  - [ ] `.none` connection mode gated behind `#if DEBUG` only (FR-MPROV-05)
  - [ ] Integration tests against Outlook SMTP (587/STARTTLS) and iCloud SMTP (587/STARTTLS)
  - [ ] Unit tests for STARTTLS handshake sequence and error cases
- **Notes**: This is the highest-risk task. NWConnection limitations may require CFStream or POSIX socket fallback. Spike first, then implement. MUST test on physical devices (simulator may behave differently for TLS upgrades).

### IOS-MP-04: Account Model Extensions

- **Status**: `todo`
- **Spec ref**: Multi-Provider IMAP spec, FR-MPROV-10
- **Validation ref**: AC-MP-04
- **Plan phase**: Phase 1
- **Description**: Extend the `Account` SwiftData model with new nullable fields for provider, IMAP security, and SMTP security. SwiftData lightweight migration adds nullable columns automatically.
- **Deliverables**:
  - [ ] Add to `Account.swift` (`@Model`): `provider: String?`, `imapSecurity: String?`, `smtpSecurity: String?`
  - [ ] Computed properties for app-level defaults: `resolvedProvider` returns `.gmail` if `provider == nil`, etc.
  - [ ] Ensure new accounts populate all three fields explicitly (never left as `nil`)
  - [ ] Unit tests verifying nil-to-default behavior via computed properties
  - [ ] Verify SwiftData lightweight migration succeeds with existing test data (no `VersionedSchema` needed)
- **Notes**: Existing fields (`imapHost`, `imapPort`, `smtpHost`, `smtpPort`, `authType`) are already present and reusable. No write-on-upgrade migration — app-level computed properties handle defaults.

---

## Phase 2: Provider Authentication Flows

### IOS-MP-05: Microsoft OAuth 2.0 (Entra)

- **Status**: `blocked`
- **Spec ref**: Multi-Provider IMAP spec, FR-MPROV-03
- **Validation ref**: AC-MP-05
- **Plan phase**: Phase 2
- **Description**: Implement OAuth 2.0 for Microsoft accounts using Microsoft Entra (Azure AD). Includes PKCE flow via `ASWebAuthenticationSession`, id_token JWT decode for email resolution, and token refresh.
- **Deliverables**:
  - [ ] `MicrosoftOAuthConfig.swift` — Entra auth/token endpoints, scopes (`https://outlook.office365.com/IMAP.AccessAsUser.All https://outlook.office365.com/SMTP.Send offline_access openid email profile`), redirect URI
  - [ ] id_token JWT decode: extract `email` claim, fall back to `preferred_username` (FR-MPROV-03)
  - [ ] id_token OIDC validation (issuer, audience, expiry)
  - [ ] PKCE flow via `ASWebAuthenticationSession` (same pattern as Gmail)
  - [ ] Token refresh using same endpoint (3 retries with exponential backoff)
  - [ ] Multi-tenant support via `/common/` endpoint (consumer + organizational accounts)
  - [ ] Error handling: user cancellation → return to provider selection; token exchange failure → error message; admin consent required → surface to user
  - [ ] Unit tests for id_token decode, OIDC validation, and error paths
  - [ ] Mock OAuth responses for development (pending Azure AD app registration — OQ-01)
- **Notes**: **Blocked** on Azure AD app registration (OQ-01). Development can proceed with mocked OAuth responses. Access token is scoped to `outlook.office365.com` — MUST NOT call Graph API. Email resolution uses id_token JWT claims only.

### IOS-MP-06: App Password Authentication Flow

- **Status**: `todo`
- **Spec ref**: Multi-Provider IMAP spec, FR-MPROV-04
- **Validation ref**: AC-MP-06
- **Plan phase**: Phase 2
- **Description**: Implement the app-password entry flow for iCloud, Yahoo, and generic IMAP providers. Includes provider-specific setup instructions, connection testing, and Keychain storage.
- **Deliverables**:
  - [ ] `AppPasswordEntryView.swift` — SecureField for password entry with provider-specific instructions
  - [ ] Provider-specific instruction text: iCloud (appleid.apple.com instructions), Yahoo (login.yahoo.com instructions), generic (contact provider)
  - [ ] "Open in browser" button to launch provider's password generation page
  - [ ] IMAP connection test after password entry (connect + AUTH PLAIN)
  - [ ] SMTP connection test (connect + AUTH PLAIN)
  - [ ] If IMAP passes but SMTP fails → warn user that receiving works but sending won't
  - [ ] App password stored in Keychain via `apppassword.{accountId}` key (IOS-MP-02)
  - [ ] Error messages: "Invalid email or app password", "Could not connect to server", "Secure connection failed"
  - [ ] Retry without re-entering email on auth failure
  - [ ] Unit tests for flow states and error handling
- **Notes**: App passwords are required because Yahoo blocks new OAuth app registrations for mail scope, and iCloud/generic IMAP servers typically don't support OAuth.

### IOS-MP-07: OAuthManager Refactoring

- **Status**: `todo`
- **Spec ref**: Multi-Provider IMAP spec, FR-MPROV-12
- **Validation ref**: AC-MP-07
- **Plan phase**: Phase 2
- **Description**: Refactor `OAuthManager` from Gmail-hardcoded to provider-configurable. Accept `OAuthProviderConfig` with endpoints, scopes, and email resolution strategy.
- **Deliverables**:
  - [ ] `OAuthProviderConfig.swift` — struct: `authEndpoint`, `tokenEndpoint`, `clientId`, `scopes`, `redirectScheme`, `emailResolution: EmailResolutionStrategy`
  - [ ] `EmailResolutionStrategy.swift` — enum: `.userProvided`, `.idTokenClaims`
  - [ ] Refactor `OAuthManager.authenticate()` to accept `OAuthProviderConfig` parameter
  - [ ] Refactor `OAuthManager.refreshToken()` to accept `OAuthProviderConfig` parameter
  - [ ] `formatXOAUTH2String(email:accessToken:)` — unchanged (format is provider-agnostic)
  - [ ] Built-in configs: Gmail (scopes = `https://mail.google.com/` only, `.userProvided`), Outlook (full scopes, `.idTokenClaims`)
  - [ ] Gmail scope MUST be exactly `https://mail.google.com/` per Account Management FR-ACCT-01 and Constitution LG-02
  - [ ] Update `OAuthManagerProtocol` to accept `OAuthProviderConfig` in `authenticate()` and `refreshToken()`
  - [ ] Update `MockOAuthManager` for tests
  - [ ] Unit tests for both email resolution strategies
  - [ ] Regression tests: existing Gmail OAuth flow still works after refactoring
- **Notes**: Critical to maintain backward compatibility with existing Gmail accounts. All existing OAuth tests MUST continue to pass.

---

## Phase 3: Discovery & Account Setup

### IOS-MP-08: Provider Auto-Discovery

- **Status**: `todo`
- **Spec ref**: Multi-Provider IMAP spec, FR-MPROV-06
- **Validation ref**: AC-MP-08
- **Plan phase**: Phase 3
- **Description**: Implement auto-discovery chain for unknown email domains: built-in registry → Mozilla ISPDB → DNS SRV → MX heuristic → manual setup fallback.
- **Deliverables**:
  - [ ] `AutoDiscoveryService.swift` — orchestrates the discovery chain with 10s timeout per method, 30s total
  - [ ] Built-in registry lookup (instant, no network) — delegates to `ProviderRegistry`
  - [ ] Mozilla ISPDB query: fetch and parse `https://autoconfig.thunderbird.net/v1.1/{domain}` XML
  - [ ] Parse `<incomingServer type="imap">` and `<outgoingServer type="smtp">`: hostname, port, socketType, authentication
  - [ ] DNS SRV record query: `_imap._tcp.{domain}` and `_submission._tcp.{domain}` via system DNS resolver
  - [ ] MX record heuristic: resolve MX records, infer provider (e.g., `*.google.com` → Gmail, `*.outlook.com` → Outlook)
  - [ ] Cache successful ISPDB lookups in UserDefaults (domain → config mapping)
  - [ ] Privacy: ISPDB queries transmit only the email domain, not the full email address (Constitution P-01)
  - [ ] Non-fatal failures: silently proceed to next discovery method
  - [ ] Unit tests for XML parsing, DNS record parsing, MX heuristic, caching, and timeout behavior
- **Notes**: All auto-discovery failures are non-fatal. The chain stops at first success. ISPDB covers thousands of providers. Cache may be time-limited (OQ-04).

### IOS-MP-09: Manual Account Setup

- **Status**: `todo`
- **Spec ref**: Multi-Provider IMAP spec, FR-MPROV-07
- **Validation ref**: AC-MP-09
- **Plan phase**: Phase 3
- **Description**: Implement manual server configuration UI for providers that cannot be auto-detected. Includes connection testing with per-step pass/fail checklist.
- **Deliverables**:
  - [ ] `ManualSetupView.swift` — form with all required fields (email, display name, IMAP host/port/security, SMTP host/port/security, auth method, password)
  - [ ] Field defaults: IMAP port 993, SMTP port 587, IMAP security `.tls`, SMTP security `.starttls`, auth `App Password`
  - [ ] Auto-fill from auto-discovery partial results (if available)
  - [ ] `ConnectionTestView.swift` — 4-step checklist: IMAP connection, IMAP auth, SMTP connection, SMTP auth
  - [ ] Connection test: TCP connect → TLS/STARTTLS → authenticate → disconnect
  - [ ] Proceed button enabled only when all 4 checks pass
  - [ ] Specific error messages per failure (e.g., "IMAP auth failed — check your password")
  - [ ] Edit fields and re-test without starting over
  - [ ] Accessibility: all form fields with `accessibilityLabel` and `accessibilityHint`
  - [ ] Unit tests for form validation and connection test state machine
- **Notes**: The connection test runs all 4 checks sequentially. Users see per-step results in real time. This view is the terminal fallback when auto-discovery fails.

### IOS-MP-10: Onboarding and Provider Selection UI

- **Status**: `todo`
- **Spec ref**: Multi-Provider IMAP spec, FR-MPROV-11
- **Validation ref**: AC-MP-10
- **Plan phase**: Phase 3
- **Description**: Update the "Add Account" flow with email-first provider detection, branded quick-add buttons, and provider-appropriate auth routing.
- **Deliverables**:
  - [ ] `ProviderSelectionView.swift` — email input field with live domain detection; branded buttons for Gmail, Outlook, Yahoo, iCloud; "Other" button for manual setup
  - [ ] Flow routing: Gmail/Outlook → OAuth flow; Yahoo/iCloud → app password flow; Unknown → auto-discovery → manual setup
  - [ ] Replace "Sign in with Google" with provider-specific text ("Sign in with Microsoft" for Outlook, etc.)
  - [ ] Replace all "Gmail account" text with "email account"
  - [ ] Welcome screen text: "Add your email account. Works with Gmail, Outlook, Yahoo, iCloud, and any IMAP provider."
  - [ ] Update `OnboardingView.swift` to use `ProviderSelectionView` instead of Gmail-only flow
  - [ ] Accessibility: provider buttons with descriptive VoiceOver labels ("Add Gmail account", etc.); connection test results announced via `AccessibilityNotification.Announcement`
  - [ ] Unit tests for provider detection from email domain and flow routing
- **Notes**: The email-first approach auto-detects the provider as the user types. Quick-add buttons are shortcuts for common providers.

---

## Phase 4: Sync Compatibility

### IOS-MP-11: Provider-Agnostic Folder Mapping

- **Status**: `todo`
- **Spec ref**: Multi-Provider IMAP spec, FR-MPROV-08
- **Validation ref**: AC-MP-11
- **Plan phase**: Phase 4
- **Description**: Replace `GmailFolderMapper` with a provider-agnostic folder mapping strategy using RFC 6154 SPECIAL-USE attributes as primary, provider-specific name maps as secondary, and generic heuristics as tertiary.
- **Deliverables**:
  - [ ] `IMAPFolderMapper.swift` — strategy-pattern mapper with three-tier resolution
  - [ ] Tier 1: RFC 6154 SPECIAL-USE attribute mapping (`\Inbox`, `\Sent`, `\Drafts`, `\Trash`, `\Junk`, `\Flagged`, `\All`)
  - [ ] Tier 2: Provider-specific name fallback maps (Gmail, Outlook, Yahoo, iCloud — all from FR-MPROV-08)
  - [ ] Tier 3: Generic case-insensitive substring heuristic (contains `sent`, `draft`, `trash`, `junk`, `spam`, `archive`, `starred`, `flagged`)
  - [ ] Excluded folders: `\Noselect` attribute, Gmail `[Gmail]/All Mail` + `[Gmail]/Important`, iCloud `Notes`
  - [ ] Provider-specific `excludedFolders` from registry
  - [ ] Error handling: zero syncable folders → "No email folders found"
  - [ ] Update `SyncEmailsUseCase` to inject `IMAPFolderMapper` instead of `GmailFolderMapper`
  - [ ] Unit tests for all three mapping tiers, excluded folders, and zero-folder error
  - [ ] Regression test: existing Gmail folder mapping produces identical results
- **Notes**: The mapper is resolved based on the account's `provider` field. For `.custom` providers, only tiers 1 and 3 are used (no provider-specific name map).

### IOS-MP-12: Sync Compatibility Layer

- **Status**: `todo`
- **Spec ref**: Multi-Provider IMAP spec, FR-MPROV-13
- **Validation ref**: AC-MP-12
- **Plan phase**: Phase 4
- **Description**: Adapt the sync engine for provider-specific behaviors: archive, delete, draft sync, sent folder append, and flag support variance.
- **Deliverables**:
  - [ ] Archive behavior: Gmail → existing COPY to All Mail; non-Gmail → COPY to Archive folder (if exists) + DELETE from source; no Archive folder → prompt "Move to a specific folder instead?"
  - [ ] Delete behavior: all providers → COPY to Trash + DELETE from source (Trash identified via folder mapper)
  - [ ] Draft sync: non-Gmail → IMAP APPEND to Drafts folder with `\Draft` flag; Drafts folder not found → local-only save + warning
  - [ ] Sent folder append: check `requiresSentAppend` from provider registry; true → APPEND to Sent with `\Seen`; false (Gmail) → skip
  - [ ] Flag support variance: attempt `STORE +FLAGS (\Flagged)` and handle server `NO` rejection → surface "This provider does not support starred emails" + revert local state
  - [ ] IDLE behavior: unchanged across providers; only refresh interval varies (per IOS-MP-13)
  - [ ] Unit tests for each provider's archive, delete, draft, and sent behaviors
  - [ ] Unit tests for flag rejection handling
- **Notes**: The sync engine remains provider-agnostic. Provider-specific behaviors are driven by the provider registry configuration and folder mapper output.

### IOS-MP-13: Per-Provider Connection Pool Configuration

- **Status**: `todo`
- **Spec ref**: Multi-Provider IMAP spec, FR-MPROV-09, FR-MPROV-14
- **Validation ref**: AC-MP-13, AC-ES-06 (FR-MPROV-14 global pool cross-ref)
- **Plan phase**: Phase 4
- **Description**: Update `ConnectionPool` to read per-provider `maxConnections` and IDLE refresh intervals from the provider registry. Enforce global 30-connection limit.
- **Deliverables**:
  - [ ] `ConnectionPool.swift` — read `maxConnections` from account's resolved provider config (was hardcoded)
  - [ ] IDLE refresh interval in `IMAPClient.swift` — read from provider config (was hardcoded 25 min)
  - [ ] Global connection limit: total IMAP connections across all accounts MUST NOT exceed 30
  - [ ] Priority queue: connection checkout requests prioritize currently-viewed account when global limit reached
  - [ ] Idle connection cleanup: platform-specific timeouts (5 min iOS, 15 min macOS per FR-SYNC-16)
  - [ ] Debug logging when connections closed due to idle timeout
  - [ ] Queue timeout: 30 seconds per FR-SYNC-09; queued (not failed) when global limit reached
  - [ ] Unit tests for per-provider limits, global limit enforcement, priority queuing, and idle cleanup
- **Notes**: Yahoo has 5-connection limit and 4-minute IDLE refresh. These are encoded in the provider registry and consumed by the connection pool and IDLE monitor.

---

## Phase 5: Migration & Validation

### IOS-MP-14: Data Migration Validation

- **Status**: `todo`
- **Spec ref**: Multi-Provider IMAP spec, FR-MPROV-15
- **Validation ref**: AC-MP-14
- **Plan phase**: Phase 5
- **Description**: Validate that SwiftData lightweight migration for new Account fields preserves all existing data and sync state. Test migration failure recovery.
- **Deliverables**:
  - [ ] Unit test: pre-migration Account entities load with nil for new fields and resolve to defaults via computed properties
  - [ ] Unit test: existing sync state (`uidValidity`, `lastSyncDate`, `lastSyncedUID`, folders, threads, emails) is unaltered after migration
  - [ ] Unit test: new accounts created after migration have all three fields populated explicitly
  - [ ] Migration failure recovery: if lightweight migration fails, present recovery flow ("Your email data needs to be refreshed") → re-auth all accounts
  - [ ] Verify Keychain credentials survive migration failure (independent of SwiftData)
  - [ ] Integration test with accounts that have active sync state (UIDs, folders, threads)
- **Notes**: SwiftData lightweight migration should "just work" for nullable columns. The tests verify this assumption and ensure the recovery path works if it doesn't.

### IOS-MP-15: End-to-End Integration Testing

- **Status**: `todo`
- **Spec ref**: Multi-Provider IMAP spec, NFR-MPROV-04, NFR-MPROV-05
- **Validation ref**: AC-MP-15
- **Plan phase**: Phase 5
- **Description**: Comprehensive integration testing across all supported providers to verify feature parity and backward compatibility.
- **Deliverables**:
  - [ ] Gmail regression: existing accounts work without re-auth after upgrade (NFR-MPROV-05)
  - [ ] Outlook: OAuth flow, IMAP sync, SMTP send, folder mapping, IDLE, STARTTLS SMTP
  - [ ] Yahoo: app password flow, IMAP sync, SMTP send, folder mapping, 4-min IDLE refresh
  - [ ] iCloud: app password flow, IMAP sync, SMTP send, folder mapping, STARTTLS SMTP
  - [ ] Generic IMAP: manual setup, auto-discovery, connection test, full sync cycle
  - [ ] Cross-provider: unified inbox with multiple providers, account switching, per-account sync status
  - [ ] Auto-discovery: test against known domains (ISPDB hit), unknown domains (fallback chain), offline (skip to manual)
  - [ ] STARTTLS: test on physical device against Outlook SMTP and iCloud SMTP
  - [ ] Performance: auto-discovery < 5s (NFR-MPROV-01), connection test < 10s (NFR-MPROV-02)
  - [ ] Security: credential audit — 0 occurrences outside Keychain (NFR-MPROV-03)
  - [ ] Document known provider-specific quirks and workarounds
- **Notes**: Integration tests require real email accounts for each provider. STARTTLS tests MUST run on physical devices. This is the final validation gate before multi-provider release.
