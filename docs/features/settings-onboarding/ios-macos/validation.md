---
title: "Settings & Onboarding — iOS/macOS Validation"
spec-ref: docs/features/settings-onboarding/spec.md
plan-refs:
  - docs/features/settings-onboarding/ios-macos/plan.md
  - docs/features/settings-onboarding/ios-macos/tasks.md
version: "1.0.0"
status: draft
last-validated: null
---

# Settings & Onboarding — Validation: Acceptance Criteria & Test Plan

> The key words **MUST**, **MUST NOT**, **REQUIRED**, **SHALL**, **SHALL NOT**, **SHOULD**, **SHOULD NOT**, **RECOMMENDED**, **MAY**, and **OPTIONAL** in this document are to be interpreted as described in [RFC 2119](https://www.ietf.org/rfc/rfc2119.txt).

---

## 1. Traceability Matrix

| Req ID | Requirement Summary | Keyword | Test Case IDs | Platform | Status |
|--------|-------------------|---------|---------------|----------|--------|
| FR-SET-01 | Settings screen | MUST | AC-U-14 | Both | — |
| FR-OB-01 | Onboarding flow | MUST | AC-U-13 | Both | — |

---

## 2. Acceptance Criteria

---

**AC-U-13**: Onboarding

- **Given**: The app is launched for the first time (no accounts configured)
- **When**: The app starts
- **Then**: The onboarding flow **MUST** be displayed (not the thread list)
  AND the welcome screen **MUST** communicate the privacy value proposition
  AND the user **MUST** be able to add at least one Gmail account
  AND the AI model download step **MUST** be shown with a skip option
  AND after completion, the app **MUST** navigate to the thread list
  AND the onboarding **MUST NOT** exceed 5 screens
- **Priority**: High

---

**AC-U-14**: Settings

- **Given**: The user opens settings
- **When**: Settings are modified
- **Then**: Sync window changes **MUST** trigger a re-sync on next foreground
  AND theme changes **MUST** apply immediately
  AND undo send delay changes **MUST** apply to the next send
  AND AI model deletion **MUST** free storage and disable AI features gracefully
  AND "Clear cache" **MUST** remove cached data without deleting accounts
- **Priority**: Medium

---

## 3. Edge Cases

No feature-specific edge cases.

---

## 4. Performance Validation

No feature-specific performance metrics.

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
