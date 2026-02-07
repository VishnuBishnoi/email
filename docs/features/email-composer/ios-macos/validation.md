---
title: "Email Composer — iOS/macOS Validation"
spec-ref: docs/features/email-composer/spec.md
plan-refs:
  - docs/features/email-composer/ios-macos/plan.md
  - docs/features/email-composer/ios-macos/tasks.md
version: "1.0.0"
status: draft
last-validated: null
---

# Email Composer — Validation: Acceptance Criteria & Test Plan

> The key words **MUST**, **MUST NOT**, **REQUIRED**, **SHALL**, **SHALL NOT**, **SHOULD**, **SHOULD NOT**, **RECOMMENDED**, **MAY**, and **OPTIONAL** in this document are to be interpreted as described in [RFC 2119](https://www.ietf.org/rfc/rfc2119.txt).

---

## 1. Traceability Matrix

| Req ID | Requirement Summary | Keyword | Test Case IDs | Platform | Status |
|--------|-------------------|---------|---------------|----------|--------|
| FR-COMP-01 | Composition | MUST | AC-U-08 | Both | — |
| FR-COMP-02 | Undo-send | MUST | AC-U-11 | Both | — |
| FR-COMP-03 | Smart reply integration | SHOULD | AC-U-08 | Both | — |
| FR-COMP-04 | Contacts autocomplete privacy | MUST | AC-U-09 | Both | — |

---

## 2. Acceptance Criteria

---

**AC-U-08**: Email Composer

- **Given**: The user opens the composer (new email or reply)
- **When**: The composer is displayed
- **Then**: To, CC, BCC fields **MUST** be available
  AND the subject field **MUST** be pre-filled for reply (Re:) and forward (Fwd:)
  AND the body **MUST** be editable with basic formatting
  AND for replies, the original message **MUST** be quoted below
  AND the send button **MUST** be disabled until at least one recipient and a body are provided
  AND tapping send **MUST** queue the message for delivery
- **Priority**: Critical

---

**AC-U-09**: Recipient Auto-Complete

- **Given**: The user has previously received emails from `alice@example.com`
- **When**: The user types "ali" in the To field
- **Then**: `alice@example.com` **MUST** appear as a suggestion
  AND tapping the suggestion **MUST** add it as a token in the field
  AND invalid email addresses **MUST** be visually indicated
  AND no system Contacts data **MUST** be accessed
- **Priority**: Medium

---

**AC-U-10**: Draft Auto-Save

- **Given**: The user is composing an email with content
- **When**: 30 seconds pass without sending
- **Then**: The draft **MUST** be saved locally
  AND the draft **SHOULD** be synced to the Drafts IMAP folder
  AND if the app is killed and reopened, the draft **MUST** be recoverable
  AND when the email is sent, the draft **MUST** be deleted
- **Priority**: Medium

---

**AC-U-11**: Undo Send

- **Given**: The user taps send with a 5-second undo delay configured
- **When**: The send is initiated
- **Then**: A toast/snackbar **MUST** appear with an "Undo" button and a countdown
  AND the email **MUST NOT** be transmitted via SMTP during the delay
  AND tapping "Undo" **MUST** cancel the send and return to the composer
  AND after the delay expires, the email **MUST** be sent via SMTP
  AND if the app is terminated during the delay, the message **MUST** be saved as a draft
- **Priority**: Medium

---

## 3. Edge Cases

| # | Scenario | Expected Behavior |
|---|---------|-------------------|
| E-12 | Compose with no network | Draft saved locally; send queued; user informed |

---

## 4. Performance Validation

| Metric | Target | Hard Limit | Measurement Method | Failure Threshold |
|--------|--------|------------|--------------------|-------------------|
| Draft auto-save | < 200ms | 500ms | Time for local persist | Fails if > 500ms |
| Autocomplete response | < 100ms | 300ms | Keystroke to suggestion update | Fails if > 300ms |

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
