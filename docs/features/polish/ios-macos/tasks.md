---
title: "Polish — iOS/macOS Task Breakdown"
platform: iOS, macOS
plan-ref: docs/features/polish/ios-macos/plan.md
version: "1.0.0"
status: draft
updated: 2025-02-07
---

# Polish — iOS/macOS Task Breakdown

> Each task references its plan ID, spec section, and acceptance criteria. Status values: `todo`, `in-progress`, `done`, `blocked`.

---

### IOS-P-01: Accessibility Audit

- **Status**: `todo`
- **Spec ref**: Constitution TC-05
- **Validation ref**: AC-P-01
- **Deliverables**:
  - [ ] VoiceOver audit on all screens (iOS + macOS)
  - [ ] Dynamic Type validation (all text scales correctly)
  - [ ] Color contrast audit (WCAG 2.1 AA)
  - [ ] Fix all accessibility issues found

### IOS-P-02: Performance Profiling

- **Status**: `todo`
- **Spec ref**: Foundation spec, Section 11 (Performance Requirements)
- **Validation ref**: AC-P-02
- **Deliverables**:
  - [ ] Instruments profiling: CPU, memory, energy
  - [ ] Cold start time measurement
  - [ ] Thread list scroll frame rate measurement
  - [ ] AI inference time measurement
  - [ ] Fix any metrics exceeding targets

### IOS-P-03: Memory Optimization

- **Status**: `todo`
- **Spec ref**: Foundation spec, Section 11 (Performance Requirements)
- **Validation ref**: AC-P-03
- **Deliverables**:
  - [ ] AI model unloading after inference completes
  - [ ] Memory pressure handling (unload model, reduce cache)
  - [ ] Lazy image loading in email detail
  - [ ] Pagination for large threads

### IOS-P-04 to IOS-P-07: Edge Cases and Features

- **Status**: `todo`
- **Spec ref**: Various
- **Validation ref**: AC-P-04
- **Deliverables**:
  - [ ] Offline mode: read cached emails, queue sends, surface sync errors on reconnect
  - [ ] Error handling audit: all error paths have user-facing messages
  - [ ] App lock (biometric/passcode) implementation
  - [ ] Background app refresh for periodic sync

### IOS-P-08: Full Validation Suite

- **Status**: `todo`
- **Spec ref**: All
- **Validation ref**: All AC items
- **Deliverables**:
  - [ ] Run all acceptance criteria from all feature validation files
  - [ ] All critical and high priority ACs pass
  - [ ] Performance metrics within targets
  - [ ] Zero critical bugs remaining
