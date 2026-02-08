---
title: "Email Composer — iOS/macOS Task Breakdown"
platform: iOS, macOS
plan-ref: docs/features/email-composer/ios-macos/plan.md
version: "1.3.0"
status: locked
updated: 2026-02-08
---

# Email Composer — iOS/macOS Task Breakdown

> Each task references its plan ID, spec section, and acceptance criteria. Status values: `todo`, `in-progress`, `done`, `blocked`.

---

### IOS-U-15: Composer View + Modes + Send Validation

- **Status**: `todo`
- **Spec ref**: Email Composer spec, FR-COMP-01
- **Validation ref**: AC-U-15
- **Description**: Implement the email composition screen with all four composition modes (new, reply, reply-all, forward), body editor with basic formatting, send validation, view states, and discard confirmation. MV pattern — no ViewModels.
- **Deliverables**:
  - [ ] `ComposerView.swift` — presented as sheet on iOS, window on macOS (uses @State, @Environment, .task)
  - [ ] Support 4 composition modes: new, reply, reply-all, forward (FR-COMP-01 modes table)
  - [ ] Pre-fill recipients, subject, body based on mode (FR-COMP-01)
  - [ ] Reply/Reply All: set `inReplyTo` and `references` per RFC 2822 (FR-COMP-01)
  - [ ] Reply/Reply All: quoted original body with "On [date], [sender] wrote:" header (FR-COMP-01)
  - [ ] Forward: forwarding header + original attachments listed (FR-COMP-01)
  - [ ] Subject prefix deduplication — no double "Re:" or "Fwd:" (FR-COMP-01)
  - [ ] Reply All deduplication — remove user's own address from To/CC (FR-COMP-01)
  - [ ] `BodyEditorView.swift` — plain text body editor with bold, italic, links (Markdown-style) (FR-COMP-01)
  - [ ] Formatting toolbar (bold, italic, link buttons) that inserts Markdown syntax — users don't type raw Markdown (FR-COMP-01)
  - [ ] To, CC, BCC recipient fields (CC/BCC collapsed by default)
  - [ ] Subject field
  - [ ] Send button disabled until at least one valid recipient in To/CC/BCC (FR-COMP-01)
  - [ ] Empty subject confirmation: "Send without subject?" (FR-COMP-01)
  - [ ] Empty body confirmation: "Send empty message?" (FR-COMP-01)
  - [ ] Invalid email addresses: visual indication with icon + color (not color alone) (NFR-COMP-03)
  - [ ] View states: composing, sending, success, failed, saving draft, discard confirmation (FR-COMP-01)
  - [ ] Discard confirmation dialog: "Delete draft?" with "Delete" and "Keep Editing" (FR-COMP-01)
  - [ ] Dismiss handling: save draft if content exists, discard silently if empty (FR-COMP-01)
  - [ ] Error handling: draft save failure warning (non-blocking), send failure with retry (FR-COMP-01)
  - [ ] VoiceOver: all fields navigable and labeled; Send and Cancel buttons accessible (NFR-COMP-03)
  - [ ] Dynamic Type: all text scales from accessibility extra small through xxxLarge (NFR-COMP-03)
  - [ ] Reduce Motion: respect reduced motion for transitions (NFR-COMP-03)
  - [ ] iOS: keyboard avoidance — body scrolls above keyboard, recipient fields remain accessible (spec Section 7)
  - [ ] iOS: adaptive layout — iPhone SE (375pt) through Pro Max (430pt), portrait + landscape (spec Section 7)
  - [ ] macOS: keyboard shortcuts — ⌘N, ⌘⇧D (send), ⌘W (close), ⌘S (save), Tab between fields (spec Section 7)
  - [ ] macOS: multiple composer windows with independent state (spec Section 7)
  - [ ] macOS: toolbar with Send, Attach, Formatting buttons (spec Section 7)
  - [ ] macOS: menu bar integration (spec Section 7)
  - [ ] SwiftUI previews for all view states and composition modes

### IOS-U-16: Recipient Field + Contacts Autocomplete

