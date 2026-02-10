---
title: "Search — iOS/macOS Validation"
spec-ref: docs/features/search/spec.md
plan-refs:
  - docs/features/search/ios-macos/plan.md
  - docs/features/search/ios-macos/tasks.md
version: "2.0.0"
status: locked
last-validated: null
---

# Search — Validation: Acceptance Criteria & Test Plan

> The key words **MUST**, **MUST NOT**, **REQUIRED**, **SHALL**, **SHALL NOT**, **RECOMMENDED**, **MAY**, and **OPTIONAL** in this document are to be interpreted as described in [RFC 2119](https://www.ietf.org/rfc/rfc2119.txt).

---

## 1. Traceability Matrix

| Req ID | Requirement Summary | Keyword | Test Case IDs | Platform | Status |
|--------|-------------------|---------|---------------|----------|--------|
| FR-SEARCH-01 | Search interface | MUST | AC-S-01, AC-S-02 | iOS | — |
| FR-SEARCH-02 | Search filters | MUST | AC-S-03 | iOS | — |
| FR-SEARCH-03 | Search scopes | MUST | AC-S-04 | iOS | — |
| FR-SEARCH-04 | NL query parsing | MUST | AC-S-05 | iOS | — |
| FR-SEARCH-05 | Hybrid search architecture | MUST | AC-S-06 | iOS | — |
| FR-SEARCH-06 | FTS5 full-text index | MUST | AC-S-07 | iOS | — |
| FR-SEARCH-07 | Semantic embedding search | MUST | AC-S-06, AC-S-08 | iOS | — |
| FR-SEARCH-08 | Search index management | MUST | AC-S-09 | iOS | — |
| FR-SEARCH-09 | Recent searches | MUST | AC-S-10 | iOS | — |
| NFR-SEARCH-01 | Search performance | MUST | AC-S-11 | iOS | — |
| NFR-SEARCH-02 | Storage budget | SHOULD | AC-S-14 | iOS | — |
| NFR-SEARCH-03 | Accessibility | MUST | AC-S-12 | iOS | — |
| NFR-SEARCH-04 | Offline behavior | MUST | AC-S-13 | iOS | — |

---

## 2. Acceptance Criteria

---

**AC-S-01**: Search Interface — Basic Search

- **Given**: 1000 synced and indexed emails
- **When**: The user navigates to the Search tab and types "project update" in the search bar
- **Then**:
  - Search results **MUST** appear within 500ms
  - Results **MUST** display as a thread list matching `ThreadListView` format
  - Matching terms ("project", "update") **MUST** be highlighted in subject and snippet
  - Tapping a result **MUST** navigate to `EmailDetailView`
  - Result count **MUST** be displayed as thread count (e.g., "15 conversations")
- **Priority**: High

---

**AC-S-02**: Search Interface — Empty and Zero States

- **Given**: The user navigates to the Search tab
- **When**: The search bar is focused but empty
- **Then**: Recent searches **MUST** be displayed; suggested contacts **SHOULD** be shown
- **When**: The user searches for "xyznonexistent12345"
- **Then**: `ContentUnavailableView.search` **MUST** be shown with a suggestion to broaden the query
- **Priority**: High

---

**AC-S-03**: Search Filters

- **Given**: 1000 synced emails, 200 from "john@example.com", 50 with attachments
- **When**: The user taps the "Sender" filter chip and selects "john@example.com"
- **Then**: Results **MUST** show only emails from john@example.com
- **When**: The user additionally taps "Has Attachment" filter
- **Then**: Results **MUST** show only emails from john@example.com that have attachments (AND logic)
- **When**: The user types "budget" in the search bar with filters active
- **Then**: Results **MUST** match "budget" AND sender=john AND hasAttachment=true
- **When**: The user taps the "Date" filter chip and selects "Last 7 days"
- **Then**: Results **MUST** show only emails from the last 7 days
- **When**: The user taps the "Folder" filter chip and selects "Sent"
- **Then**: Results **MUST** show only emails in the Sent folder
- **When**: The user taps the "Category" filter chip and selects "Promotions"
- **Then**: Results **MUST** show only emails with `AICategory.promotions`
- **When**: The user taps the "Unread" filter chip
- **Then**: Results **MUST** show only unread emails
- **Priority**: High

---

**AC-S-04**: Search Scopes

- **Given**: 500 emails in Inbox, 300 in Sent, user is viewing Inbox
- **When**: The user searches for "meeting" with scope "Current Folder"
- **Then**: Results **MUST** only include emails from the Inbox folder
- **When**: The user switches scope to "All Mail"
- **Then**: Results **MUST** include emails from all folders
- **Given**: An email exists in both Inbox and Archive (multi-folder via EmailFolder join)
- **When**: The user searches with scope "Inbox"
- **Then**: The email **MUST** appear in results
- **When**: The user switches scope to "Drafts"
- **Then**: The email **MUST NOT** appear in results
- **Priority**: Medium

---

**AC-S-05**: Natural Language Query Parsing

- **Given**: 1000 synced and indexed emails
- **When**: The user types "from john last week with attachments"
- **Then**:
  - Sender filter **MUST** be set to "john"
  - Date range filter **MUST** be set to the previous 7 days
  - Has attachment filter **MUST** be set to true
  - Remaining text for FTS5/semantic search **MUST** be empty (all tokens consumed by filters)
  - Extracted filters **MUST** appear as active filter chips
- **When**: The user types "budget report from sarah"
- **Then**:
  - Sender filter **MUST** be set to "sarah"
  - "budget report" **MUST** be used as the free-text search query
- **When**: The user types "unread promotions from john"
- **Then**:
  - Sender filter **MUST** be set to "john"
  - Category filter **MUST** be set to "promotions"
  - Read status filter **MUST** be set to unread (isRead = false)
  - Remaining text for FTS5/semantic search **MUST** be empty (all tokens consumed by filters)
- **Priority**: Medium

---

**AC-S-06**: Semantic Search (Hybrid)

- **Given**: 1000 synced and indexed emails, including one about "quarterly budget review"
- **When**: The user searches for "financial planning meeting"
- **Then**:
  - Semantic search **SHOULD** return results that are conceptually related but not keyword-matched (e.g., "quarterly budget review" for query "financial planning meeting"). This is a **smoke test** — pass criteria: at least one non-keyword-matched result appears when embeddings are available.
  - If no semantic results appear, the system **MUST** still return keyword-only results without error
  - Results **MUST** be ranked by relevance (RRF fusion score)
  - When embeddings are available, results **SHOULD** include both keyword and semantic matches
  - For production quality validation, use Recall@20 ≥ 0.3 on a labeled test corpus (defined during implementation)
- **Priority**: High

---

**AC-S-07**: FTS5 Keyword Search

- **Given**: 1000 synced and indexed emails
- **When**: The user types "proj" (partial word)
- **Then**: Emails containing "project", "projection", "projects" **MUST** appear (prefix matching)
- **When**: The user types "deployment schedule"
- **Then**: Emails containing both "deployment" and "schedule" **MUST** rank highest (BM25)
- **Priority**: High

---

**AC-S-08**: Semantic Search — Fallback

- **Given**: Emails are indexed in FTS5 but embeddings are not yet generated (model not available)
- **When**: The user searches for "financial planning"
- **Then**:
  - FTS5 keyword results **MUST** still appear
  - No error or warning **MUST** be shown about missing semantic search
  - Search **MUST** complete within performance targets
- **Priority**: High

---

**AC-S-09**: Search Index Management

- **Given**: A new email is synced via `SyncEmailsUseCase`
- **When**: The sync completes
- **Then**:
  - The email **MUST** be inserted into the FTS5 index
  - An embedding **SHOULD** be generated and stored in `SearchIndex.embedding`
  - The email **MUST** be findable via search immediately after indexing
- **Given**: An email is deleted
- **When**: The deletion is processed
- **Then**: The email **MUST** be removed from both FTS5 and SearchIndex
- **Given**: An account with 100 indexed emails is deleted
- **When**: The account deletion completes
- **Then**: All 100 FTS5 entries for that account **MUST** be removed AND all 100 SearchIndex entries **MUST** be removed
- **Priority**: High

---

**AC-S-10**: Recent Searches

- **Given**: The user has performed 3 previous searches: "budget", "meeting notes", "project alpha"
- **When**: The user focuses the search bar (empty query)
- **Then**:
  - All 3 recent searches **MUST** appear in the zero-state
  - Most recent search **MUST** appear first
  - Tapping "meeting notes" **MUST** execute that search
- **When**: The user taps "Clear Recent Searches"
- **Then**: All recent searches **MUST** be cleared
- **When**: The user searches for "budget" again
- **Then**: "budget" **MUST** appear only once in recent searches (deduplicated, moved to top)
- **Priority**: Medium

---

**AC-S-11**: Performance

- **Given**: 10,000 synced and indexed emails
- **When**: The user submits a search query
- **Then**:
  - First results **MUST** appear in <500ms (hard limit)
  - First results **SHOULD** appear in <100ms (target)
  - Query parsing **MUST** complete in <5ms
- **Given**: 50,000 synced and indexed emails
- **When**: The user submits a search query
- **Then**:
  - First results **MUST** appear in <1000ms (hard limit)
  - First results **SHOULD** appear in <200ms (target)
- **Priority**: High

---

**AC-S-12**: Accessibility

- **Given**: VoiceOver is enabled
- **When**: The user navigates to the Search tab
- **Then**:
  - Search bar **MUST** announce "Search emails"
  - Filter chips **MUST** announce their filter description (e.g., "Filter: From John Smith")
  - Search results **MUST** be navigable via VoiceOver swipe
  - Empty state **MUST** announce "No results found for [query]"
  - Recent searches **MUST** announce "Recent search: [query]"
  - All text **MUST** scale with Dynamic Type
- **Priority**: High

---

**AC-S-13**: Offline Search

- **Given**: The device is in airplane mode
- **When**: The user performs a search
- **Then**:
  - Search **MUST** work normally (all data is local)
  - No network error **MUST** be shown
  - FTS5 keyword results **MUST** be returned
  - Semantic results **MUST** be returned if the embedding model is available and embeddings have been generated for the corpus
  - If embeddings are unavailable, FTS5 keyword results **MUST** still be returned with no error (consistent with AC-S-08)
- **Priority**: Medium

---

**AC-S-14**: Storage Budget Validation

- **Given**: 50,000 synced and indexed emails with FTS5 + embeddings
- **When**: The user views Settings > Storage
- **Then**:
  - FTS5 index size **SHOULD** be reported and **SHOULD** be approximately 50MB
  - Embedding storage **SHOULD** be reported and **SHOULD** be approximately 75MB
  - The FTS5 database **MUST** be stored in the app's Application Support directory
- **Priority**: Low

---

## 3. Edge Cases

| # | Scenario | Expected Behavior | Test Case |
|---|---------|-------------------|-----------|
| E-01 | No results | `ContentUnavailableView.search` displayed | AC-S-02 |
| E-02 | Very short query (1-2 chars) | FTS5 prefix match only, skip semantic | Unit test |
| E-03 | Query is only filters | SwiftData predicate filter only | AC-S-05 |
| E-04 | Embeddings not available | Keyword-only search, no error | AC-S-08 |
| E-05 | FTS5 database corrupt | Auto-rebuild FTS5 index, brief toast | Unit test |
| E-06 | Search while sync in progress | Stale results shown; refresh on next search | Manual test |
| E-07 | 100K+ emails | "Searching..." indicator if >500ms | Performance test |
| E-08 | Special characters in query | FTS5 unicode61 handles; escape operators | Unit test |
| E-09 | Multi-account search | Results include account indicator | AC-S-04 |
| E-10 | Empty search bar focused | Zero-state displayed | AC-S-02 |
| E-11 | Clear search | Return to previous state | Manual test |
| E-12 | Search during offline | Full functionality | AC-S-13 |

---

## 4. Performance Validation

| Metric | Target | Hard Limit | Corpus | Measurement Method | Failure Threshold |
|--------|--------|------------|--------|--------------------|--------------------|
| End-to-end search (10K) | <100ms | <500ms | 10K emails | Time from query submit to first result | Fails if >500ms |
| End-to-end search (50K) | <200ms | <1000ms | 50K emails | Time from query submit to first result | Fails if >1000ms |
| Query embedding | <10ms | <50ms | 1 query | CoreML inference time | Fails if >50ms |
| FTS5 query | <10ms | <50ms | 50K emails | SQLite query time | Fails if >50ms |
| Vector similarity | <20ms | <100ms | 50K vectors | Brute-force dot product time | Fails if >100ms |
| RRF fusion | <5ms | <20ms | 100 results | Merge + sort time | Fails if >20ms |
| Query parsing | <2ms | <5ms | Any query | Regex + NSDataDetector time | Fails if >5ms |

---

## 5. Device Test Matrix

Refer to Foundation validation Section 5 for shared device test matrix. Additional search-specific tests:

| Device | Corpus Size | Key Validation |
|--------|-------------|----------------|
| iPhone SE (3rd gen) | 10K emails | Performance on low-RAM device; memory pressure handling |
| iPhone 16 | 50K emails | Full performance validation |
| iPhone 16 Pro Max | 50K emails | ANE CoreML inference speed |
| iPad Air | 50K emails | Larger screen layout |

---

## 6. Test Coverage Requirements

| Component | Min Unit Tests | Key Scenarios |
|-----------|---------------|---------------|
| FTS5Manager | 10 | Insert, search, prefix, BM25, delete, highlight, corrupt recovery |
| VectorSearchEngine | 5 | Cosine similarity, top-K, empty corpus, normalized vectors |
| RRFMerger | 5 | Single source, dual source, weighted, dedup, empty |
| SearchQueryParser | 10 | Sender, date, attachment, category, read, mixed, empty, edge cases |
| SearchEmailsUseCase | 8 | Keyword-only, semantic-only, hybrid, filters, scope, fallback, empty |
| GenerateEmbeddingUseCase | 4 | Single, batch, fallback, model unavailable |
| SearchIndexManager | 8 | Index on sync, delete email, delete account, backfill accountId, reindex, concurrent access |

---

## 7. Sign-Off

| Reviewer | Role | Date | Status |
|----------|------|------|--------|
| — | Spec Author | — | — |
| — | QA Lead | — | — |
| — | Engineering Lead | — | — |
