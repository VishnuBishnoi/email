---
title: "Polish — iOS/macOS Task Breakdown"
platform: iOS, macOS
plan-ref: docs/features/polish/ios-macos/plan.md
version: "1.1.0"
status: locked
updated: 2026-02-10
---

# Polish — iOS/macOS Task Breakdown

> Each task references its plan ID, spec section, and acceptance criteria. Status values: `todo`, `in-progress`, `done`, `blocked`.

---

### IOS-P-01: Accessibility Audit

- **Status**: `done`
- **Spec ref**: Constitution TC-05
- **Validation ref**: AC-P-01
- **Deliverables**:
  - [x] 181+ accessibility annotations across all presentation views (accessibilityLabel, accessibilityHint, accessibilityValue, accessibilityAddTraits)
  - [x] VoiceOver support on all screens — all interactive elements labeled
  - [x] Dynamic Type: all text scales correctly across views
  - [x] Color contrast: visual indicators use icon + color (not color alone) per NFR-COMP-03
  - [x] Reduce Motion: supported in UndoSendToastView (simple progress bar)
  - [x] `.updatesFrequently` trait on real-time countdown elements
- **Notes**: Comprehensive accessibility support built-in during feature development, not as a separate pass.

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

- **Status**: `done` (partial)
- **Spec ref**: Foundation spec, Section 11 (Performance Requirements)
- **Validation ref**: AC-P-03
- **Deliverables**:
  - [x] AI model unloading via `LlamaEngine.unload()` and `AIEngineProtocol.unload()`
  - [x] Pagination for large threads (50 msg threshold in EmailDetailView)
  - [x] Cursor-based pagination in ThreadListView
  - [ ] Memory pressure handling (unload model, reduce cache) — needs Instruments validation
  - [ ] Attachment cache eviction (500MB LRU per account)

### IOS-P-04 to IOS-P-07: Edge Cases and Features

- **Status**: `done`
- **Spec ref**: Various
- **Validation ref**: AC-P-04
- **Deliverables**:
  - [x] Offline mode: ThreadListView `.offline` state, NetworkMonitor tracks connectivity + cellular
  - [x] Error handling: error banners/toasts in ComposerView, EmailDetailView, ThreadListView; validation alerts
  - [x] App lock: `AppLockManager.swift` with biometric (Face ID/Touch ID) + passcode via `BiometricEvaluating` protocol
  - [x] Background app refresh: `BackgroundSyncScheduler.swift` with `BGAppRefreshTask` (15-min interval, 30-sec budget)
  - [x] Unit tests: `AppLockManagerTests.swift` (6 tests), `BackgroundSyncSchedulerTests.swift` (4 tests)

### IOS-P-08: Full Validation Suite

- **Status**: `todo`
- **Spec ref**: All
- **Validation ref**: All AC items
- **Deliverables**:
  - [ ] Run all acceptance criteria from all feature validation files
  - [ ] All critical and high priority ACs pass
  - [ ] Performance metrics within targets
  - [ ] Zero critical bugs remaining
