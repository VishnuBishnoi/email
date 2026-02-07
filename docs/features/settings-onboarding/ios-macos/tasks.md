---
title: "Settings & Onboarding — iOS/macOS Task Breakdown"
platform: iOS, macOS
plan-ref: docs/features/settings-onboarding/ios-macos/plan.md
version: "1.0.0"
status: draft
updated: 2025-02-07
---

# Settings & Onboarding — iOS/macOS Task Breakdown

> Each task references its plan ID, spec section, and acceptance criteria. Status values: `todo`, `in-progress`, `done`, `blocked`.

---

### IOS-U-13: Onboarding Flow

- **Status**: `todo`
- **Spec ref**: Settings & Onboarding spec, FR-OB-01
- **Validation ref**: AC-U-13
- **Description**: First-launch onboarding experience.
- **Deliverables**:
  - [ ] Welcome screen with privacy value proposition
  - [ ] Account addition step (OAuth flow)
  - [ ] AI model download step (with skip option)
  - [ ] Feature tour (swipe gestures, AI features)
  - [ ] Completion and transition to thread list
  - [ ] Max 5 screens

### IOS-U-14: Settings Screen

- **Status**: `todo`
- **Spec ref**: Settings & Onboarding spec, FR-SET-01
- **Validation ref**: AC-U-14
- **Description**: Implement settings screen with all V1 options.
- **Deliverables**:
  - [ ] `SettingsView.swift` — grouped list of settings
  - [ ] Sync window picker (per account)
  - [ ] Default account picker
  - [ ] Undo send delay picker
  - [ ] AI model management section
  - [ ] Theme picker (System/Light/Dark)
  - [ ] App lock toggle
  - [ ] Data management (clear cache, storage usage)
  - [ ] About section (version, licenses)
