---
title: "Multi-Provider IMAP — Validation: Acceptance Criteria & Test Plan"
spec-ref: docs/features/multi-provider-imap/spec.md
plan-refs:
  - docs/features/multi-provider-imap/ios-macos/plan.md
  - docs/features/multi-provider-imap/ios-macos/tasks.md
version: "1.0.0"
status: locked
last-validated: null
---

# Multi-Provider IMAP — Validation: Acceptance Criteria & Test Plan

> The key words **MUST**, **MUST NOT**, **REQUIRED**, **SHALL**, **SHALL NOT**, **SHOULD**, **SHOULD NOT**, **RECOMMENDED**, **MAY**, and **OPTIONAL** in this document are to be interpreted as described in [RFC 2119](https://www.ietf.org/rfc/rfc2119.txt).

---

## 1. Traceability Matrix

| Req ID | Requirement Summary | Keyword | Test Case IDs | Platform | Status |
|--------|-------------------|---------|---------------|----------|--------|
| FR-MPROV-01 | Provider configuration registry | MUST | AC-MP-01 | Both | — (IOS-MP-01) |
| FR-MPROV-02 | Multi-mechanism authentication (XOAUTH2 + PLAIN) | MUST | AC-MP-02 | Both | — (IOS-MP-02) |
| FR-MPROV-03 | Microsoft OAuth 2.0 (Entra) | MUST | AC-MP-05 | Both | — (IOS-MP-05) |
| FR-MPROV-04 | App password authentication flow | MUST | AC-MP-06 | Both | — (IOS-MP-06) |
| FR-MPROV-05 | STARTTLS transport support | MUST | AC-MP-03 | Both | — (IOS-MP-03) |
| FR-MPROV-06 | Provider auto-discovery | MUST | AC-MP-08 | Both | — (IOS-MP-08) |
| FR-MPROV-07 | Manual account setup | MUST | AC-MP-09 | Both | — (IOS-MP-09) |
| FR-MPROV-08 | Provider-agnostic folder mapping | MUST | AC-MP-11 | Both | — (IOS-MP-11) |
| FR-MPROV-09 | Per-provider connection configuration | MUST | AC-MP-13 | Both | — (IOS-MP-13) |
| FR-MPROV-10 | Account model extensions | MUST | AC-MP-04 | Both | — (IOS-MP-04) |
| FR-MPROV-11 | Onboarding and account setup UI | MUST | AC-MP-10 | Both | — (IOS-MP-10) |
| FR-MPROV-12 | OAuthManager refactoring | MUST | AC-MP-07 | Both | — (IOS-MP-07) |
| FR-MPROV-13 | Email sync compatibility (archive, delete, draft, sent) | MUST | AC-MP-12 | Both | — (IOS-MP-12) |
| FR-MPROV-14 | Multi-account sync (cross-reference) | MUST | AC-MP-13, AC-ES-06 | Both | — (AC-MP-13 covers global pool in IOS-MP-13; AC-ES-06 cross-ref to Email Sync) |
| FR-MPROV-15 | Data migration validation | MUST | AC-MP-14 | Both | — (IOS-MP-14) |
| NFR-MPROV-01 | Auto-discovery speed (< 5s) | MUST | AC-MP-08 | Both | — |
| NFR-MPROV-02 | Connection test speed (< 10s) | MUST | AC-MP-09 | Both | — |
| NFR-MPROV-03 | Credential security (0 outside Keychain) | MUST | AC-MP-15 | Both | — |
| NFR-MPROV-04 | Provider parity | MUST | AC-MP-15 | Both | — |
| NFR-MPROV-05 | Backward compatibility (Gmail no re-auth) | MUST | AC-MP-15 | Both | — |
| NFR-MPROV-06 | STARTTLS security (TLS 1.2+) | MUST | AC-MP-03 | Both | — |
| NFR-MPROV-07 | Global connection resource usage | MUST | AC-ES-06 | Both | — (cross-ref to Email Sync) |

---

## 2. Acceptance Criteria

---

**AC-MP-01**: Provider Configuration Registry — **Not started**

- **Given**: The app with built-in provider registry
- **When**: An email domain is looked up in the registry
- **Then**: Known domains (gmail.com, outlook.com, yahoo.com, icloud.com) **MUST** return the correct pre-configured provider with IMAP/SMTP host, port, security mode, auth mechanism, maxConnections, idleRefreshInterval, folderNameMap, excludedFolders, and requiresSentAppend
  AND unknown domains **MUST** fall back to `.custom` with conservative defaults (maxConnections=5, idleRefreshInterval=20min)
  AND the registry **MUST** include `oauthConfig` for OAuth providers (Gmail, Outlook) and `nil` for PLAIN-only providers (Yahoo, iCloud)
- **Priority**: Critical

---

**AC-MP-02**: SASL PLAIN Authentication — **Not started**

- **Given**: An account configured with PLAIN auth mechanism and an app password stored in Keychain
- **When**: The IMAP or SMTP client authenticates
- **Then**: The client **MUST** construct a valid SASL PLAIN token: `base64("\0" + email + "\0" + password)`
  AND the client **MUST** verify TLS is active before sending PLAIN credentials
  AND if TLS is not active, the client **MUST** abort authentication with an error (not send credentials in cleartext)
  AND IMAP capability `AUTH=PLAIN` **MUST** be detected before attempting PLAIN auth
  AND app passwords **MUST** be stored at `apppassword.{accountId}` in Keychain
- **Priority**: Critical

---

**AC-MP-03**: STARTTLS Transport — **Not started**

- **Given**: An account configured with STARTTLS security mode
- **When**: The client connects to the IMAP or SMTP server
- **Then**: IMAP STARTTLS **MUST** follow: TCP connect (143) → CAPABILITY → STARTTLS → TLS handshake → re-CAPABILITY → AUTH
  AND SMTP STARTTLS **MUST** follow: TCP connect (587) → EHLO → STARTTLS → TLS handshake → re-EHLO → AUTH
  AND the TLS handshake **MUST** enforce TLS 1.2+ and reject self-signed certificates (NFR-SYNC-05, NFR-MPROV-06)
  AND if the server does not advertise STARTTLS in capabilities, the client **MUST** abort the connection
  AND `.none` security mode **MUST** only be available in `#if DEBUG` builds
- **Priority**: Critical

---

**AC-MP-04**: Account Model Extensions — **Not started**

- **Given**: An existing SwiftData store with Gmail-only accounts (pre-migration)
- **When**: The app launches after update
- **Then**: SwiftData lightweight migration **MUST** succeed without data loss
  AND new fields (`provider`, `imapSecurity`, `smtpSecurity`) **MUST** be `nil` for existing accounts
  AND computed properties **MUST** resolve `nil` to defaults (provider → `.gmail`, imapSecurity → `.tls`, smtpSecurity → `.tls`)
  AND new accounts **MUST** populate all three fields explicitly (never left as `nil`)
  AND existing sync state (uidValidity, lastSyncDate, folders, threads, emails) **MUST** be unaltered
- **Priority**: Critical

---

**AC-MP-05**: Microsoft OAuth 2.0 — **Not started**

- **Given**: A user adding a Microsoft account (Outlook/Office 365)
- **When**: OAuth flow is initiated
- **Then**: The client **MUST** launch `ASWebAuthenticationSession` with Entra `/common/` endpoint and PKCE
  AND scopes **MUST** include `https://outlook.office365.com/IMAP.AccessAsUser.All`, `https://outlook.office365.com/SMTP.Send`, `offline_access`, `openid`, `email`, `profile`
  AND email resolution **MUST** decode the `id_token` JWT — extract `email` claim, fall back to `preferred_username`
  AND the client **MUST NOT** call Microsoft Graph API (`/v1.0/me`) for email resolution
  AND token refresh **MUST** use the same Entra token endpoint with 3 retries and exponential backoff
  AND the `/common/` endpoint **MUST** support both consumer (outlook.com) and organizational (Office 365) accounts
- **Priority**: Critical

---

**AC-MP-06**: App Password Authentication Flow — **Not started**

- **Given**: A user adding an iCloud, Yahoo, or generic IMAP account
- **When**: The app password entry screen is shown
- **Then**: Provider-specific setup instructions **MUST** be displayed (iCloud → appleid.apple.com, Yahoo → login.yahoo.com, generic → "Contact your provider")
  AND an "Open in browser" button **MUST** launch the provider's app-password generation page
  AND after password entry, an IMAP connection test (connect + AUTH PLAIN) **MUST** be performed
  AND an SMTP connection test **MUST** also be performed
  AND if IMAP passes but SMTP fails, the user **MUST** be warned that receiving works but sending won't
  AND auth failure **MUST** display "Invalid email or app password" (not generic OAuth-style errors)
  AND retry **MUST NOT** require re-entering the email address
- **Priority**: Critical

---

**AC-MP-07**: OAuthManager Refactoring — **Not started**

- **Given**: The refactored `OAuthManager` accepting `OAuthProviderConfig`
- **When**: OAuth is used for Gmail or Outlook
- **Then**: Gmail scopes **MUST** be exactly `https://mail.google.com/` (per Constitution LG-02 and Account Management FR-ACCT-01)
  AND Gmail email resolution **MUST** use `.userProvided` strategy (user enters email, validated via IMAP)
  AND Outlook email resolution **MUST** use `.idTokenClaims` strategy (JWT decode)
  AND `OAuthProviderConfig` **MUST** contain: authEndpoint, tokenEndpoint, clientId, scopes, redirectScheme, emailResolution
  AND existing Gmail OAuth flow **MUST** continue to work without any behavioral change (backward compatibility)
- **Priority**: Critical

---

**AC-MP-08**: Provider Auto-Discovery — **Not started**

- **Given**: A user entering an email with an unknown domain
- **When**: Auto-discovery is triggered
- **Then**: The discovery chain **MUST** execute: built-in registry → Mozilla ISPDB → DNS SRV → MX heuristic → manual setup fallback
  AND each method **MUST** have a 10-second timeout; total chain **MUST** not exceed 30 seconds
  AND ISPDB queries **MUST** transmit only the email domain, not the full email address (Constitution P-01)
  AND successful ISPDB lookups **SHOULD** be cached in UserDefaults
  AND all discovery failures **MUST** be non-fatal — the chain proceeds to the next method silently
  AND auto-discovery **MUST** complete within 5 seconds for known ISPDB domains (NFR-MPROV-01)
- **Priority**: Medium

---

**AC-MP-09**: Manual Account Setup — **Not started**

- **Given**: A user who reached the manual setup screen (auto-discovery failed or user chose "Other")
- **When**: The manual setup form is displayed
- **Then**: The form **MUST** include: email, display name, IMAP host/port/security, SMTP host/port/security, auth method, password
  AND defaults **MUST** be: IMAP port 993, SMTP port 587, IMAP security `.tls`, SMTP security `.starttls`, auth `App Password`
  AND a 4-step connection test checklist **MUST** run: IMAP connection, IMAP auth, SMTP connection, SMTP auth
  AND the proceed button **MUST** be disabled until all 4 checks pass
  AND connection testing **MUST** complete within 10 seconds (NFR-MPROV-02)
  AND the user **MUST** be able to edit fields and re-test without restarting the flow
  AND all form fields **MUST** have `accessibilityLabel` and `accessibilityHint`
- **Priority**: Medium

---

**AC-MP-10**: Onboarding and Provider Selection UI — **Not started**

- **Given**: A user tapping "Add Account" (onboarding or from account switcher)
- **When**: The provider selection screen is shown
- **Then**: An email input field **MUST** detect the provider from the domain as the user types
  AND branded quick-add buttons **MUST** be shown for Gmail, Outlook, Yahoo, and iCloud
  AND an "Other" button **MUST** route to auto-discovery → manual setup
  AND Gmail/Outlook buttons **MUST** route to OAuth flow; Yahoo/iCloud buttons **MUST** route to app password flow
  AND all provider-specific text **MUST** be correct ("Sign in with Microsoft" for Outlook, not "Sign in with Google")
  AND the welcome screen text **MUST** include "Works with Gmail, Outlook, Yahoo, iCloud, and any IMAP provider"
- **Priority**: Critical

---

**AC-MP-11**: Provider-Agnostic Folder Mapping — **Not started**

- **Given**: An IMAP server with folders that may or may not have SPECIAL-USE attributes
- **When**: Folder discovery runs during sync
- **Then**: Tier 1: RFC 6154 SPECIAL-USE attributes **MUST** be used as the primary mapping strategy
  AND Tier 2: Provider-specific name maps from the provider registry **MUST** be used as fallback
  AND Tier 3: Generic case-insensitive substring heuristics **MUST** be the final fallback
  AND `\Noselect` folders **MUST** be excluded
  AND provider-specific excluded folders **MUST** be honored (e.g., Gmail `[Gmail]/All Mail`, iCloud `Notes`)
  AND zero syncable folders **MUST** produce an error: "No email folders found"
  AND existing Gmail folder mapping **MUST** produce identical results (regression)
- **Priority**: Critical

---

**AC-MP-12**: Sync Compatibility Layer — **Not started**

- **Given**: Accounts from different providers (Gmail, Outlook, Yahoo, iCloud, generic)
- **When**: Archive, delete, draft, send, or flag operations are performed
- **Then**: Archive on Gmail **MUST** use existing COPY to All Mail behavior
  AND archive on non-Gmail **MUST** COPY to Archive folder (if exists) + DELETE from source; if no Archive folder → prompt user
  AND delete on all providers **MUST** COPY to Trash + DELETE from source
  AND draft sync on non-Gmail **MUST** IMAP APPEND to Drafts with `\Draft` flag; Drafts not found → local-only + warning
  AND sent folder append **MUST** check `requiresSentAppend`: true → APPEND with `\Seen`; false (Gmail) → skip
  AND flag rejection (server returns `NO` for `\Flagged`) **MUST** surface "This provider does not support starred emails" and revert local state
- **Priority**: Critical

---

**AC-MP-13**: Per-Provider Connection Pool Configuration — **Not started**

- **Given**: Accounts with different providers, each having different maxConnections and idleRefreshInterval
- **When**: The connection pool manages connections
- **Then**: Per-account connection limits **MUST** be read from the provider registry (e.g., Yahoo=5, Gmail=5, Outlook=5)
  AND IDLE refresh intervals **MUST** be read from the provider registry (e.g., Gmail=25min, Yahoo=4min, Outlook=25min)
  AND global connection limit of 30 **MUST** be enforced across all accounts
  AND platform-specific idle cleanup **MUST** apply (iOS 5min, macOS 15min per FR-SYNC-16)
  AND queue timeout **MUST** be 30 seconds when global limit reached (queued, not failed)
- **Priority**: Medium

---

**AC-MP-14**: Data Migration Validation — **Not started**

- **Given**: An app with pre-existing Gmail-only accounts upgrading to multi-provider version
- **When**: The app launches after update
- **Then**: All existing account data **MUST** survive migration (emails, threads, folders, sync state, attachments)
  AND new nullable fields **MUST** default correctly via computed properties
  AND Keychain credentials **MUST** survive even if SwiftData migration fails
  AND if lightweight migration fails, a recovery flow **MUST** be presented: "Your email data needs to be refreshed" → re-auth all accounts
  AND new accounts created after migration **MUST** have all fields populated explicitly
- **Priority**: Critical

---

**AC-MP-15**: End-to-End Integration Testing — **Not started**

- **Given**: Test accounts for Gmail, Outlook, Yahoo, iCloud, and a generic IMAP provider
- **When**: Full feature regression is run
- **Then**: Gmail regression: existing accounts **MUST** work without re-auth after upgrade (NFR-MPROV-05)
  AND Outlook: OAuth flow, IMAP sync, SMTP send, folder mapping, IDLE, STARTTLS SMTP **MUST** all work
  AND Yahoo: app password flow, IMAP sync, SMTP send, folder mapping, 4-min IDLE refresh **MUST** all work
  AND iCloud: app password flow, IMAP sync, SMTP send, folder mapping, STARTTLS SMTP **MUST** all work
  AND generic IMAP: manual setup, auto-discovery, connection test, full sync cycle **MUST** all work
  AND credential security audit: 0 credential occurrences outside Keychain (NFR-MPROV-03)
  AND auto-discovery **MUST** complete < 5s for ISPDB-known domains (NFR-MPROV-01)
  AND connection test **MUST** complete < 10s for all providers (NFR-MPROV-02)
- **Priority**: Critical

---

## 3. Edge Cases

| # | Scenario | Expected Behavior | Status |
|---|---------|-------------------|--------|
| E-22 | User enters protonmail.com email | Provider detected as unsupported; message: "ProtonMail requires their Bridge app" (NG-01) | — (IOS-MP-10) |
| E-23 | ISPDB returns invalid XML | Discovery silently falls through to DNS SRV | — (IOS-MP-08) |
| E-24 | Server does not advertise STARTTLS | Connection aborted with "Secure connection failed" error | — (IOS-MP-03) |
| E-25 | App password has special characters (!, @, #) | PLAIN auth encodes correctly; no escaping issues | — (IOS-MP-02) |
| E-26 | Outlook tenant blocks consumer accounts | Error surfaced: "Your organization requires admin consent" | — (IOS-MP-05) |
| E-27 | IMAP server has no SPECIAL-USE attributes and non-English folder names | Tier 3 heuristic attempts substring match; unrecognized folders mapped as `custom` | — (IOS-MP-11) |
| E-28 | Provider with no Archive folder | Archive action prompts: "Move to a specific folder instead?" | — (IOS-MP-12) |
| E-29 | Server rejects `\Flagged` flag with NO response | "This provider does not support starred emails"; local state reverted | — (IOS-MP-12) |
| E-30 | SwiftData lightweight migration fails on upgrade | Recovery flow: "Your email data needs to be refreshed" → re-auth | — (IOS-MP-14) |
| E-31 | Auto-discovery chain times out (30s) | User routed to manual setup with partial results pre-filled | — (IOS-MP-08) |
| E-32 | Yahoo IDLE drops after 5 minutes | Provider registry configures 4-min refresh; IDLE re-issued before timeout | — (IOS-MP-13) |

---

## 4. Performance Validation

| Metric | Target | Hard Limit | Measurement Method | Failure Threshold |
|--------|--------|------------|--------------------|-------------------|
| Auto-discovery (ISPDB hit) | < 5s | 10s | Wall clock from email entry to server config resolved (NFR-MPROV-01) | Fails if > 10s |
| Auto-discovery (full chain) | < 15s | 30s | Wall clock through all fallback methods | Fails if > 30s |
| Connection test (4-step) | < 10s | 15s | Wall clock for IMAP connect + auth + SMTP connect + auth (NFR-MPROV-02) | Fails if > 15s |
| Gmail backward compat | No re-auth | No re-auth | Existing Gmail accounts work after upgrade (NFR-MPROV-05) | Any Gmail account requires re-auth |
| Credential security | 0 outside Keychain | 0 | Audit all storage locations (NFR-MPROV-03) | Any credential found outside Keychain |
| STARTTLS handshake | < 2s | 5s | TLS upgrade time on port 143/587 | Fails if > 5s |

---

## 5. Device Test Matrix

Refer to Foundation validation Section 5 for shared device test matrix.

Additional requirements:
- STARTTLS tests **MUST** run on physical devices (simulator may behave differently for TLS upgrades)
- Microsoft OAuth **MUST** be tested on both consumer (outlook.com) and organizational (Office 365) accounts

---

## 6. Sign-Off

| Reviewer | Role | Date | Status |
|----------|------|------|--------|
| — | Spec Author | — | — |
| — | QA Lead | — | — |
| — | Engineering Lead | — | — |