- **Status**: `todo`
- **Spec ref**: Email Composer spec, FR-COMP-04
- **Validation ref**: AC-U-16
- **Description**: Implement token-based recipient input with privacy-preserving autocomplete from locally cached email addresses. No system Contacts access.
- **Deliverables**:
  - [ ] `RecipientFieldView.swift` — token-based input with autocomplete dropdown (FR-COMP-04)
  - [ ] `ContactCacheEntry.swift` — feature-local SwiftData `@Model` entity (spec Section 5)
  - [ ] `QueryContactsUseCase` — domain use case for querying contact cache (spec Section 6)
  - [ ] Autocomplete data sourced exclusively from email headers (From, To, CC) of synced emails (FR-COMP-04)
  - [ ] No system Contacts access — no `CNContact`, `ABAddressBook`, no contact permissions requested (FR-COMP-04)
  - [ ] No external directory lookups (LDAP, CardDAV, Google People API) (FR-COMP-04)
  - [ ] Contact cache stored in SwiftData, scoped per account (FR-COMP-04)
  - [ ] Each entry stores: email address, display name, last seen date, frequency (FR-COMP-04)
  - [ ] Autocomplete results ranked by frequency of correspondence (FR-COMP-04)
  - [ ] Multi-account deduplication: merge suggestions across accounts, keep most recent displayName and highest frequency (FR-COMP-04)
  - [ ] Cascade delete contact cache entries when account is removed (FR-COMP-04)
  - [ ] Contact cache population during email sync: extract From/To/CC and upsert into ContactCacheEntry (FR-COMP-04)
  - [ ] Email address validation (reject malformed addresses with visual indication) (FR-COMP-01)
  - [ ] Autocomplete response time < 100ms target, < 300ms hard limit (NFR-COMP-02)
  - [ ] VoiceOver: recipient tokens announce name/email with remove custom action (NFR-COMP-03)
  - [ ] Dynamic Type for recipient tokens and autocomplete suggestions (NFR-COMP-03)
  - [ ] Unit tests for `QueryContactsUseCase` with 1,000+ cached entries
  - [ ] Unit tests for email address validation
  - [ ] SwiftUI previews for empty, typing, suggestions visible, tokens added

### IOS-U-17: Draft Lifecycle + Undo-Send

