---
title: "Settings & Onboarding — iOS/macOS Implementation Plan"
platform: iOS, macOS
spec-ref: docs/features/settings-onboarding/spec.md
version: "1.0.0"
status: draft
assignees:
  - Core Team
target-milestone: V1.0
---

# Settings & Onboarding — iOS/macOS Implementation Plan

---

## 1. Scope

This plan covers the settings screen and onboarding flow implementation.

---

## 2. Platform Context

Refer to Foundation plan Section 2.

---

## 3. Architecture Mapping

### Files

| File | Layer | Purpose |
|------|-------|---------|
| `OnboardingView.swift` | iOS/Views/Onboarding | First-launch flow |
| `OnboardingViewModel.swift` | iOS/Views/Onboarding | Onboarding state machine |
| `SettingsView.swift` | iOS/Views/Settings | Settings grouped list |
| `SettingsViewModel.swift` | iOS/Views/Settings | Settings persistence |

---

## 4. Implementation Phases

| Task ID | Description | Dependencies |
|---------|-------------|-------------|
| IOS-U-13 | Onboarding flow | IOS-U-01 (Thread List), IOS-F-09 (Account Management) |
| IOS-U-14 | Settings screen | IOS-U-01 (Thread List) |

---

## 5. Risks and Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Onboarding complexity with AI download | Low | Low | Skip option ensures onboarding completes without download |
