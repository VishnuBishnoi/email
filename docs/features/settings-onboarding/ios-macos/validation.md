---
title: "Settings & Onboarding — iOS/macOS Validation"
spec-ref: docs/features/settings-onboarding/spec.md
plan-refs:
  - docs/features/settings-onboarding/ios-macos/plan.md
  - docs/features/settings-onboarding/ios-macos/tasks.md
depends-on:
  - docs/features/account-management/ios-macos/validation.md
  - docs/features/email-sync/ios-macos/validation.md
  - docs/features/email-composer/ios-macos/validation.md
  - docs/features/thread-list/ios-macos/validation.md
version: "1.2.0"
status: locked
last-validated: null
---

# Settings & Onboarding — Validation: Acceptance Criteria & Test Plan

> The key words **MUST**, **MUST NOT**, **REQUIRED**, **SHALL**, **SHALL NOT**, **SHOULD**, **SHOULD NOT**, **RECOMMENDED**, **MAY**, and **OPTIONAL** in this document are to be interpreted as described in [RFC 2119](https://www.ietf.org/rfc/rfc2119.txt).

---

## 1. Traceability Matrix

| Req ID | Requirement Summary | Keyword | Test Case IDs | Platform | Status |
|--------|-------------------|---------|---------------|----------|--------|
| FR-SET-01 | Settings screen with all V1 sections | MUST | AC-U-14 | Both | — |
| FR-SET-02 | Account settings surface (add/remove/configure) | MUST | AC-U-14a | Both | — |
| FR-SET-03 | Storage & data management | MUST | AC-U-14b | Both | — |
| FR-SET-04 | AI model management | MUST | AC-U-14c | Both | — |
| FR-SET-05 | Privacy & legal (privacy policy, licenses) | MUST | AC-U-14d | Both | — |
| FR-OB-01 | Onboarding flow (5 steps) | MUST | AC-U-13 | Both | — |
| NFR-SET-01 | Settings persistence across restarts | MUST | PV-SO-01 | Both | — |
| NFR-SET-02 | Accessibility (VoiceOver, Dynamic Type, WCAG 2.1 AA) | MUST | AC-U-13, AC-U-14 | Both | — |
| NFR-SET-03 | Onboarding completion time (< 2min target, 5min limit) | SHOULD | PV-SO-02 | Both | — |
| NFR-SET-04 | Settings save latency (< 100ms target, 500ms limit) | SHOULD | PV-SO-03 | Both | — |
| NFR-SET-05 | Storage calculation time (< 2s target, 5s limit) | SHOULD | PV-SO-04 | Both | — |
| G-01 | Comprehensive settings for all V1 configuration | — | AC-U-14 | Both | — |
| G-02 | Onboarding with privacy messaging and security recommendations | — | AC-U-13 | Both | — |
| G-03 | AI model download with informed consent (URL, size, license) | — | AC-U-13, AC-U-14c | Both | — |
| G-04 | 5 or fewer onboarding screens | — | AC-U-13 | Both | — |
| G-05 | Full accessibility (WCAG 2.1 AA, VoiceOver, Dynamic Type) | — | AC-U-13, AC-U-14 | Both | — |
| G-06 | Per-account storage visibility | — | AC-U-14b | Both | — |
| G-07 | App lock with biometric/passcode | — | AC-U-14 | Both | — |
| G-08 | In-app privacy policy and AI model licenses | — | AC-U-14d | Both | — |

---

## 2. Acceptance Criteria

---

**AC-U-13**: Onboarding Flow

- **Given**: The app is launched for the first time (no accounts configured)
- **When**: The app starts
- **Then**:
  - The onboarding flow **MUST** be displayed (not the thread list) (FR-OB-01)
  - The onboarding **MUST NOT** exceed 5 screens/steps (G-04)
  - **Step 1 — Welcome**: The welcome screen **MUST** display the privacy value proposition: "Your emails stay on your device." (FR-OB-01 step 1)
  - **Step 2 — Account Setup**: The account setup screen **MUST** display "Add your Gmail account" with an Add Account button (FR-OB-01 step 2)
  - Tapping Add Account **MUST** invoke the OAuth 2.0 PKCE flow via `ASWebAuthenticationSession` (FR-ACCT-01, FR-ACCT-03)
  - IMAP/SMTP connectivity **MUST** be validated before the account setup completes (FR-ACCT-01)
  - At least one account **MUST** be added before the user can proceed to the next step (FR-OB-01)
  - If OAuth is cancelled by the user, the screen **MUST** return to Account Setup with the option to retry (FR-OB-01 error table)
  - If OAuth fails due to network error, the screen **MUST** display "Network unavailable. Check your connection and try again." with a Retry button (FR-OB-01 error table)
  - If IMAP/SMTP validation fails, the screen **MUST** display an appropriate error with Retry (FR-OB-01 error table)
  - **Step 3 — Security Recommendations**: The screen **MUST** display security recommendations per Proposal Section 6.4: (1) device passcode + biometric, (2) app lock, (3) encrypted backups, (4) OS updates, (5) review accounts (FR-OB-01 step 3)
  - On macOS, the screen **SHOULD** also recommend FileVault enablement (Foundation Section 9.2)
  - **Step 4 — AI Model Download**: The screen **MUST** display the model source URL, file size, and license **before** download begins (Proposal Section 3.4.1)
  - A skip option **MUST** be clearly labeled: "Skip — the app works without AI features." (FR-OB-01)
  - After download, SHA-256 integrity verification **MUST** be performed (Proposal Section 3.4.1)
  - If SHA-256 mismatch, the corrupted file **MUST** be deleted and the user prompted to retry (FR-OB-01 error table)
  - Expected storage disclosure **MUST** be displayed: "Syncing your email may use [estimated range] of storage" (Constitution TC-06)
  - **Step 5 — Ready**: The feature tour **MUST** be displayed with a "Go to Inbox" button (FR-OB-01 step 5)
  - On completion, initial sync **MUST** be triggered for all added accounts (Email Sync FR-SYNC-01)
  - On completion, the app **MUST** navigate to the Thread List (Inbox view) (FR-OB-01 post-onboarding)
  - The `isOnboardingComplete` flag **MUST** be persisted so onboarding does not re-display (FR-OB-01 post-onboarding)
  - All onboarding screens **MUST** be navigable with VoiceOver with descriptive labels (NFR-SET-02)
  - All text **MUST** scale with Dynamic Type from accessibility extra small through xxxLarge (NFR-SET-02)
  - Transitions **SHOULD** use crossfade when "Reduce Motion" is enabled (NFR-SET-02)
- **Priority**: High

---

**AC-U-14**: Settings Screen — Main Structure

- **Given**: The user has at least one account configured and opens Settings
- **When**: Settings screen is displayed
- **Then**:
  - The settings screen **MUST** be organized into sections: Accounts, Composition, Appearance, AI Features, Notifications, Security, Data Management, About (FR-SET-01)
  - iOS: **MUST** use `NavigationStack` with `.listStyle(.insetGrouped)` (spec Section 7)
  - macOS: **MUST** use `Settings` scene pattern accessible via `⌘,` (spec Section 7)
  - macOS: Settings window **SHOULD** be a singleton (spec Section 7)
  - Theme changes **MUST** apply immediately to the entire app (FR-SET-01)
  - All settings changes **MUST** persist across app restarts (NFR-SET-01)
  - All settings controls **MUST** be navigable and labeled for VoiceOver (NFR-SET-02)
  - Toggle switches **MUST** announce current state (on/off) via VoiceOver (NFR-SET-02)
  - All text **MUST** scale with Dynamic Type (NFR-SET-02)
  - Status indicators **MUST** use icon/shape in addition to color (NFR-SET-02)
- **Priority**: Medium

---

**AC-U-14a**: Account Settings

- **Given**: The user opens the Accounts section in Settings
- **When**: Account-related actions are performed
- **Then**:
  - All configured accounts **MUST** be listed with email address and active/inactive status (FR-SET-02)
  - Per-account sync window picker **MUST** offer 7/14/30/60/90 days (default 30) (FR-SET-02, FR-ACCT-02)
  - Per-account display name **MUST** be editable (FR-SET-02, FR-ACCT-02)
  - When sync window is reduced, a confirmation dialog **MUST** be displayed explaining local purge (FR-SET-01, Foundation Section 8.3)
  - Purge of local emails **MUST NOT** delete from IMAP server (Foundation Section 8.3)
  - Inactive accounts **MUST** display a warning badge with "Re-authenticate" action (FR-SET-02, FR-ACCT-04)
  - Inactive accounts **MUST NOT** be silently hidden (FR-SET-02)
  - "Add Account" **MUST** invoke OAuth 2.0 flow with IMAP/SMTP validation (FR-SET-02, FR-ACCT-01)
  - "Remove Account" **MUST** display a destructive confirmation with cascade delete warning (FR-SET-02, FR-ACCT-05)
  - Removing the last account **MUST** re-trigger the onboarding flow (FR-SET-02, FR-OB-01)
  - Default account picker **MUST** list all active accounts; hidden if only one account exists (FR-SET-01)
  - Undo send delay picker **MUST** offer 0/5/10/15/30 seconds (default 5s) (FR-SET-01, FR-COMP-02)
- **Priority**: Medium

---

**AC-U-14b**: Storage & Data Management

- **Given**: The user opens the Data Management section in Settings
- **When**: Storage or data management actions are performed
- **Then**:
  - Per-account storage breakdown **MUST** be displayed (emails, attachments, search index) (FR-SET-03, Foundation Section 8.2)
  - Total app storage usage **MUST** be displayed (Foundation Section 8.2)
  - Per-account storage exceeding 2 GB **MUST** display a warning (Foundation Section 8.2)
  - Total storage exceeding 5 GB **SHOULD** display a proactive warning (Foundation Section 8.2)
  - Storage loading state **MUST** show a loading indicator (FR-SET-01 view states)
  - If storage calculation fails, "Unable to calculate storage" **MUST** be displayed with retry (FR-SET-01 error handling)
  - "Clear Cache" **MUST** remove downloaded attachments and regenerable caches without deleting emails/accounts/AI models (FR-SET-03)
  - Before clearing cache, the amount of space to be freed **MUST** be displayed (FR-SET-03)
  - Clear cache **MUST** require confirmation (FR-SET-01 view states)
  - If clear cache fails, data **MUST** be preserved and an error displayed (FR-SET-01 error handling)
  - "Wipe All Data" **MUST** require a critical destructive confirmation dialog (FR-SET-03, Foundation Section 9.3)
  - After wipe, the app **MUST** re-trigger the onboarding flow (FR-SET-03, Foundation Section 9.3)
- **Priority**: Medium

---

**AC-U-14c**: AI Model Management

- **Given**: The user opens the AI Features section in Settings
- **When**: AI model management actions are performed
- **Then**:
  - Model status **MUST** display one of: Not downloaded / Downloading (with progress) / Downloaded (FR-SET-04)
  - Before download, the source URL, file size, and license **MUST** be displayed (FR-SET-04, Proposal Section 3.4.1)
  - Download **MUST** use HTTPS and be resumable (HTTP Range) (FR-SET-04)
  - After download, SHA-256 integrity verification **MUST** be performed (FR-SET-04, Proposal Section 3.4.1)
  - If SHA-256 mismatch, the corrupted file **MUST** be deleted and "Download verification failed" displayed (FR-SET-04)
  - Delete model **MUST** display confirmation warning about disabled AI features (FR-SET-04)
  - On deletion, AI features **MUST** degrade gracefully — hidden, not errored (Foundation Section 11)
  - AI Model Licenses **MUST** be accessible from Settings > About (FR-SET-05, Constitution LG-01)
- **Priority**: Medium

---

**AC-U-14d**: Privacy & Legal

- **Given**: The user opens the About section in Settings
- **When**: Privacy or legal information is accessed
- **Then**:
  - App version and build number **MUST** be displayed (FR-SET-05)
  - Privacy Policy **MUST** be accessible in-app (FR-SET-05, Constitution LG-02, Foundation Section 10.3)
  - The same privacy policy URL **MUST** be used on the OAuth consent screen (Constitution LG-02)
  - Open Source Licenses page **MUST** list all third-party dependency licenses (FR-SET-05)
  - AI Model Licenses page **MUST** list model name, license type, and source (FR-SET-05, Constitution LG-01, Foundation Section 10.1)
- **Priority**: Low

---

## 3. Edge Cases

| ID | Scenario | Expected Behavior | Spec Ref |
|----|----------|-------------------|----------|
| E-SO-01 | OAuth cancelled by user during onboarding | Return to Account Setup screen; allow retry or try different account; do NOT advance to next step | FR-OB-01 error table |
| E-SO-02 | Network lost during OAuth flow in onboarding | Display "Network unavailable. Check your connection and try again." with Retry button | FR-OB-01 error table |
| E-SO-03 | OAuth succeeds but IMAP validation fails | Display "Couldn't connect to Gmail. Please check account permissions." with Retry; account is NOT added | FR-OB-01 error table, FR-ACCT-01 |
| E-SO-04 | Network lost during AI model download (onboarding) | Display "Download failed. You can download later in Settings." with Skip option | FR-OB-01 error table |
| E-SO-05 | AI model SHA-256 checksum mismatch | Delete corrupted file; display "Download verification failed. Please retry." with Retry and Skip | FR-OB-01 error table, FR-SET-04 |
| E-SO-06 | Force-quit app during onboarding (before completion) | On relaunch, onboarding restarts from the beginning; `isOnboardingComplete` remains false | FR-OB-01 post-onboarding |
| E-SO-07 | Force-quit app during AI model download | Download is interrupted; on next launch, model status is "Not downloaded"; user can retry in onboarding or Settings | FR-SET-04 |
| E-SO-08 | Last account removed from Settings | App re-triggers the full onboarding flow; ensures user always has at least one account | FR-SET-02, FR-OB-01 post-onboarding |
| E-SO-09 | Wipe All Data from Settings | Critical destructive confirmation; delete all accounts, emails, AI models, caches, Keychain; re-trigger onboarding | FR-SET-03, Foundation Section 9.3 |
| E-SO-10 | Sync window reduced from 90 to 7 days | Confirmation dialog explaining local purge; purge within 24 hours; server emails unaffected | FR-SET-01, Foundation Section 8.3 |
| E-SO-11 | Biometric enrollment unavailable (no Face ID/Touch ID hardware) | `LAContext` automatically falls back to device passcode; app lock still functional | FR-SET-01, Foundation Section 9.2 |
| E-SO-12 | Biometric evaluation fails (e.g., finger not recognized) | `LAContext` handles fallback to device passcode automatically | FR-SET-01 |
| E-SO-13 | Storage calculation for account with 50,000+ emails | Async calculation with loading indicator; results cached for session; must not block UI | NFR-SET-04, FR-SET-03 |
| E-SO-14 | Clear cache triggered while sync is in progress | Cache clear should complete; next sync re-downloads needed attachments | FR-SET-03 |
| E-SO-15 | AI model download when insufficient disk space | Check available space before download; display model size; abort with clear error if insufficient space | FR-SET-04 |
| E-SO-16 | Theme change applies immediately | Switching System→Dark→Light must apply without app restart via `preferredColorScheme` | FR-SET-01 |
| E-SO-17 | Inactive account displayed in account list | Warning badge visible; "Re-authenticate" action available; inactive account NOT silently hidden | FR-SET-02, FR-ACCT-04 |
| E-SO-18 | Category toggles when AI model not downloaded | Category tab toggles disabled with note "Download AI model to enable categories" | FR-SET-01 |
| E-SO-19 | AI model deleted from Settings | Confirmation dialog shown; on deletion, smart categories/reply/summarization hidden (not errored); category toggles disabled | FR-SET-04, Foundation Section 11 |
| E-SO-20 | App launched after `isOnboardingComplete = true` with all accounts removed (e.g., data corruption) | `isOnboardingComplete` must be reset; onboarding flow re-triggered to ensure at least one account | FR-OB-01 post-onboarding |
| E-SO-21 | Notification permission denied by user | In-app banners remain functional (per-account toggle still controls in-app behavior); local notifications cannot be posted; notification toggle SHOULD display note "System notifications are disabled. Enable in iOS Settings to receive background alerts." with link to system Settings | FR-SET-01 |
| E-SO-22 | Background fetch detects new mail with notifications enabled | Client posts local notification via UNUserNotificationCenter with sender name, subject line, and badge update. No push relay server involved (Constitution P-02). | FR-SET-01, Constitution P-02 |
| E-SO-23 | User expects app lock to protect specific within-app screens | App lock applies at app boundary only (cold launch + background return). No within-app re-authentication for specific screens or actions in V1. User proceeds without additional prompts once unlocked. | FR-SET-01, Foundation Section 9.2 |

---

## 4. Performance Validation

| ID | Metric | Target | Hard Limit | Measurement | Failure Threshold | Spec Ref |
|----|--------|--------|------------|-------------|-------------------|----------|
| PV-SO-01 | Settings persistence | Immediate (before UI confirms) | < 1 second | Change setting → force-quit → relaunch → verify | Fails if any setting reverts after force-quit | NFR-SET-01 |
| PV-SO-02 | Onboarding completion time (excl. AI download) | < 2 minutes | 5 minutes | Stopwatch from Welcome to Thread List on iPhone SE 3rd gen | Fails if > 5 min on 3 consecutive attempts | NFR-SET-03 |
| PV-SO-03 | Settings save latency | < 100ms | 500ms | Time from toggle/picker change to UserDefaults write on iPhone SE 3rd gen | Fails if > 500ms on 3 consecutive changes | NFR-SET-04 |
| PV-SO-04 | Storage calculation time | < 2 seconds | 5 seconds | Time from opening Storage Settings to display of per-account breakdown on device with 10K emails | Fails if > 5s on 3 consecutive attempts | FR-SET-03 |
| PV-SO-05 | App lock evaluation time | < 500ms | 2 seconds | Time from biometric/passcode prompt to app unlock on iPhone SE 3rd gen | Fails if > 2s on 3 consecutive attempts | Foundation Section 9.2 |

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
