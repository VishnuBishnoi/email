---
title: "Account Management — iOS/macOS Task Breakdown"
platform: iOS, macOS
plan-ref: docs/features/account-management/ios-macos/plan.md
version: "1.0.0"
status: draft
updated: 2025-02-07
---

# Account Management — iOS/macOS Task Breakdown

> Each task references its plan ID, spec section, and acceptance criteria. Status values: `todo`, `in-progress`, `done`, `blocked`.

---

### IOS-F-03: Keychain Manager

- **Status**: `todo`
- **Spec ref**: Account Management spec, FR-ACCT-04
- **Validation ref**: AC-F-03
- **Description**: Implement a `KeychainManager` that stores and retrieves OAuth tokens with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` protection.
- **Deliverables**:
  - [ ] `KeychainManager.swift` — save, read, delete, update operations
  - [ ] Scoped by account ID
  - [ ] Unit tests for CRUD operations
  - [ ] Error handling for Keychain failures

### IOS-F-04: OAuth 2.0 Manager

- **Status**: `todo`
- **Spec ref**: Account Management spec, FR-ACCT-03
- **Validation ref**: AC-F-04
- **Description**: Implement Gmail OAuth 2.0 with PKCE using `ASWebAuthenticationSession`. Support token exchange, storage, and refresh.
- **Deliverables**:
  - [ ] `OAuthManager.swift` — authorization flow, token exchange, refresh
  - [ ] PKCE code verifier/challenge generation
  - [ ] Integration with KeychainManager for token storage
  - [ ] Automatic token refresh before expiry
  - [ ] Error handling for auth failures, user cancellation
  - [ ] Integration test with real Gmail OAuth

### IOS-F-09: Account Repository

- **Status**: `todo`
- **Spec ref**: Account Management spec, FR-ACCT-01, FR-ACCT-02, FR-ACCT-05
- **Validation ref**: AC-F-09
- **Description**: Implement `AccountRepositoryImpl` for account CRUD, token management, and configuration storage.
- **Deliverables**:
  - [ ] `AccountRepositoryImpl.swift` — all protocol methods
  - [ ] Add account (OAuth + IMAP validation)
  - [ ] Remove account (cascade delete all data)
  - [ ] Update account configuration
  - [ ] Token refresh delegation
  - [ ] Unit tests with mocked Keychain
