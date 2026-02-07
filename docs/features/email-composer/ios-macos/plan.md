---
title: "Email Composer — iOS/macOS Implementation Plan"
platform: iOS, macOS
spec-ref: docs/features/email-composer/spec.md
version: "1.0.0"
status: draft
assignees:
  - Core Team
target-milestone: V1.0
---

# Email Composer — iOS/macOS Implementation Plan

---

## 1. Scope

This plan covers the email composition screen: composer UI, recipient autocomplete, draft auto-save, and undo-send mechanism.

---

## 2. Platform Context

Refer to Foundation plan Section 2.

---

## 3. Architecture Mapping

### Files

| File | Layer | Purpose |
|------|-------|---------|
| `ComposerView.swift` | iOS/Views/Composer | Composition UI (sheet on iOS) |
| `ComposerViewModel.swift` | iOS/Views/Composer | Compose logic, modes |
| `RecipientFieldView.swift` | iOS/Views/Composer | Token-based recipient input |
| `SmartReplyChipView.swift` | iOS/Views/Components | Smart reply suggestion chips |

---

## 4. Implementation Phases

| Task ID | Description | Dependencies |
|---------|-------------|-------------|
| IOS-U-08 | Composer view + view model | IOS-U-01 (Thread List), IOS-F-10 (Email Sync) |
| IOS-U-09 | Recipient field with auto-complete | IOS-U-08 |
| IOS-U-10 | Draft auto-save | IOS-U-08 |
| IOS-U-11 | Undo-send mechanism | IOS-U-08 |

---

## 5. Risks and Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Undo-send edge cases (app kill) | Medium | Medium | Write pendingSend to SwiftData before countdown; comprehensive state machine testing |
| Draft sync conflicts | Low | Medium | Server-side draft is overwritten on each auto-save; local is source of truth during editing |
