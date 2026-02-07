---
title: "Account Management — iOS/macOS Validation"
spec-ref: docs/features/account-management/spec.md
plan-refs:
  - docs/features/account-management/ios-macos/plan.md
  - docs/features/account-management/ios-macos/tasks.md
version: "1.1.0"
status: draft
last-validated: null
---

# Account Management — Validation: Acceptance Criteria & Test Plan

> The key words **MUST**, **MUST NOT**, **REQUIRED**, **SHALL**, **SHALL NOT**, **SHOULD**, **SHOULD NOT**, **RECOMMENDED**, **MAY**, and **OPTIONAL** in this document are to be interpreted as described in [RFC 2119](https://www.ietf.org/rfc/rfc2119.txt).

---

## 1. Traceability Matrix

| Req ID | Requirement Summary | Keyword | Test Case IDs | Platform | Status |
|--------|-------------------|---------|---------------|----------|--------|
| FR-ACCT-01 | Account addition via OAuth | MUST | AC-F-04 | Both | — |
| FR-ACCT-02 | Account configuration | MUST | AC-F-09 | Both | — |
| FR-ACCT-04 | Token management | MUST | AC-F-03, AC-F-04b | Both | — |
| FR-ACCT-05 | Account removal + data deletion | MUST | AC-SEC-03 | Both | — |
| NFR-ACCT-01 | OAuth token security | MUST | AC-SEC-02 | Both | — |
| NFR-SEC-01 | TLS enforcement during IMAP/SMTP validation | MUST | AC-F-04 | Both | — |

---

## 2. Acceptance Criteria

---

**AC-F-03**: Keychain Manager

- **Given**: A `KeychainManager` instance
- **When**: An OAuth token is stored for a given account ID
- **Then**: The token **MUST** be retrievable using the same account ID
  AND the token **MUST NOT** be retrievable after deletion
  AND the token **MUST** be stored with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`
  AND storing a token for the same account ID **MUST** update the existing entry
- **Priority**: Critical

---

**AC-F-04**: OAuth 2.0 Flow

- **Given**: A user with a valid Gmail account
- **When**: The user initiates account addition
- **Then**: A system browser **MUST** open to Google's OAuth consent page
  AND after user consent, the app **MUST** receive an authorization code
  AND the app **MUST** exchange the code for access + refresh tokens
  AND tokens **MUST** be stored in the Keychain
  AND IMAP authentication with XOAUTH2 **MUST** succeed using the access token
  AND IMAP/SMTP connections during validation **MUST** use TLS with server certificate verification (per Foundation NFR-SEC-01)
- **Priority**: Critical

**AC-F-04b**: Token Refresh

- **Given**: An account with an expired access token
- **When**: The app attempts an IMAP operation
- **Then**: The app **MUST** automatically refresh the token using the refresh token
  AND the new token **MUST** be stored in the Keychain
  AND the IMAP operation **MUST** succeed with the new token
  AND if refresh fails, the user **MUST** be prompted to re-authenticate
- **Priority**: Critical

---

**AC-F-09**: Account Repository

- **Given**: An `AccountRepositoryImpl`
- **When**: Account operations are performed
- **Then**: `addAccount` **MUST** store account config in SwiftData and tokens in Keychain
  AND `removeAccount` **MUST** cascade delete all associated data per FR-FOUND-03: Folders, EmailFolder associations, Emails, Threads, Attachments, SearchIndex entries, and Keychain tokens
  AND `getAccounts` **MUST** return all configured accounts
  AND `updateAccount` **MUST** persist configuration changes
- **Priority**: Critical

---

**AC-SEC-02**: Credential Security

- **Given**: The app has configured accounts
- **When**: The device file system is inspected
- **Then**: OAuth tokens **MUST NOT** appear in any file outside the Keychain
  AND the SwiftData database **MUST NOT** contain plaintext tokens
  AND tokens **MUST** be stored with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`
- **Priority**: Critical

---

**AC-SEC-03**: Data Deletion on Account Removal

- **Given**: An account with 50,000 synced emails and AI-generated data
- **When**: The account is removed
- **Then**: All emails, folders, threads, attachments, search index entries, and AI cache for the account **MUST** be deleted from SwiftData
  AND Keychain tokens for the account **MUST** be deleted
  AND no orphaned data **MUST** remain
  AND the operation **MUST** complete within 15 seconds (per NFR-ACCT-02)
- **Priority**: Critical

---

## 3. Edge Cases

| # | Scenario | Expected Behavior |
|---|---------|-------------------|
| E-02 | OAuth token refresh fails (revoked) | User sees "Re-authenticate" modal prompt; if dismissed, account enters inactive state (isActive=false) with warning badge; sync suspended; local data preserved; no crash; other accounts unaffected |
| E-03 | Network disconnect during OAuth flow | ASWebAuthenticationSession shows system error; user returned to account list; no partial account created |
| E-04 | User cancels OAuth consent | ASWebAuthenticationSession dismissed; user returned to account list; no data stored |
| E-05 | Authorization code expires before exchange | Token exchange fails; user sees error with "Try Again" action; no partial account created |

---

## 4. Performance Validation

| Metric | Target | Hard Limit | Measurement Method | Failure Threshold |
|--------|--------|------------|--------------------|-------------------|
| Account removal | < 5s | 15s | Time to delete all data for account with 50,000 emails (per NFR-STOR-01) | Fails if > 15s |

---

## 5. Device Test Matrix

Refer to Foundation validation Section 5 for shared device test matrix.

---

## 6. Sign-Off

| Reviewer | Role | Date | Status |
|----------|------|------|--------|
| — | Spec Author | — | — |
| — | QA Lead | — | — |
| — | Engineering Lead | — | — |