- **Status**: `todo`
- **Spec ref**: Email Composer spec, FR-COMP-01 (draft lifecycle), FR-COMP-02 (undo-send)
- **Validation ref**: AC-U-17a, AC-U-17b
- **Description**: Implement draft auto-save with IMAP sync, draft resume, and the full undo-send mechanism with all edge cases (app termination, background, offline).
- **Deliverables**:
  - [ ] `SaveDraftUseCase` — domain use case for persisting drafts to SwiftData + IMAP (spec Section 6)
  - [ ] `DeleteDraftUseCase` — domain use case for deleting drafts on send/discard (spec Section 6)
  - [ ] Auto-save timer: trigger on first meaningful edit, then every 30 seconds while content changes (FR-COMP-01)
  - [ ] Auto-save persists to SwiftData with `Email.isDraft = true` (FR-COMP-01)
  - [ ] Draft IMAP sync: APPEND to `[Gmail]/Drafts`; delete previous version (STORE \Deleted + EXPUNGE) before APPEND (FR-COMP-01)
  - [ ] Draft save latency < 200ms target, < 500ms hard limit (NFR-COMP-01)
  - [ ] On dismiss with content: save draft + display "Draft saved" toast (FR-COMP-01)
  - [ ] On dismiss without content: discard silently (FR-COMP-01)
  - [ ] On send success: delete draft from local store AND server Drafts folder (FR-COMP-01)
  - [ ] Draft resume: tapping a draft in Drafts folder reopens composer with all fields restored (FR-COMP-01)
  - [ ] Server conflict resolution: server version authoritative on next sync (per FR-SYNC-05) (FR-COMP-01)
  - [ ] `UndoSendToastView.swift` — countdown toast with "Undo" button (FR-COMP-02)
  - [ ] Undo-send: configurable delay (0, 5, 10, 15, 30 seconds; default 5s) (FR-COMP-02)
  - [ ] Persist `sendState = .queued` + `isDraft = false` to SwiftData **before** countdown begins (FR-COMP-02)
  - [ ] Send state machine: none (draft) → queued (undo window) → sending → sent/failed (per Foundation Section 5.5 mapping in FR-COMP-02)
  - [ ] User taps Undo: cancel send, return to composer (revert to `sendState = .none` + `isDraft = true`) (FR-COMP-02)
  - [ ] Timer expires (foreground): transition to queued → SMTP pipeline (FR-COMP-02)
  - [ ] App backgrounded during undo: timer pauses, resumes on foreground (FR-COMP-02)
  - [ ] App terminated during undo: save as draft, NOT auto-sent on relaunch (FR-COMP-02)
  - [ ] App killed by user during undo: same as OS termination (FR-COMP-02)
  - [ ] Network lost during undo: timer continues, on expiry enters offline queue (FR-COMP-02)
  - [ ] Undo window = 0: send immediately, no countdown shown (FR-COMP-02)
  - [ ] Post-undo-window: follow FR-SYNC-07 SMTP pipeline (3 retries: 30s, 2m, 8m) (FR-COMP-02)
  - [ ] SMTP server rejection: set failed immediately, no retry (FR-COMP-02)
  - [ ] After SMTP success: APPEND to Sent folder via IMAP (FR-COMP-02)
  - [ ] Offline on expiry: enter offline send queue (FIFO, 24h max age) (FR-COMP-02)
  - [ ] Send time < 3s target, < 5s hard limit from queued to sent (NFR-COMP-04)
  - [ ] Reduce Motion: simple progress bar instead of animated transitions for countdown (NFR-COMP-03)
  - [ ] Unit tests for send state machine (all transitions)
  - [ ] Unit tests for draft auto-save lifecycle
  - [ ] Unit tests for undo-send edge cases (termination, background, offline)

### IOS-U-18: Attachment Handling + Smart Reply

- **Status**: `todo`
- **Spec ref**: Email Composer spec, FR-COMP-01 (attachments), FR-COMP-03 (smart reply)
- **Validation ref**: AC-U-18
- **Description**: Implement attachment handling (file picker, photo library, camera, forward attachments, size validation) and smart reply integration for reply composition.
- **Deliverables**:
  - [ ] `AttachmentPickerView.swift` — file/photo picker + attachment list with remove buttons (FR-COMP-01)
  - [ ] File picker: iOS `UIDocumentPickerViewController`, macOS `NSOpenPanel` (FR-COMP-01)
  - [ ] Photo library: iOS `PHPickerViewController` (limited photos permission only) (FR-COMP-01)
  - [ ] Camera: iOS `UIImagePickerController` with `.camera` source (requires `NSCameraUsageDescription`) (FR-COMP-01)
  - [ ] Each attachment displays: filename, size, remove button (FR-COMP-01)
  - [ ] Total size warning at 25 MB; prevent send if over limit (FR-COMP-01)
  - [ ] Forward mode: list original attachments, allow removal, download undownloaded before send (FR-COMP-01)
  - [ ] Forward attachment download failure: show error, prevent send until resolved (FR-COMP-01)
  - [ ] macOS: drag-and-drop files onto composer adds as attachments (spec Section 7)
  - [ ] `SmartReplyChipView.swift` — up to 3 smart reply suggestions for reply mode (FR-COMP-03)
  - [ ] Smart reply via `SmartReplyUseCase` — async, non-blocking (FR-COMP-03)
  - [ ] Tapping a suggestion inserts text into body for editing (FR-COMP-03)
  - [ ] If smart reply fails or unavailable: hide suggestion area entirely (no error) (FR-COMP-03)
  - [ ] VoiceOver: attachments announce name, size with remove custom action (NFR-COMP-03)
  - [ ] VoiceOver: smart reply chips are labeled and selectable (NFR-COMP-03)
  - [ ] Unit tests for attachment size validation
  - [ ] Unit tests for forward attachment handling
  - [ ] SwiftUI previews for: no attachments, with attachments, size warning, smart reply chips
