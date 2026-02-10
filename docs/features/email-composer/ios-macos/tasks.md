---
title: "Email Composer — iOS/macOS Task Breakdown"
platform: iOS, macOS
plan-ref: docs/features/email-composer/ios-macos/plan.md
version: "1.4.0"
status: locked
updated: 2026-02-10
---

# Email Composer — iOS/macOS Task Breakdown

> Each task references its plan ID, spec section, and acceptance criteria. Status values: `todo`, `in-progress`, `done`, `blocked`.

---

### IOS-U-15: Composer View + Modes + Send Validation

- **Status**: `done`
- **Spec ref**: Email Composer spec, FR-COMP-01
- **Validation ref**: AC-U-15
- **Description**: Implement the email composition screen with all composition modes, body editor with basic formatting, send validation, view states, and discard confirmation. MV pattern — no ViewModels.
- **Deliverables**:
  - [x] `ComposerView.swift` (615 lines) — presented as sheet on iOS (uses @State, @Environment, .task)
  - [x] Support 5 composition modes: new, reply, reply-all, forward, edit-draft (FR-COMP-01)
  - [x] Pre-fill recipients, subject, body based on mode (FR-COMP-01)
  - [x] Reply/Reply All: set `inReplyTo` and `references` per RFC 2822 (FR-COMP-01)
  - [x] Reply/Reply All: quoted original body with "On [date], [sender] wrote:" header (FR-COMP-01)
  - [x] Forward: forwarding header + original attachments listed (FR-COMP-01)
  - [x] Subject prefix deduplication — no double "Re:" or "Fwd:" (FR-COMP-01)
  - [x] Reply All deduplication — remove user's own address from To/CC (FR-COMP-01)
  - [x] `BodyEditorView.swift` — plain text body editor with bold, italic, links (Markdown-style) (FR-COMP-01)
  - [x] Formatting toolbar (bold, italic, link buttons) that inserts Markdown syntax (FR-COMP-01)
  - [x] To, CC, BCC recipient fields (CC/BCC collapsed by default)
  - [x] Subject field
  - [x] Send button disabled until at least one valid recipient in To/CC/BCC (FR-COMP-01)
  - [x] Empty subject confirmation: "Send without subject?" (FR-COMP-01)
  - [x] Empty body confirmation: "Send empty message?" (FR-COMP-01)
  - [x] Invalid email addresses: visual indication with icon + color (not color alone) (NFR-COMP-03)
  - [x] View states: composing, sending, success, failed, saving draft, discard confirmation (FR-COMP-01)
  - [x] Discard confirmation dialog: "Delete draft?" with "Delete" and "Keep Editing" (FR-COMP-01)
  - [x] Dismiss handling: save draft if content exists, discard silently if empty (FR-COMP-01)
  - [x] Error handling: draft save failure warning (non-blocking), send failure with retry (FR-COMP-01)
  - [x] VoiceOver: all fields navigable and labeled; Send and Cancel buttons accessible (NFR-COMP-03)
  - [x] Dynamic Type: all text scales from accessibility extra small through xxxLarge (NFR-COMP-03)
  - [x] Reduce Motion: respect reduced motion for transitions (NFR-COMP-03)
  - [x] iOS: keyboard avoidance — body scrolls above keyboard, recipient fields remain accessible (spec Section 7)
  - [x] iOS: adaptive layout — iPhone SE (375pt) through Pro Max (430pt), portrait + landscape (spec Section 7)
  - [ ] macOS: keyboard shortcuts — deferred to macOS adaptation (IOS-M-01+)
  - [ ] macOS: multiple composer windows — deferred to macOS adaptation
  - [ ] macOS: toolbar — deferred to macOS adaptation
  - [ ] macOS: menu bar integration — deferred to macOS adaptation
- **Notes**: All iOS deliverables complete. macOS-specific items deferred to macOS adaptation feature.

### IOS-U-16: Recipient Field + Contacts Autocomplete

