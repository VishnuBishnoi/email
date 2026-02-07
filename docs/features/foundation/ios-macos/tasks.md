---
title: "Foundation — iOS/macOS Task Breakdown"
platform: iOS, macOS
plan-ref: docs/features/foundation/ios-macos/plan.md
version: "1.0.0"
status: draft
updated: 2025-02-07
---

# Foundation — iOS/macOS Task Breakdown

> Each task references its plan ID, spec section, and acceptance criteria. Status values: `todo`, `in-progress`, `done`, `blocked`.

---

### IOS-F-01: Xcode Project Setup

- **Status**: `todo`
- **Spec ref**: Foundation spec, Section 7 (Platform-Specific Considerations)
- **Validation ref**: AC-F-01
- **Description**: Create Xcode project with shared framework, iOS target, and macOS target. Configure build settings, deployment targets (iOS 17, macOS 14), and Swift 5.9. Set up folder structure per plan section 3.1.
- **Deliverables**:
  - [ ] Xcode project with three targets (Shared, iOS, macOS)
  - [ ] Build settings configured for both platforms
  - [ ] Project compiles and runs empty app on both targets
  - [ ] `.gitignore` for Xcode artifacts

### IOS-F-02: SwiftData Model Definitions

- **Status**: `todo`
- **Spec ref**: Foundation spec, Section 5 (Data Model)
- **Validation ref**: AC-F-02
- **Description**: Define all SwiftData `@Model` classes matching the spec ERD: Account, Folder, Email, Thread, Attachment, SearchIndex.
- **Deliverables**:
  - [ ] `AccountEntity.swift` — Account model with all spec fields
  - [ ] `FolderEntity.swift` — Folder model with folder type enum
  - [ ] `EmailEntity.swift` — Email model with all spec fields
  - [ ] `ThreadEntity.swift` — Thread model with computed properties
  - [ ] `AttachmentEntity.swift` — Attachment model
  - [ ] SwiftData `ModelContainer` configuration
  - [ ] Unit tests for model relationships and constraints
