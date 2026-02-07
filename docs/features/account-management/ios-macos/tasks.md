---
title: "Account Management — iOS/macOS Task Breakdown"
platform: iOS, macOS
plan-ref: docs/features/account-management/ios-macos/plan.md
version: "1.0.0"
status: done
updated: 2026-02-07
---

# Account Management — iOS/macOS Task Breakdown

> Each task references its plan ID, spec section, and acceptance criteria. Status values: `todo`, `in-progress`, `done`, `blocked`.

---

### IOS-F-03: Keychain Manager

- **Status**: `done`
- **Spec ref**: Account Management spec, FR-ACCT-04
- **Validation ref**: AC-F-03
- **Description**: Implement a `KeychainManager` that stores and retrieves OAuth tokens with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` protection.
- **Deliverables**:
  - [x] `KeychainManager.swift` — save, read, delete, update operations
  - [x] Scoped by account ID
  - [x] Unit tests for CRUD operations (7 tests in `KeychainManagerTests.swift`)
  - [x] Error handling for Keychain failures (`KeychainError` enum)
- **Files created**:
  - `Domain/Protocols/KeychainManagerProtocol.swift`
  - `Domain/Errors/KeychainError.swift`
  - `Data/Keychain/KeychainManager.swift`
  - `Tests/.../KeychainManagerTests.swift`
  - `Tests/.../Mocks/MockKeychainManager.swift`

### IOS-F-04: OAuth 2.0 Manager

- **Status**: `done`
- **Spec ref**: Account Management spec, FR-ACCT-03
- **Validation ref**: AC-F-04
- **Description**: Implement Gmail OAuth 2.0 with PKCE using `ASWebAuthenticationSession`. Support token exchange, storage, and refresh.
- **Deliverables**:
  - [x] `OAuthManager.swift` — authorization flow, token exchange, refresh
  - [x] PKCE code verifier/challenge generation (SHA256 + base64url)
  - [x] Integration with KeychainManager for token storage (via AccountRepositoryImpl)
  - [x] Automatic token refresh with exponential backoff (3 retries)
  - [x] Error handling for auth failures, user cancellation
  - [x] XOAUTH2 SASL string formatting for IMAP/SMTP auth
  - [ ] Integration test with real Gmail OAuth (deferred to UI integration)
- **Files created**:
  - `Domain/Models/OAuthToken.swift`
  - `Domain/Protocols/OAuthManagerProtocol.swift`
  - `Domain/Errors/OAuthError.swift`
  - `Data/Network/OAuthManager.swift`
  - `Tests/.../OAuthManagerTests.swift`
  - `Tests/.../Mocks/MockOAuthManager.swift`

### IOS-F-09: Account Repository

- **Status**: `done`
- **Spec ref**: Account Management spec, FR-ACCT-01, FR-ACCT-02, FR-ACCT-05
- **Validation ref**: AC-F-09
- **Description**: Implement `AccountRepositoryImpl` for account CRUD, token management, and configuration storage.
- **Deliverables**:
  - [x] `AccountRepositoryImpl.swift` — all protocol methods
  - [x] Add account with duplicate email check
  - [x] Remove account (cascade deletes folders, threads, emails, attachments, emailFolders + Keychain cleanup)
  - [x] Update account configuration
  - [x] Token refresh delegation with account deactivation on max retries
  - [x] Unit tests with mocked Keychain and OAuth (11 tests in `AccountRepositoryTests.swift`)
- **Files created**:
  - `Domain/Errors/AccountError.swift`
  - `Data/Repositories/AccountRepositoryImpl.swift`
  - `Tests/.../AccountRepositoryTests.swift`
- **Files modified**:
  - `Domain/Protocols/AccountRepositoryProtocol.swift` (added `refreshToken(for:)`)
  - `Shared/Constants.swift` (added OAuth configuration constants)
