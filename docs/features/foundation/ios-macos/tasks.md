---
title: "Foundation — iOS/macOS Task Breakdown"
platform: iOS, macOS
plan-ref: docs/features/foundation/ios-macos/plan.md
version: "1.2.0"
status: locked
updated: 2026-02-10
---

# Foundation — iOS/macOS Task Breakdown

> Each task references its plan ID, spec section, and acceptance criteria. Status values: `todo`, `in-progress`, `done`, `blocked`.

---

### IOS-F-01: Xcode Project Setup

- **Status**: `done`
- **Spec ref**: Foundation spec, Section 7 (Platform-Specific Considerations)
- **Validation ref**: AC-F-01
- **Commit**: `8287501`
- **Description**: Create Xcode project with workspace + SPM package architecture. Configure deployment targets (iOS 17, macOS 14) and Swift 6.1. Set up folder structure with Domain/Models, Domain/Protocols, Data/Persistence, Shared layers.
- **Deliverables**:
  - [x] Workspace + SPM package (`VaultMailPackage`) with iOS and macOS platform support
  - [x] Build settings configured for both platforms (iOS 17.0+, macOS 14.0+)
  - [x] Project compiles and launches empty app on both iOS Simulator and macOS
  - [x] `.gitignore` for Xcode and SPM build artifacts

### IOS-F-02: SwiftData Model Definitions

- **Status**: `done`
- **Spec ref**: Foundation spec, Section 5 (Data Model)
- **Validation ref**: AC-F-02
- **Commit**: `8287501`
- **Description**: Define all SwiftData `@Model` classes matching the spec ERD: Account, Folder, Email, Thread, EmailFolder, Attachment, SearchIndex. Define enums (AICategory, FolderType, SendState), repository protocols, and ModelContainerFactory.
- **Deliverables**:
  - [x] `Account.swift` — Account model with all spec fields + syncWindowDays
  - [x] `Folder.swift` — Folder model with folder type enum
  - [x] `Email.swift` — Email model with all spec fields, @Attribute(.externalStorage) for body fields
  - [x] `Thread.swift` — Thread model with accountId stored field
  - [x] `EmailFolder.swift` — Join entity for Email↔Folder many-to-many with imapUID
  - [x] `Attachment.swift` — Attachment model
  - [x] `SearchIndex.swift` — Search index with embedding blob
  - [x] `AICategory.swift`, `FolderType.swift`, `SendState.swift` — 3 enums per spec
  - [x] 4 repository protocols (Account, Email, AI, Search)
  - [x] `ModelContainerFactory.swift` — production + in-memory (testing) variants
  - [x] `Constants.swift` — spec-derived constants
  - [x] 27 unit tests across 4 suites (enums, relationships, CRUD, cascade deletes)
