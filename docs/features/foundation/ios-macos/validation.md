---
title: "Foundation — iOS/macOS Validation"
spec-ref: docs/features/foundation/spec.md
plan-refs:
  - docs/features/foundation/ios-macos/plan.md
  - docs/features/foundation/ios-macos/tasks.md
version: "1.2.0"
status: locked
last-validated: 2026-02-11
---

# Foundation — Validation: Acceptance Criteria & Test Plan

> The key words **MUST**, **MUST NOT**, **REQUIRED**, **SHALL**, **SHALL NOT**, **SHOULD**, **SHOULD NOT**, **RECOMMENDED**, **MAY**, and **OPTIONAL** in this document are to be interpreted as described in [RFC 2119](https://www.ietf.org/rfc/rfc2119.txt).

---

## 1. Traceability Matrix

| Req ID | Requirement Summary | Keyword | Test Case IDs | Platform | Status |
|--------|-------------------|---------|---------------|----------|--------|
| FR-FOUND-01 | Clean architecture layering | MUST | AC-F-01 | Both | ✅ Pass |
| FR-FOUND-02 | Cross-platform code sharing | MUST | AC-F-01 | Both | ✅ Pass |
| FR-FOUND-03 | Cascade deletes | MUST | AC-F-02 | Both | ✅ Pass |

---

## 2. Acceptance Criteria

---

**AC-F-01**: Project Setup

- **Given**: A clean development environment with Xcode 15+
- **When**: The project is opened and built
- **Then**: The project **MUST** compile without errors on both iOS Simulator and macOS
  AND both targets **MUST** launch to an empty screen
  AND the project **MUST** contain shared, iOS, and macOS targets
- **Priority**: Critical

---

**AC-F-02**: SwiftData Models

- **Given**: SwiftData model classes are defined
- **When**: A `ModelContainer` is initialized with all model types
- **Then**: The container **MUST** initialize without errors
  AND all relationships (Account→Folder, Folder→Email, Email→Thread, Email→Attachment) **MUST** be navigable
  AND CRUD operations on each entity **MUST** persist across app restarts
  AND cascade deletes **MUST** function (deleting Account deletes all child data)
- **Priority**: Critical

---

## 3. Edge Cases

| # | Scenario | Expected Behavior |
|---|---------|-------------------|
| E-05 | Device runs low on storage | Warning shown; AI features degrade (model unloaded); sync reduces window |

---

## 4. Performance Validation

| Metric | Target | Hard Limit | Measurement Method | Failure Threshold |
|--------|--------|------------|--------------------|-------------------|
| Cold start | < 1.5s | 3s | Instruments Time Profiler on min-spec device | Fails if > 3s on 3 consecutive runs |
| Thread list scroll FPS | 60 fps | 30 fps | Instruments Core Animation on min-spec with 500+ threads | Fails if drops below 30fps for >1s |
| Email open (cached) | < 300ms | 500ms | Measured from tap to content visible | Fails if > 500ms on 3 consecutive runs |
| Memory idle | < 100MB | 200MB | Instruments Allocations, app in foreground, no activity | Fails if > 200MB |
| Initial sync (1K emails) | < 60s | 120s | Wall clock time on Wi-Fi | Fails if > 120s |
| Send email | < 3s | 5s | Time from send tap to SMTP completion (after undo delay) | Fails if > 5s |

---

## 5. Device Test Matrix

| Device | OS | Role |
|--------|-----|------|
| iPhone SE 3rd gen (A15, 4GB) | iOS 17 | Min-spec performance validation |
| iPhone 15 Pro (A17 Pro, 8GB) | iOS 17 | Reference device, AI performance |
| iPhone 16 | iOS 18 | Forward compatibility |
| MacBook Air M1 (8GB) | macOS 14 | Min-spec Mac validation |
| MacBook Pro M3 (18GB) | macOS 14 | Reference Mac, AI performance |
| Simulator (various) | iOS 17 | UI layout, accessibility, functional testing |

---

## 6. Sign-Off

| Reviewer | Role | Date | Status |
|----------|------|------|--------|
| Claude | Implementation | 2026-02-07 | ✅ AC-F-01, AC-F-02 pass (27/27 tests, both platforms build) |
| — | QA Lead | — | — |
| — | Engineering Lead | — | — |
