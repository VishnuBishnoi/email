---
title: "Settings & Onboarding — iOS/macOS Implementation Plan"
platform: iOS, macOS
spec-ref: docs/features/settings-onboarding/spec.md
version: "1.2.0"
status: locked
assignees:
  - Core Team
target-milestone: V1.0
---

# Settings & Onboarding — iOS/macOS Implementation Plan

---

## 1. Scope

This plan covers the settings screen and first-launch onboarding flow for iOS and macOS. The settings screen includes account management surface (add/remove/configure accounts), composition preferences (default account, undo send delay), appearance (theme, category tabs), AI model management (download/delete with informed consent), notification preferences, security (app lock), storage and data management (breakdown, clear cache, wipe all data), and legal compliance (privacy policy, licenses). The onboarding flow includes 5 steps: welcome with privacy messaging, Gmail account setup via OAuth, security recommendations, AI model download, and feature tour with initial sync trigger.

---

## 2. Platform Context

Refer to Foundation plan Section 2. Key platform-specific considerations:
- iOS: `NavigationStack` with `.listStyle(.insetGrouped)` for Settings; `.fullScreenCover` for onboarding; `LAContext` for app lock.
- macOS: `Settings` scene pattern (`⌘,`); `Window` scene for onboarding; `LAContext` for Touch ID/device password.

---

## 3. Architecture Mapping

### Files

| File | Layer | Purpose |
|------|-------|---------|
| `OnboardingView.swift` | Presentation/Views | Full-screen onboarding flow with step navigation (uses @State for step index) |
| `OnboardingWelcomeStep.swift` | Presentation/Components | Welcome screen with privacy value proposition |
| `OnboardingAccountStep.swift` | Presentation/Components | Account addition step wrapping OAuth flow |
| `OnboardingSecurityStep.swift` | Presentation/Components | Security recommendations per Proposal 6.4 |
| `OnboardingAIModelStep.swift` | Presentation/Components | AI model download step with progress and skip |
| `OnboardingReadyStep.swift` | Presentation/Components | Feature tour and completion |
| `SettingsView.swift` | Presentation/Views | Main settings grouped list (uses @State, @Environment) |
| `AccountSettingsView.swift` | Presentation/Components | Per-account settings (sync window, display name) |
| `AIModelSettingsView.swift` | Presentation/Components | AI model management (download/delete/status) |
| `StorageSettingsView.swift` | Presentation/Components | Storage usage breakdown, clear cache, wipe data |
| `AboutView.swift` | Presentation/Components | Version, privacy policy, licenses |
| `SettingsStore.swift` | Domain/Services | @Observable service wrapping UserDefaults-backed preferences |
| `AppLockManager.swift` | Domain/Services | LAContext wrapper for biometric/passcode evaluation |
| `StorageCalculator.swift` | Domain/Services | Async per-account and total storage usage calculation |

**Note**: Per project architecture (CLAUDE.md), this feature uses the MV (Model-View) pattern with `@Observable` services and SwiftUI native state management. No ViewModels — view logic is in the SwiftUI views using `@State`, `@Environment`, and `.task` modifiers. Per Foundation FR-FOUND-01, views **MUST** call domain use cases only — never repositories directly.

### Settings Screen Layout (iOS)

```
+-------------------------------------------+
| [< Back]     Settings                      |
+-------------------------------------------+
| ACCOUNTS                                   |
|  user@gmail.com            [chevron]       |
|    Sync window: 30 days                    |
|    Display name: John                      |
|  ⚠ work@gmail.com (Inactive) [chevron]    |
|    Re-authenticate                         |
|  + Add Account                             |
+-------------------------------------------+
| COMPOSITION                                |
|  Default account    user@gmail.com  [>]    |
|  Undo send delay    5 seconds       [>]    |
+-------------------------------------------+
| APPEARANCE                                 |
|  Theme              System          [>]    |
|  Category tabs                      [>]    |
+-------------------------------------------+
| AI FEATURES                                |
|  AI Model           Downloaded      [>]    |
|    Model size: 1.2 GB                      |
|    [Delete Model]                          |
+-------------------------------------------+
| NOTIFICATIONS                              |
|  user@gmail.com     [toggle ON]            |
|  work@gmail.com     [toggle ON]            |
+-------------------------------------------+
| SECURITY                                   |
|  App Lock           [toggle OFF]           |
+-------------------------------------------+
| DATA MANAGEMENT                            |
|  Storage Usage                      [>]    |
|  Clear Cache                        [>]    |
|  Wipe All Data                      [>]    |
+-------------------------------------------+
| ABOUT                                      |
|  Version            1.0.0 (42)             |
|  Privacy Policy                     [>]    |
|  Open Source Licenses               [>]    |
|  AI Model Licenses                  [>]    |
+-------------------------------------------+
```

---

## 4. Implementation Phases

| Task ID | Description | Spec FRs | Dependencies |
|---------|-------------|----------|-------------|
| IOS-U-13 | Onboarding flow (5 steps) | FR-OB-01 | IOS-F-09 (Account Repository) |
| IOS-U-14 | Settings screen (all sections) | FR-SET-01..05 | IOS-U-01 (Thread List), IOS-F-09 |

---

## 5. Risks and Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| OAuth failure during onboarding blocks user | Medium | High | Clear error messaging with retry; OAuth is the only blocking step |
| Network loss during AI model download | Medium | Medium | Resumable downloads (HTTP Range); Skip option; download later in Settings |
| AI model SHA-256 checksum mismatch | Low | Medium | Delete corrupted file, prompt re-download; never load unverified models |
| App lock biometric enrollment failure | Low | Low | LAContext handles fallback to device passcode automatically |
| Storage calculation slow for large mailboxes | Medium | Low | Async calculation with loading indicator; cache results for session |
| Sync window reduction triggers unexpected data loss UX | Medium | High | Confirmation dialog explaining local purge; 24h gradual purge; server unaffected |
| AI model download exceeds available disk space | Low | Medium | Check available space before download; display model size; abort with clear error |
