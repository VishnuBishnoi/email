---
title: "Email Sync — iOS/macOS Validation"
spec-ref: docs/features/email-sync/spec.md
plan-refs:
  - docs/features/email-sync/ios-macos/plan.md
  - docs/features/email-sync/ios-macos/tasks.md
version: "1.1.0"
status: draft
last-validated: null
---

# Email Sync — Validation: Acceptance Criteria & Test Plan

> The key words **MUST**, **MUST NOT**, **REQUIRED**, **SHALL**, **SHALL NOT**, **SHOULD**, **SHOULD NOT**, **RECOMMENDED**, **MAY**, and **OPTIONAL** in this document are to be interpreted as described in [RFC 2119](https://www.ietf.org/rfc/rfc2119.txt).

---

## 1. Traceability Matrix

| Req ID | Requirement Summary | Keyword | Test Case IDs | Platform | Status |
|--------|-------------------|---------|---------------|----------|--------|
| FR-SYNC-01 | Full sync | MUST | AC-F-06 | Both | — |
| FR-SYNC-02 | Incremental sync | MUST | AC-F-06b | Both | — |
| FR-SYNC-03 | Real-time updates (IDLE) | MUST | AC-F-05 | Both | — |
| FR-SYNC-05 | Conflict resolution | MUST | AC-F-06 | Both | — |
| FR-SYNC-06 | Threading algorithm | MUST | AC-F-06 | Both | — |
| FR-SYNC-07 | Email sending (SMTP) | MUST | AC-F-07 | Both | — |
| FR-SYNC-08 | Attachment handling | MUST | AC-F-06 | Both | — |
| FR-SYNC-09 | Connection management | MUST | AC-F-05 | Both | — |
| FR-SYNC-10 | Flag synchronization | MUST | AC-F-06b, AC-F-08 | Both | — |
| G-01 | Full email CRUD | MUST | AC-F-05, AC-F-07, AC-F-08 | Both | — |

---

## 2. Acceptance Criteria

---

**AC-F-05**: IMAP Client

- **Given**: Valid OAuth credentials for a Gmail account
- **When**: The IMAP client connects to `imap.gmail.com:993`
- **Then**: The connection **MUST** use TLS
  AND XOAUTH2 authentication **MUST** succeed
  AND the client **MUST** list all Gmail folders (INBOX, Sent, Drafts, Trash, Spam, All Mail, Starred, plus labels)
  AND the client **MUST** fetch email UIDs within a date range
  AND the client **MUST** fetch complete email headers (From, To, CC, Subject, Date, Message-ID, References, In-Reply-To)
  AND the client **MUST** fetch email bodies (plain text and HTML parts)
  AND the client **MUST** support IMAP IDLE and receive notifications within 30 seconds of new email arrival
- **Priority**: Critical

---

**AC-F-06**: Sync Engine

- **Given**: A configured Gmail account
- **When**: Initial sync is triggered with a 30-day window
- **Then**: All emails within the window **MUST** be downloaded (headers + bodies)
  AND emails **MUST** be grouped into threads using References/In-Reply-To headers
  AND folder metadata (unread count, total count) **MUST** be accurate
  AND sync state (last UID, UIDVALIDITY) **MUST** be persisted

**AC-F-06b**: Incremental Sync

- **Given**: A previously synced account with sync state
- **When**: Incremental sync is triggered
- **Then**: Only emails newer than the last synced UID **MUST** be fetched
  AND deleted/moved emails on the server **MUST** be reflected locally
  AND flag changes (read, starred) **MUST** be synced bidirectionally
  AND the sync **MUST** complete within 5 seconds for 10 new emails on Wi-Fi
- **Priority**: Critical

---

**AC-F-07**: SMTP Client

- **Given**: Valid OAuth credentials and a composed email
- **When**: The email is sent
- **Then**: The SMTP connection **MUST** use TLS
  AND the email **MUST** be delivered to the recipient's inbox
  AND a copy **MUST** be appended to the Sent folder via IMAP
  AND if offline, the email **MUST** be queued and sent when connectivity resumes
- **Priority**: Critical

---

**AC-F-08**: Email Repository

- **Given**: An `EmailRepositoryImpl` with connected IMAP/SMTP and initialized SwiftData
- **When**: CRUD operations are performed
- **Then**: `fetchThreads` **MUST** return paginated threads sorted by latest date
  AND `markAsRead` **MUST** set the \Seen flag via IMAP and update local state
  AND `moveToFolder` **MUST** perform IMAP COPY + DELETE and update local state
  AND `deleteEmail` **MUST** move to Trash (or permanently delete if already in Trash)
  AND `starEmail` **MUST** set/remove the \Flagged flag via IMAP and update local state
- **Priority**: Critical

---

**AC-F-10**: Domain Use Cases

- **Given**: Use cases with mocked repositories
- **When**: Each use case is invoked
- **Then**: `SyncEmailsUseCase` **MUST** orchestrate sync and report progress/errors
  AND `FetchThreadsUseCase` **MUST** return filtered, sorted, paginated threads
  AND `SendEmailUseCase` **MUST** send or queue the email and handle errors
  AND `ManageAccountsUseCase` **MUST** delegate to account repository correctly
- **Priority**: Critical

---

## 3. Edge Cases

| # | Scenario | Expected Behavior |
|---|---------|-------------------|
| E-01 | Network drops during initial sync | Sync pauses; resumes from last checkpoint on reconnect; partial data is usable |
| E-03 | IMAP UIDVALIDITY changes | Full re-sync of affected folder; user notified of delay |
| E-08 | Concurrent sync on multiple accounts | Syncs run independently; no deadlocks; UI responsive |
| E-09 | Download 30MB attachment on cellular | Warning dialog shown; user can cancel or proceed (FR-SYNC-08) |

---

## 4. Performance Validation

| Metric | Target | Hard Limit | Measurement Method | Failure Threshold |
|--------|--------|------------|--------------------|-------------------|
| Initial sync (1K emails) | < 60s | 120s | Wall clock time on Wi-Fi | Fails if > 120s |
| Incremental sync (10 emails) | < 5s | — | Time from foreground to updated list | Fails if > 10s on 3 runs |
| Send email | < 3s | 5s | Time from send tap to SMTP completion | Fails if > 5s |

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