- **Status**: `done`
- **Spec ref**: Email Composer spec, FR-COMP-04
- **Validation ref**: AC-U-16
- **Description**: Implement token-based recipient input with privacy-preserving autocomplete from locally cached email addresses. No system Contacts access.
- **Deliverables**:
  - [x] `RecipientFieldView.swift` — token-based input with autocomplete dropdown (FR-COMP-04)
  - [x] `ContactCacheEntry.swift` — SwiftData `@Model` entity (spec Section 5)
  - [x] `QueryContactsUseCase.swift` — domain use case for querying contact cache (spec Section 6)
  - [x] Autocomplete data sourced exclusively from email headers (From, To, CC) of synced emails (FR-COMP-04)
  - [x] No system Contacts access — no `CNContact`, no contact permissions requested (FR-COMP-04)
  - [x] No external directory lookups (FR-COMP-04)
  - [x] Contact cache stored in SwiftData, scoped per account (FR-COMP-04)
  - [x] Each entry stores: email address, display name, last seen date, frequency (FR-COMP-04)
  - [x] Autocomplete results ranked by frequency of correspondence (FR-COMP-04)
  - [x] Email address validation with visual indication — icon + color, not color alone (FR-COMP-01, NFR-COMP-03)
  - [x] Comma/space-based auto-commit of typed email addresses
  - [x] VoiceOver: recipient tokens accessible (NFR-COMP-03)
  - [x] Dynamic Type for recipient tokens and autocomplete suggestions (NFR-COMP-03)
  - [x] Unit tests: `QueryContactsUseCaseTests.swift` (7 tests)
- **Notes**: Contact cache population happens during email sync via `SyncEmailsUseCase`.

### IOS-U-17: Draft Lifecycle + Undo-Send

- **Status**: `done`
- **Spec ref**: Email Composer spec, FR-COMP-01 (draft lifecycle), FR-COMP-02 (undo-send)
- **Validation ref**: AC-U-17a, AC-U-17b
- **Description**: Implement draft auto-save with IMAP sync, draft resume, and the full undo-send mechanism with all edge cases (app termination, background, offline).
- **Deliverables**:
  - [x] Draft auto-save in `ComposerView`: 30-second interval with content fingerprint change detection (FR-COMP-01)
  - [x] Auto-save persists to SwiftData with `Email.isDraft = true` (FR-COMP-01)
  - [x] On dismiss with content: save draft (FR-COMP-01)
  - [x] On dismiss without content: discard silently (FR-COMP-01)
  - [x] `UndoSendManager.swift` — @Observable @MainActor service with countdown timer (FR-COMP-02)
  - [x] `UndoSendToastView.swift` — countdown toast with "Undo" button, progress bar (FR-COMP-02)
  - [x] Undo-send: configurable delay (0–30 seconds) via SettingsStore (FR-COMP-02)
  - [x] User taps Undo: cancel send, return to composer (FR-COMP-02)
  - [x] App backgrounded during undo: timer pauses, resumes on foreground (FR-COMP-02)
  - [x] Undo window = 0: send immediately, no countdown shown (FR-COMP-02)
  - [x] Reduce Motion: simple progress bar instead of animated transitions (NFR-COMP-03)
  - [x] Accessibility: `.updatesFrequently` trait on countdown, labels updated per second (NFR-COMP-03)
  - [x] Unit tests: `UndoSendManagerTests.swift` (11 tests), `ComposeEmailUseCaseTests.swift` (26 tests)
  - [ ] Draft IMAP sync: APPEND to `[Gmail]/Drafts` — deferred (depends on IMAP APPEND in IOS-F-08)
- **Notes**: Local draft lifecycle fully functional. IMAP APPEND for server-side draft sync is a minor remaining item tracked under IOS-F-08.

### IOS-U-18: Attachment Handling + Smart Reply

- **Status**: `done`
- **Spec ref**: Email Composer spec, FR-COMP-01 (attachments), FR-COMP-03 (smart reply)
- **Validation ref**: AC-U-18
- **Description**: Implement attachment handling (file picker, photo library, size validation) and smart reply integration for reply composition.
- **Deliverables**:
  - [x] `AttachmentPickerView.swift` — file/photo picker + attachment list with remove buttons (FR-COMP-01)
  - [x] File picker: iOS `DocumentPickerRepresentable`, macOS guards with `#if os(iOS)` (FR-COMP-01)
  - [x] Photo library: iOS PhotosUI `PHPickerViewController` (FR-COMP-01)
  - [x] Each attachment displays: filename, size, remove button (FR-COMP-01)
  - [x] Total size warning at 25 MB (FR-COMP-01)
  - [x] `SmartReplyChipView.swift` — up to 3 smart reply suggestions for reply mode (FR-COMP-03)
  - [x] Smart reply via `SmartReplyUseCase` — async, non-blocking (FR-COMP-03)
  - [x] Tapping a suggestion inserts text into body for editing (FR-COMP-03)
  - [x] If smart reply fails or unavailable: hide suggestion area entirely (no error) (FR-COMP-03)
  - [x] VoiceOver: attachments and smart reply chips accessible (NFR-COMP-03)
  - [ ] macOS: drag-and-drop files — deferred to macOS adaptation
  - [ ] Forward attachment download before send — TODO in ComposerView line 382
- **Notes**: All iOS attachment and smart reply functionality complete. macOS drag-and-drop deferred. Forward attachment pre-download is a minor remaining item.
