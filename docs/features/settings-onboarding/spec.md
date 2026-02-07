---
title: "Settings & Onboarding — Specification"
version: "1.0.0"
status: draft
created: 2025-02-07
updated: 2025-02-07
authors:
  - Core Team
reviewers: []
tags: [settings, onboarding, configuration, first-launch]
depends-on:
  - docs/constitution.md
  - docs/features/foundation/spec.md
---

# Specification: Settings & Onboarding

> The key words **MUST**, **MUST NOT**, **REQUIRED**, **SHALL**, **SHALL NOT**, **SHOULD**, **SHOULD NOT**, **RECOMMENDED**, **MAY**, and **OPTIONAL** in this document are to be interpreted as described in RFC 2119.

## 1. Summary

This specification defines the settings screen and first-launch onboarding flow. Settings covers all V1 configuration options. Onboarding guides the user through account setup and AI model download.

---

## 2. Goals and Non-Goals

### Goals

- Comprehensive settings screen for all V1 configuration
- First-launch onboarding with privacy value proposition
- AI model download integration in onboarding
- 5 or fewer onboarding screens

### Non-Goals

- In-app tutorial beyond onboarding
- Settings export/import
- Remote configuration

---

## 3. Functional Requirements

### FR-SET-01: Settings Screen

- The client **MUST** provide a settings screen with the following options:

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| Sync window | Picker (7/14/30/60/90 days) | 30 days | Per-account configurable |
| Default account | Picker | First added | Account used for new compositions |
| Undo send delay | Picker (0/5/10/15/30 seconds) | 5 seconds | Delay before email is actually sent |
| AI model management | Section | — | Download, delete, view model size |
| Category tabs visible | Toggle per category | All on | Show/hide categories in thread list |
| Notification preferences | Section | — | Per-account enable/disable |
| Theme | System/Light/Dark | System | Appearance preference |
| App lock | Toggle | Off | Require biometric/passcode to open |
| Data management | Section | — | Clear cache, export data, storage usage |
| About | Section | — | Version, licenses, privacy policy |

### FR-OB-01: Onboarding Flow

- The client **MUST** display a first-launch onboarding flow.
- Onboarding **MUST** include: welcome screen with privacy value proposition, account addition (at least one account required), AI model download (with option to skip), brief feature tour (swipe gestures, AI features).
- Onboarding **MUST** complete in 5 or fewer screens/steps.

---

## 4. Non-Functional Requirements

### NFR-SET-01: Settings Persistence

- **Metric**: Settings changes must persist across app restarts
- **Target**: Immediate persistence
- **Hard Limit**: —

---

## 5. Data Model

Refer to Foundation spec Section 5. Settings stored via SwiftData or UserDefaults (for simple preferences). Account entity stores per-account settings.

---

## 6. Architecture Overview

Refer to Foundation spec Section 6. Settings uses `ManageAccountsUseCase` for account-related settings. Other settings stored directly.

---

## 7. Platform-Specific Considerations

### iOS
- Settings presented as a grouped List view
- Onboarding presented as a full-screen flow

### macOS
- Settings uses the macOS Settings scene pattern
- Onboarding uses a window-based flow

---

## 8. Alternatives Considered

| Alternative | Pros | Cons | Rejected Because |
|-------------|------|------|-----------------|
| System Settings integration | Native feel on iOS | Limited customization | Need app-specific settings not supported by system |
| No onboarding | Faster to first use | Confusing first experience | Account setup is required; privacy messaging is important |

---

## 9. Open Questions

| # | Question | Owner | Target Date |
|---|----------|-------|-------------|
| — | — | — | — |

---

## 10. Revision History

| Version | Date | Author | Change Summary |
|---------|------|--------|---------------|
| 1.0.0 | 2025-02-07 | Core Team | Extracted from monolithic spec v1.2.0 sections 5.8 and 5.9. |
