---
title: "Settings & Onboarding — iOS/macOS Task Breakdown"
platform: iOS, macOS
plan-ref: docs/features/settings-onboarding/ios-macos/plan.md
version: "1.2.0"
status: locked
updated: 2026-02-08
---

# Settings & Onboarding — iOS/macOS Task Breakdown

> Each task references its plan ID, spec section, and acceptance criteria. Status values: `todo`, `in-progress`, `done`, `blocked`.

---

### IOS-U-13: Onboarding Flow (5 Steps)

- **Status**: `todo`
- **Spec ref**: Settings & Onboarding spec, FR-OB-01
- **Validation ref**: AC-U-13
- **Description**: Implement the first-launch onboarding experience with 5 steps: welcome with privacy messaging, Gmail account setup via OAuth with IMAP/SMTP validation, security recommendations, AI model download with informed consent, and feature tour with initial sync trigger. MV pattern — no ViewModels.
- **Deliverables**:
  - [ ] `OnboardingView.swift` — full-screen onboarding flow with step navigation (uses @State for step index, @Environment for services) (FR-OB-01)
  - [ ] iOS: presented via `.fullScreenCover`; macOS: dedicated `Window` scene (spec Section 7)
  - [ ] Step navigation: forward-only with progress indicator dots (max 5 steps) (FR-OB-01, G-04)
  - [ ] `OnboardingWelcomeStep.swift` — welcome screen with app logo, branding, and privacy value proposition: "Your emails stay on your device. No servers. No tracking. No compromise." (FR-OB-01 step 1)
  - [ ] Continue button to advance to Account Setup (FR-OB-01)
  - [ ] `OnboardingAccountStep.swift` — "Add your Gmail account" with Add Account button (FR-OB-01 step 2)
  - [ ] Add Account invokes OAuth 2.0 PKCE flow via `ASWebAuthenticationSession` (cross-ref Account Management FR-ACCT-01, FR-ACCT-03)
  - [ ] IMAP/SMTP connectivity **MUST** be validated before setup completes (FR-ACCT-01)
  - [ ] Display added account with email address and success indicator
  - [ ] At least one account **MUST** be added before "Next" is enabled (FR-OB-01)
  - [ ] OAuth cancelled by user: return to Account Setup, allow retry or different account (FR-OB-01 error table)
  - [ ] OAuth network failure: display "Network unavailable. Check your connection and try again." with Retry (FR-OB-01 error table)
  - [ ] OAuth token exchange failure: display "Authentication failed. Please try again." with Retry (FR-OB-01 error table)
  - [ ] IMAP/SMTP validation failure after OAuth: display "Couldn't connect to Gmail. Please check account permissions." with Retry (FR-OB-01 error table)
  - [ ] `OnboardingSecurityStep.swift` — "Protect your data" screen per Proposal Section 6.4 (FR-OB-01 step 3)
  - [ ] Display 5 recommendations: (1) device passcode + biometric, (2) enable app lock, (3) encrypted backups, (4) keep OS updated, (5) review connected accounts periodically (Proposal 6.4)
  - [ ] macOS: **SHOULD** also recommend FileVault enablement (Foundation Section 9.2)
  - [ ] Optional: toggle to enable app lock directly from this step (FR-OB-01)
  - [ ] `OnboardingAIModelStep.swift` — AI model download step with informed consent (FR-OB-01 step 4)
  - [ ] Display model source URL, file size, and license **before** download begins (Proposal Section 3.4.1)
  - [ ] Download button with progress indicator (FR-OB-01)
  - [ ] Skip option clearly labeled: "Skip — the app works without AI features." (FR-OB-01)
  - [ ] SHA-256 integrity verification after download (Proposal Section 3.4.1)
  - [ ] Download network failure: display "Download failed. You can download later in Settings." with Skip (FR-OB-01 error table)
  - [ ] SHA-256 checksum mismatch: delete corrupted file, display "Download verification failed. Please retry." with Retry and Skip (FR-OB-01 error table)
  - [ ] Download cancelled by user: return to download screen with Skip available (FR-OB-01 error table)
  - [ ] Expected storage disclosure: "Syncing your email may use [estimated range] of storage on this device" (Constitution TC-06)
  - [ ] `OnboardingReadyStep.swift` — feature tour: swipe gestures (archive/delete), AI categorization, smart reply, search (FR-OB-01 step 5)
  - [ ] "You're all set" confirmation with "Go to Inbox" button (FR-OB-01)
  - [ ] On completion: trigger initial sync for all added accounts (cross-ref Email Sync FR-SYNC-01) (FR-OB-01 post-onboarding)
  - [ ] On completion: navigate to Thread List (Inbox view) (FR-OB-01 post-onboarding)
  - [ ] On completion: persist `isOnboardingComplete = true` in UserDefaults — do not re-display on subsequent launches (FR-OB-01 post-onboarding)
  - [ ] Re-entry: if all accounts removed from Settings, re-trigger onboarding flow (FR-OB-01 post-onboarding)
  - [ ] VoiceOver: all onboarding screens fully navigable with descriptive labels (NFR-SET-02)
  - [ ] Dynamic Type: all text scales from accessibility extra small through accessibility 5 (xxxLarge) (NFR-SET-02)
  - [ ] Reduce Motion: use crossfade instead of slide animations when "Reduce Motion" is enabled (NFR-SET-02)
  - [ ] Color independence: status indicators use icon/shape in addition to color (NFR-SET-02)
  - [ ] iOS: adaptive layout — iPhone SE (375pt) through Pro Max (430pt), portrait + landscape (spec Section 7)
  - [ ] macOS: window-based onboarding, centered on screen with appropriate sizing (spec Section 7)
  - [ ] SwiftUI previews for all 5 steps, error states, and accessibility sizes
  - [ ] Unit tests for onboarding completion persistence
  - [ ] Unit tests for re-entry trigger when all accounts removed

