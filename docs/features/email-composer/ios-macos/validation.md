---
title: "Email Composer — iOS/macOS Validation"
spec-ref: docs/features/email-composer/spec.md
plan-refs:
  - docs/features/email-composer/ios-macos/plan.md
  - docs/features/email-composer/ios-macos/tasks.md
version: "1.3.0"
status: locked
last-validated: null
---

# Email Composer — Validation: Acceptance Criteria & Test Plan

> The key words **MUST**, **MUST NOT**, **REQUIRED**, **SHALL**, **SHALL NOT**, **SHOULD**, **SHOULD NOT**, **RECOMMENDED**, **MAY**, and **OPTIONAL** in this document are to be interpreted as described in [RFC 2119](https://www.ietf.org/rfc/rfc2119.txt).

---

## 1. Traceability Matrix

| Req ID | Requirement Summary | Keyword | Test Case IDs | Platform | Status |
|--------|-------------------|---------|---------------|----------|--------|
| FR-COMP-01 | Composition (modes, body editor, attachments, validation, view states, draft lifecycle) | MUST | AC-U-15, AC-U-17a, AC-U-18 | Both | — |
| FR-COMP-02 | Undo-send mechanism (delay, edge cases, send state machine) | MUST | AC-U-17b | Both | — |
| FR-COMP-03 | Smart reply integration | SHOULD | AC-U-18 | Both | — |
| FR-COMP-04 | Contacts autocomplete privacy | MUST | AC-U-16 | Both | — |
| NFR-COMP-01 | Draft save latency (< 200ms) | MUST | PERF-01 | Both | — |
| NFR-COMP-02 | Autocomplete response time (< 100ms) | MUST | PERF-02 | Both | — |
| NFR-COMP-03 | Accessibility (WCAG 2.1 AA, VoiceOver, Dynamic Type) | MUST | AC-U-15, AC-U-16, AC-U-18 | Both | — |
| NFR-COMP-04 | Send time (< 3s from queued to sent) | MUST | PERF-03 | Both | — |
| G-01 | All composition modes with correct pre-filling | MUST | AC-U-15 | Both | — |
| G-02 | Client-side undo-send with edge cases | MUST | AC-U-17b | Both | — |
| G-03 | Auto-save drafts + IMAP sync | MUST | AC-U-17a | Both | — |
| G-04 | Privacy-preserving contacts autocomplete | MUST | AC-U-16 | Both | — |
| G-05 | Accessibility (VoiceOver, Dynamic Type, WCAG 2.1 AA) | MUST | AC-U-15, AC-U-16, AC-U-18 | Both | — |
| G-06 | Smart reply integration | SHOULD | AC-U-18 | Both | — |

---

## 2. Acceptance Criteria

---

**AC-U-15**: Email Composer View + Modes + Validation

- **Given**: The user opens the composer in each mode (new, reply, reply-all, forward)
- **When**: The composer is displayed
- **Then**: To, CC, BCC fields **MUST** be available (CC/BCC collapsed by default)
  AND for New mode: all fields **MUST** be empty
  AND for Reply mode: To **MUST** contain original sender, Subject **MUST** be "Re: " + original subject, body **MUST** contain quoted original with "On [date], [sender] wrote:" header
  AND for Reply All mode: To **MUST** contain original sender, CC **MUST** contain all To/CC recipients except self (deduplicated), Subject **MUST** be "Re: " + original subject
  AND for Forward mode: To **MUST** be empty, Subject **MUST** be "Fwd: " + original subject, body **MUST** contain forwarding header, original attachments **MUST** be listed
  AND Subject prefix **MUST NOT** be duplicated (no "Re: Re: ...")
  AND the body **MUST** be editable with basic formatting (bold, italic, links)
  AND the send button **MUST** be disabled until at least one valid recipient exists in To, CC, or BCC
  AND tapping Send with empty subject **SHOULD** display "Send without subject?" confirmation
  AND tapping Send with empty body **SHOULD** display "Send empty message?" confirmation
  AND invalid email addresses **MUST** be visually indicated with icon and color (not color alone)
  AND discard confirmation **MUST** appear when closing with content: "Delete draft?" with "Delete" and "Keep Editing"
  AND VoiceOver **MUST** navigate all fields with labels; Send and Cancel **MUST** be accessible
  AND all text **MUST** scale with Dynamic Type at all supported sizes
- **Priority**: Critical

---

**AC-U-16**: Recipient Auto-Complete + Privacy

- **Given**: The user has previously received emails from `alice@example.com` (high frequency) and `alex@example.com` (low frequency)
- **When**: The user types "al" in the To field
- **Then**: Both `alice@example.com` and `alex@example.com` **MUST** appear as suggestions
  AND `alice@example.com` **MUST** be ranked higher (by frequency)
  AND tapping a suggestion **MUST** add it as a token in the field
  AND the token **MUST** display name/email and provide a remove action
  AND autocomplete suggestions **MUST** appear within 300ms (hard limit)
  AND invalid email addresses **MUST** be visually indicated with icon + color
  AND no system Contacts data **MUST** be accessed (no `CNContact`, no contact permissions)
  AND no external directory lookups **MUST** be made (LDAP, CardDAV, Google People API)
  AND for multi-account users, suggestions **SHOULD** merge across accounts with deduplication
  AND VoiceOver **MUST** announce tokens with name/email and provide a remove custom action
  AND when an account is removed, all associated contact cache entries **MUST** be deleted
- **Priority**: Medium

---

**AC-U-17a**: Draft Auto-Save + Lifecycle

- **Given**: The user is composing an email with content (recipients, subject, or body)
- **When**: 30 seconds pass without sending
- **Then**: The draft **MUST** be saved locally to SwiftData with `isDraft = true`
  AND the draft **SHOULD** be synced to the server Drafts IMAP folder (APPEND)
  AND the previous server draft version **MUST** be deleted before the new APPEND
  AND draft save **MUST** complete within 500ms (hard limit)
  AND if the app is killed and reopened, the draft **MUST** be recoverable
  AND when the email is sent, the draft **MUST** be deleted from both local store and server Drafts folder
  AND tapping a draft in the Drafts folder **MUST** reopen the composer with all fields restored (To, CC, BCC, subject, body, attachments)
  AND if the draft is edited on another device, the server version **MUST** win on next sync (per FR-SYNC-05)
  AND on dismiss with content, a "Draft saved" toast **MUST** appear
  AND on dismiss with empty content, the composer **MUST** dismiss silently (no draft created)
  AND if draft auto-save fails, a subtle warning **SHOULD** appear but composition **MUST NOT** be blocked
- **Priority**: Medium

---

**AC-U-17b**: Undo Send

- **Given**: The user taps Send with a 5-second undo delay configured
- **When**: The send is initiated
- **Then**: The message **MUST** be persisted with `sendState = .queued` and `isDraft = false` in SwiftData **before** the countdown starts
  AND a countdown toast **MUST** appear with an "Undo" button
  AND the email **MUST NOT** be transmitted via SMTP during the delay
  AND tapping "Undo" **MUST** cancel the send and return to the composer with all content preserved
  AND after the delay expires, the email **MUST** transition to `queued` and follow the SMTP pipeline (FR-SYNC-07)
  AND if the app is terminated during the delay, the message **MUST** be saved as a draft and **MUST NOT** be auto-sent on next launch
  AND if the app enters background during the delay, the timer **MUST** pause and resume on foreground
  AND if the device loses network during the delay, the timer **MUST** continue; on expiry, the message enters the offline send queue
  AND if undo delay is set to 0 (disabled), the SMTP send **MUST** proceed immediately with no undo option
  AND Reduce Motion: countdown **SHOULD** use a simple progress bar instead of animated transitions
- **Priority**: Medium

---

**AC-U-18**: Attachment Handling + Smart Reply

- **Given**: The user is composing an email and wants to add attachments or use smart replies
- **When**: The user interacts with attachment or smart reply features
- **Then**: The user **MUST** be able to attach files via the system file picker
  AND the user **MUST** be able to attach images from the photo library (PHPickerViewController on iOS)
  AND the user **MUST** be able to attach images from the camera (on iOS, with NSCameraUsageDescription)
  AND each attachment **MUST** display filename, size, and a remove button
  AND a warning **MUST** appear when total attachment size exceeds 25 MB
  AND the client **SHOULD** prevent sending if total attachments exceed 25 MB
  AND for Forward mode, original attachments **MUST** be listed and optionally removable
  AND for Forward mode, undownloaded attachments **MUST** be downloaded before sending (with progress indicator)
  AND if forward attachment download fails, send **MUST** be prevented until resolved
  AND on macOS, files dragged onto the composer **MUST** be added as attachments
  AND for reply composition, up to 3 smart reply suggestions **SHOULD** appear via SmartReplyUseCase
  AND tapping a smart reply **MUST** insert the suggestion into the body for further editing
  AND if smart reply generation fails or is unavailable, the suggestion area **MUST** be hidden (no error)
  AND VoiceOver **MUST** announce each attachment with name, size, and provide a remove custom action
- **Priority**: High

---

## 3. Edge Cases

| # | Scenario | Expected Behavior |
|---|---------|-------------------|
| E-13 | Compose with no network | Draft saved locally; send queued in offline queue; user informed |
| E-14 | App killed during undo window | Message saved as draft, NOT auto-sent on relaunch |
| E-15 | App backgrounded during undo window | Timer pauses; resumes on foreground |
| E-16 | Undo window set to 0 (disabled) | SMTP send proceeds immediately; no undo option shown |
| E-17 | Network lost during SMTP transmission | Follow FR-SYNC-07 retry policy (30s, 2m, 8m); message enters offline queue if all retries fail |
| E-18 | SMTP server rejects recipient | Set `sendState = .failed` immediately; show error with server message; no retry |
| E-19 | Reply All where user is in To/CC | Remove user's own email address(es) from recipients |
| E-20 | Forward with undownloaded attachment | Download attachment before allowing send; show download progress; prevent send until complete or removed |
| E-21 | Attachment total exceeds 25 MB | Warning displayed; send prevented; show cumulative size |
| E-22 | Draft edited on another device | Server version wins on next sync (per FR-SYNC-05 conflict resolution) |
| E-23 | Empty composer dismissed (no recipients, no subject, no body) | No draft saved; silent dismiss |
| E-24 | Send with invalid email address in recipients | Send button disabled; invalid address highlighted with icon + color |
| E-25 | Subject already contains "Re:" and user replies | No prefix duplication — subject remains "Re: Original Subject" |
| E-26 | Forward attachment download fails | Error shown; send prevented until attachment downloaded or removed |
| E-27 | Draft auto-save fails (SwiftData error) | Subtle warning shown; composition not blocked |
| E-28 | SMTP send fails after undo window (after 3 retries) | Message set to `sendState = .failed`; error toast with retry option; composer content preserved |
| E-29 | Draft open in composer when server conflict detected | Warning: "Draft updated on another device. Reload?" with Reload and Keep Local options |
| E-30 | Forward with undownloaded attachment while offline | Forward queued; attachment download attempted on connectivity resume; send blocked until all attachments available |
| E-31 | User taps formatting toolbar (bold/italic/link) | Markdown syntax inserted at cursor position; user sees styled preview or raw syntax depending on editor mode |

---

## 4. Performance Validation

| Metric | Target | Hard Limit | Measurement Method | Failure Threshold |
|--------|--------|------------|--------------------|-------------------|
| Draft auto-save (NFR-COMP-01) | < 200ms | 500ms | Time from auto-save trigger to SwiftData persist confirmation on iPhone SE 3rd gen | Fails if > 500ms on 3 consecutive saves |
| Autocomplete response (NFR-COMP-02) | < 100ms | 300ms | Time from key event to visible suggestion list update on iPhone SE 3rd gen with 1,000+ cached contacts | Fails if > 300ms on 10 consecutive keystrokes |
| Send time (NFR-COMP-04) | < 3s | 5s | Time from `sendState = .queued` to `sendState = .sent` on iPhone SE 3rd gen with Wi-Fi | Fails if > 5s on 3 consecutive sends |

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