### IOS-U-14: Settings Screen (All Sections)

- **Status**: `todo`
- **Spec ref**: Settings & Onboarding spec, FR-SET-01, FR-SET-02, FR-SET-03, FR-SET-04, FR-SET-05
- **Validation ref**: AC-U-14
- **Description**: Implement the full settings screen with all V1 sections: accounts, composition, appearance, AI features, notifications, security, data management, and about. Grouped list on iOS, Settings scene on macOS. MV pattern — no ViewModels.
- **Deliverables**:
  - [ ] `SettingsView.swift` — main settings grouped list with all sections (uses @State, @Environment, .task) (FR-SET-01)
  - [ ] iOS: `NavigationStack` with `.listStyle(.insetGrouped)`, accessible from Thread List toolbar (spec Section 7)
  - [ ] macOS: `Settings` scene pattern (`Settings { SettingsView() }`), opened via `⌘,` (spec Section 7)
  - [ ] macOS: Settings window is singleton — opening when already open brings existing window to front (spec Section 7)
  - [ ] `SettingsStore.swift` — `@Observable` service wrapping UserDefaults-backed preferences (plan Section 3)
  - [ ] SettingsStore properties: theme, undoSendDelay, categoryTabVisibility, appLockEnabled, notificationPreferences, attachmentCacheLimitMB, isOnboardingComplete, defaultSendingAccountId (spec Section 5)
  - [ ] Settings enums: `AppTheme` (system/light/dark), `UndoSendDelay` (0/5/10/15/30s), `SyncWindow` (7/14/30/60/90 days) (spec Section 5)
  - [ ] **Accounts section** — `AccountSettingsView.swift` (FR-SET-02)
  - [ ] List all configured accounts with email address and active/inactive status indicator (FR-SET-02)
  - [ ] Per-account: sync window picker (7/14/30/60/90 days, default 30) (FR-SET-02, FR-ACCT-02)
  - [ ] Per-account: editable display name field (FR-SET-02, FR-ACCT-02)
  - [ ] Sync window reduction: display confirmation "Reducing the sync window will remove local copies of older emails. Server emails are not affected." (FR-SET-01, Foundation Section 8.3)
  - [ ] Purge of local emails outside new window within 24 hours, **MUST NOT** delete from IMAP server (Foundation Section 8.3)
  - [ ] Inactive account: warning badge with "Re-authenticate" action → re-initiate OAuth flow (FR-SET-02, FR-ACCT-04)
  - [ ] Inactive accounts **MUST NOT** be silently hidden (FR-SET-02)
  - [ ] "Add Account" button → OAuth 2.0 flow via `ASWebAuthenticationSession` (FR-SET-02, FR-ACCT-01)
  - [ ] "Remove Account" with destructive confirmation: "Remove [email]? All local emails, drafts, and cached data for this account will be deleted." (FR-SET-02, FR-ACCT-05)
  - [ ] Cascade delete on remove: Folders, EmailFolder, Emails, Threads, Attachments, SearchIndex, Keychain items (FR-ACCT-05)
  - [ ] Removing last account re-triggers onboarding flow (FR-SET-02, FR-OB-01)
  - [ ] **Composition section** (FR-SET-01)
  - [ ] Default account picker listing all active accounts (FR-SET-01, FR-ACCT-02)
  - [ ] Default account picker hidden if only one account exists (FR-SET-01)
  - [ ] Undo send delay picker (0/5/10/15/30 seconds, default 5s) — change applies to next send (FR-SET-01, Email Composer FR-COMP-02)
  - [ ] **Appearance section** (FR-SET-01)
  - [ ] Theme picker (System/Light/Dark) — changes apply immediately via `preferredColorScheme` (FR-SET-01)
  - [ ] Category tab visibility toggles per category (Primary, Social, Promotions, Updates) — all on by default (FR-SET-01, Thread List FR-TL-02)
  - [ ] If AI features unavailable (model not downloaded): category toggles disabled with note "Download AI model to enable categories" (FR-SET-01)
  - [ ] **AI Features section** — `AIModelSettingsView.swift` (FR-SET-04)
  - [ ] Model status display: Not downloaded / Downloading (with progress) / Downloaded (FR-SET-04)
  - [ ] Model details: file size, source URL (FR-SET-04)
  - [ ] Before download: display source URL, file size, and license (Proposal Section 3.4.1)
  - [ ] Download: HTTPS, resumable (HTTP Range), SHA-256 verification (FR-SET-04, Proposal Section 3.4.1)
  - [ ] SHA-256 mismatch: delete corrupted file, display "Download verification failed. Please retry." (FR-SET-04)
  - [ ] Delete model confirmation: "Deleting the AI model will disable smart categories, smart reply, and thread summarization." (FR-SET-04)
  - [ ] On deletion: AI features degrade gracefully — hidden, not errored (Foundation Section 11)
  - [ ] **Notifications section** (FR-SET-01)
  - [ ] Per-account toggle to enable/disable new email notifications (FR-SET-01)
  - [ ] Notifications driven by IMAP IDLE + background fetch only — no push relay (Constitution P-02)
  - [ ] **Security section** (FR-SET-01)
  - [ ] App lock toggle — requires biometric (Face ID / Touch ID) or device passcode (FR-SET-01, Foundation Section 9.2)
  - [ ] `AppLockManager.swift` — `LAContext` wrapper for biometric/passcode evaluation (plan Section 3)
  - [ ] Uses `LAContext.evaluatePolicy(.deviceOwnerAuthentication)` — handles biometric + passcode fallback automatically (FR-SET-01)
  - [ ] App lock applies on cold launch and return from background (FR-SET-01)
  - [ ] **Data Management section** — `StorageSettingsView.swift` (FR-SET-03)
  - [ ] `StorageCalculator.swift` — async per-account and total storage usage calculation (plan Section 3)
  - [ ] Per-account storage breakdown: emails, downloaded attachments, search index (Foundation Section 8.2)
  - [ ] Total app storage usage display (Foundation Section 8.2)
  - [ ] Per-account storage > 2 GB: display warning (Foundation Section 8.2)
  - [ ] Total storage > 5 GB: display proactive warning (Foundation Section 8.2)
  - [ ] Per-account attachment cache limit picker (100 / 250 / 500 / 1000 MB, default 500 MB) — configurable per account, LRU eviction when exceeded (FR-SET-03, Foundation Section 8.1)
  - [ ] Storage loading state: loading indicator while calculating (FR-SET-01 view states)
  - [ ] Storage calculation failure: display "Unable to calculate storage" with retry option (FR-SET-01 error handling)
  - [ ] "Clear Cache": removes downloaded attachments and regenerable caches, preserves emails/accounts/AI models (FR-SET-03)
  - [ ] Clear cache: display amount of space to be freed before confirmation (FR-SET-03)
  - [ ] Clear cache confirmation: "This will remove cached attachments and data. Emails and accounts will not be affected." (FR-SET-01 view states)
  - [ ] Clear cache failure: display error and preserve existing data (FR-SET-01 error handling)
  - [ ] "Wipe All Data": destructive confirmation — "This will delete ALL local data including emails, accounts, and AI models. This cannot be undone. You will need to set up the app again." with "Delete Everything" (destructive) and "Cancel" (FR-SET-01, FR-SET-03, Foundation Section 9.3)
  - [ ] After wipe: re-trigger onboarding flow (FR-SET-03, Foundation Section 9.3)
  - [ ] **About section** — `AboutView.swift` (FR-SET-05)
  - [ ] App version and build number display (FR-SET-05)
  - [ ] Privacy Policy — in-app browser or link (Constitution LG-02, Foundation Section 10.3)
  - [ ] Open Source Licenses page (FR-SET-05)
  - [ ] AI Model Licenses page — model name, license type, source (Constitution LG-01, Foundation Section 10.1)
  - [ ] **Accessibility** (NFR-SET-02)
  - [ ] VoiceOver: all settings controls navigable and labeled (NFR-SET-02)
  - [ ] VoiceOver: toggle switches announce current state (on/off) (NFR-SET-02)
  - [ ] VoiceOver: pickers announce selected value (NFR-SET-02)
  - [ ] VoiceOver: account list items announce email address and active/inactive status (NFR-SET-02)
  - [ ] Dynamic Type: all text scales from accessibility extra small through accessibility 5 (xxxLarge) (NFR-SET-02)
  - [ ] Color independence: inactive badge, download states, storage warnings use icon/shape in addition to color (NFR-SET-02)
  - [ ] **Settings persistence**: all changes persist across app restarts (NFR-SET-01)
  - [ ] Settings save latency < 100ms target, < 500ms hard limit (NFR-SET-04)
  - [ ] SwiftUI previews for all settings sections, view states (default, downloading, storage loading, confirmations)
  - [ ] Unit tests for SettingsStore persistence (write, force-quit, read)
  - [ ] Unit tests for StorageCalculator with mock SwiftData store
  - [ ] Unit tests for AppLockManager with mock LAContext
