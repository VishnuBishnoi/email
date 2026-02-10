---
title: "Search — Specification"
version: "2.0.0"
status: locked
created: 2025-02-07
updated: 2026-02-10
authors:
  - Core Team
reviewers: []
tags: [search, semantic-search, keyword-search, fts5, embeddings, ui]
depends-on:
  - docs/constitution.md
  - docs/features/foundation/spec.md
  - docs/features/ai-features/spec.md
---

# Specification: Search

> The key words **MUST**, **MUST NOT**, **REQUIRED**, **SHALL**, **SHALL NOT**, **SHOULD**, **SHOULD NOT**, **RECOMMENDED**, **MAY**, and **OPTIONAL** in this document are to be interpreted as described in RFC 2119.

## 1. Summary

This specification defines a **hybrid local search system** combining SQLite FTS5 full-text search with AI-powered semantic embedding search. All search is performed on-device — no server-side IMAP SEARCH. The system uses **Reciprocal Rank Fusion (RRF)** to merge keyword and semantic results, supports **structured filter extraction** from natural language queries, and provides a polished SwiftUI search experience following Apple HIG patterns.

---

## 2. Goals and Non-Goals

### Goals

- Instant (<200ms) local search across all synced emails
- Hybrid keyword + semantic search with RRF fusion scoring
- Natural language query parsing ("emails from john last week with attachments")
- Structured filters: sender, date range, has-attachment, folder, AI category, read/unread
- Search-as-you-type with debounced queries (300ms)
- Recent searches persistence
- Zero-state intelligence (suggested searches based on frequent contacts and recent activity)
- Incremental index building during sync (no separate indexing pass)
- Graceful degradation: keyword search works even without AI embeddings

### Non-Goals

- Server-side IMAP SEARCH (all search is local-only)
- Saved searches / smart folders
- Search across non-synced emails
- Cross-account unified search ranking (results grouped by account)
- Regex or advanced query syntax (keep it simple)
- Real-time search index updates during compose (index on sync only)

---

## 3. Research-Informed Design Decisions

### 3.1 UX Patterns (from competitive analysis)

| Pattern | Source | Adoption |
|---------|--------|----------|
| Search-as-you-type with debounce | Gmail, Apple Mail, Superhuman | Yes — 300ms debounce |
| Filter chips below search bar | Gmail (iOS) | Yes — tappable filter chips |
| Search tokens (typed filters) | Apple Mail (iOS 17+) | Yes — SwiftUI `.searchable(tokens:)` |
| Zero-state suggestions | Outlook, Superhuman | Yes — recent searches + top contacts |
| Highlighted matching terms | Gmail, Apple Mail | Yes — bold matches in results |
| Empty state with suggestions | Apple HIG | Yes — `ContentUnavailableView.search` |
| Scoped search (current folder vs all) | Apple Mail | Yes — `.searchScopes()` |
| Instant result preview | Superhuman (Cmd+K) | No — too complex for v1 |

### 3.2 Technical Architecture Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Full-text search engine | SQLite FTS5 (separate DB) | SwiftData cannot create FTS5 virtual tables; FTS5 provides BM25 ranking, prefix queries |
| FTS5 access layer | Raw SQLite C API | No dependency; ~200 lines of wrapper code; consistent with llama.cpp C API usage |
| Vector storage | In-memory from SwiftData | sqlite-vec adds C dependency complexity; with <100K emails, loading Float arrays from SwiftData into memory is fast enough |
| Embedding model | all-MiniLM-L6-v2 (384-dim, CoreML) | 50MB model, ~5ms/embedding on ANE, excellent semantic quality for email domain |
| Hybrid scoring | Reciprocal Rank Fusion (RRF) | Simple, effective, no tuning needed. `score = 1/(k + rank)` with k=60 |
| Query parsing | Regex + NSDataDetector | Fast (<2ms), no LLM needed for structured filter extraction |
| Tokenizer | FTS5 unicode61 (no porter stemmer) | Email content includes names, addresses, technical terms where stemming causes false matches |

### 3.3 Why Separate SQLite DB for FTS5

SwiftData wraps Core Data which wraps SQLite, but it does NOT expose:
- Virtual table creation (`CREATE VIRTUAL TABLE ... USING fts5(...)`)
- Raw SQL queries needed for `MATCH` operator and `bm25()` ranking
- FTS5 auxiliary functions (`highlight()`, `snippet()`)

**Solution**: A dedicated `search.sqlite` database managed via raw SQLite C API (keeping dependencies minimal). This database contains only the FTS5 virtual table and is co-located with the SwiftData store.

---

## 4. Functional Requirements

### FR-SEARCH-01: Search Interface

- The client **MUST** provide a search bar accessible from the main thread list via a dedicated Search tab.
- The client **MUST** use SwiftUI `.searchable(text:tokens:isPresented:placement:)` for the search bar.
- The client **MUST** support search-as-you-type with a 300ms debounce.
- The client **MUST** display results as a thread list matching the existing `ThreadListView` format.
- The client **MUST** highlight matching terms in search results (subject and snippet).
- The client **MUST** support tapping a result to navigate to `EmailDetailView`.
- The client **SHOULD** show a zero-state when the search bar is empty but focused, displaying:
  - Recent searches (last 10, persisted in UserDefaults)
  - Suggested searches based on top 5 frequent contacts
- The client **MUST** show `ContentUnavailableView.search` when no results match.
- The client **MUST** display result count as thread count ("N conversations" text below search bar), since results are grouped by thread.

### FR-SEARCH-02: Search Filters

- The client **MUST** support these structured filters:
  - **Sender**: Filter by sender email or display name
  - **Date range**: Filter by start/end date
  - **Has attachment**: Boolean filter
  - **Folder**: Filter to specific folder (Inbox, Sent, etc.)
  - **AI Category**: Filter by category (Primary, Social, Promotions, Updates, Forums)
  - **Read/Unread**: Filter by read status
- Filters **MUST** be displayed as tappable chips below the search bar.
- Filters **MUST** be extractable from natural language queries (FR-SEARCH-04).
- Filters **MUST** combine with text search using AND logic.
- The client **SHOULD** use SwiftUI search tokens for active filters.

### FR-SEARCH-03: Search Scopes

- The client **MUST** support two search scopes via `.searchScopes()`:
  - **All Mail**: Search across all folders and accounts
  - **Current Folder**: Search within the currently selected folder
- Default scope **MUST** be "All Mail".
- Scope selection **MUST** persist within the search session.
- "Current Folder" filtering **MUST** be applied outside FTS5 as a SwiftData predicate joining FTS5 result email IDs against `EmailFolder.folder.id`. This avoids storing mutable folder associations in the FTS5 index and correctly handles multi-folder emails (Gmail labels).

### FR-SEARCH-04: Natural Language Query Parsing

- The client **MUST** parse structured filters from natural language input before executing search.
- Parsing **MUST** extract:
  - **Sender**: "from john", "from john@example.com" → sender filter
  - **Date**: "last week", "yesterday", "in January", "before March" → date range filter (via `NSDataDetector` + hardcoded relative patterns)
  - **Attachment**: "with attachments", "has attachment", "with files" → hasAttachment filter
  - **Category**: "promotions", "social emails" → category filter
  - **Read status**: "unread", "read" → isRead filter
- After filter extraction, the remaining text **MUST** be used as the free-text search query.
- Parsing **MUST** complete in <5ms (regex + NSDataDetector, no LLM).

### FR-SEARCH-05: Hybrid Search Architecture

```
User Query
    |
    v
[Query Parser] -- extracts --> Structured Filters (sender, date, etc.)
    |                               |
    | remaining text                |
    v                               v
+---+---+                  [SwiftData Predicate]
|       |                         |
v       v                         v
[FTS5]  [Embedding]         Filter Results
BM25    Cosine Sim               |
ranked  ranked                   |
|       |                        |
v       v                        |
[Reciprocal Rank Fusion] <-------+
        |
        v
  Merged + Filtered Results
        |
        v
  [Display in SearchView]
```

- The client **MUST** execute keyword search via FTS5 and semantic search via embedding similarity in parallel.
- The client **MUST** merge results using Reciprocal Rank Fusion: `score(d) = sum(1 / (k + rank_i(d)))` with k=60.
- Semantic results **SHOULD** receive a 1.5x weight boost: `semantic_score = 1.5 / (k + semantic_rank)`.
- Keyword-only results (no embedding match) **MUST** still appear in results.
- If embeddings are unavailable (model not downloaded), the client **MUST** fall back to FTS5-only search.

### FR-SEARCH-06: FTS5 Full-Text Index

- The client **MUST** maintain an FTS5 virtual table in a separate SQLite database (`search.sqlite`).
- The FTS5 table schema **MUST** be:
  ```sql
  CREATE VIRTUAL TABLE email_fts USING fts5(
      email_id UNINDEXED,
      account_id UNINDEXED,
      subject,
      body,
      sender_name,
      sender_email,
      tokenize='unicode61 remove_diacritics 2'
  );
  ```
- Porter stemmer is omitted intentionally — email content includes names, addresses, and technical terms where stemming causes false matches. Unicode61 with diacritic removal provides sufficient normalization.
- FTS5 queries **MUST** use prefix matching for search-as-you-type: `query*`.
- Results **MUST** be ranked by BM25 via `ORDER BY bm25(email_fts)`.
- The FTS5 `highlight()` function **SHOULD** be used for match highlighting in results.

### FR-SEARCH-07: Semantic Embedding Search

- The client **MUST** generate a 384-dimensional embedding for each query using the same model used for indexing (all-MiniLM-L6-v2 via CoreML).
- The client **MUST** compute cosine similarity between the query embedding and all indexed email embeddings.
- Cosine similarity **MUST** be computed as dot product on pre-L2-normalized vectors: `sim = dot(q, d)`.
- The client **MUST** return the top-50 results by similarity score.
- Embeddings **MUST** be pre-normalized at index time to avoid per-query normalization.
- If the embedding model is not available, semantic search **MUST** be silently skipped (keyword-only fallback).

### FR-SEARCH-08: Search Index Management

- The client **MUST** build the search index incrementally during email sync (not as a separate pass).
- `SearchIndexManager` is the **single owner** of all search index mutations (FTS5 inserts/deletes and SearchIndex entity upserts). `AIProcessingQueue.generateEmbeddings()` **MUST** delegate to `SearchIndexManager` rather than directly manipulating SearchIndex entries, to prevent duplicate writes and race conditions.
- When `SyncEmailsUseCase` inserts new emails, it **MUST** also:
  1. Insert into FTS5 table (subject + body + sender)
  2. Generate embedding via `GenerateEmbeddingUseCase` and store in `SearchIndex.embedding`
- When an email is deleted, `SearchIndexManager` **MUST** delete the corresponding FTS5 row by email_id and the SearchIndex SwiftData entry by emailId.
- When an account is deleted, `SearchIndexManager` **MUST** bulk-delete all FTS5 rows where account_id matches and all SearchIndex entries where accountId matches.
- When sync reconciliation detects server-missing emails, `SearchIndexManager` **MUST** clean up orphaned FTS5 and SearchIndex entries.
- Folder deletion does NOT require FTS5/SearchIndex cleanup (emails survive folder removal; only EmailFolder associations are affected).
- The client **SHOULD** support a one-time full reindex for existing emails (Settings > "Rebuild Search Index").
- The client **SHOULD** auto-detect unindexed emails on first Search tab open and index progressively in background.
- Index build **MUST NOT** block the UI — all indexing runs on background actors.

### FR-SEARCH-09: Recent Searches

- The client **MUST** persist the last 10 search queries in UserDefaults.
- Recent searches **MUST** be displayed in the zero-state (search bar focused, no query entered).
- Each recent search **MUST** be tappable to re-execute the search.
- The client **MUST** provide a "Clear Recent Searches" action.
- Duplicate queries **MUST** be deduplicated (most recent wins).

---

## 5. Non-Functional Requirements

### NFR-SEARCH-01: Search Performance

| Metric | Target | Hard Limit | Corpus Size |
|--------|--------|------------|-------------|
| End-to-end search (first results) | <100ms | <500ms | 10K emails |
| End-to-end search (first results) | <200ms | <1000ms | 50K emails |
| Query embedding generation | <10ms | <50ms | Single query |
| FTS5 query execution | <10ms | <50ms | 50K emails |
| Vector similarity (brute force) | <20ms | <100ms | 50K embeddings |
| RRF fusion + dedup | <5ms | <20ms | 100 results |
| Query parsing | <2ms | <5ms | Any query |
| Search-as-you-type debounce | 300ms | — | — |

### NFR-SEARCH-02: Storage Budget

| Component | Size (50K emails) | Size (100K emails) |
|-----------|-------------------|---------------------|
| FTS5 index | ~50MB | ~100MB |
| Embedding vectors (384-dim Float32) | ~75MB (in SwiftData) | ~150MB |
| CoreML model (all-MiniLM-L6-v2) | 50MB (bundled) | 50MB |
| **Total search overhead** | **~175MB** | **~300MB** |

- The FTS5 database **MUST** be stored in the app's Application Support directory.
- The client **SHOULD** display search index size in Settings > Storage.

### NFR-SEARCH-03: Accessibility

- Search bar **MUST** have `accessibilityLabel("Search emails")`.
- Filter chips **MUST** have accessibility labels describing the filter (e.g., "Filter: From John Smith").
- Search results **MUST** be navigable via VoiceOver.
- Empty state **MUST** announce "No results found for [query]" to VoiceOver.
- Recent searches **MUST** be accessible with labels like "Recent search: [query]".
- Dynamic Type **MUST** be supported across all search UI elements.

### NFR-SEARCH-04: Offline Behavior

- Search **MUST** work fully offline (all data is local).
- If embeddings are not yet generated for some emails, those emails **MUST** still be findable via FTS5 keyword search.

---

## 6. Data Model

### 6.1 Existing: SearchIndex (SwiftData) — Changes Needed

```swift
@Model
public final class SearchIndex {
    public var emailId: String      // FK to Email
    public var accountId: String    // NEW: for account-scoped queries
    public var content: String      // subject + body + sender (kept for backward compat)
    public var embedding: Data?     // 384-dim Float32 vector, pre-L2-normalized (1536 bytes)
}
```

> **Migration note**: Adding `accountId` is a lightweight SwiftData schema migration (additive property with default value `""`). Existing SearchIndex entries will have `accountId = ""` after migration and **MUST** be backfilled on first app launch after upgrade by joining SearchIndex.emailId to Email.accountId in batch. Guard with UserDefaults flag to run once.

### 6.2 New: FTS5 Table (separate search.sqlite)

```sql
CREATE VIRTUAL TABLE email_fts USING fts5(
    email_id UNINDEXED,
    account_id UNINDEXED,
    subject,
    body,
    sender_name,
    sender_email,
    tokenize='unicode61 remove_diacritics 2'
);
```

### 6.3 Search Query Model

```swift
struct SearchQuery: Sendable {
    var text: String                    // Free-text after filter extraction
    var filters: SearchFilters
    var scope: SearchScope
}

struct SearchFilters: Sendable {
    var sender: String?
    var dateRange: DateRange?
    var hasAttachment: Bool?
    var folder: String?
    var category: AICategory?
    var isRead: Bool?
}

enum SearchScope: Sendable {
    case allMail
    case currentFolder(folderId: String)
}
```

### 6.4 Search Result Model

```swift
struct SearchResult: Identifiable, Sendable {
    let id: String                      // Thread ID (used as Identifiable id)
    let threadId: String
    let emailId: String
    let subject: String
    let senderName: String
    let senderEmail: String
    let date: Date
    let snippet: String                 // Body snippet with match context
    let highlightRanges: [Range<String.Index>]  // For keyword highlighting
    let hasAttachment: Bool
    let score: Double                   // RRF fusion score
    let matchSource: MatchSource
    let accountId: String
}

enum MatchSource: Sendable {
    case keyword
    case semantic
    case both
}
```

> **Concurrency note**: `SearchResult` is a lightweight value type carrying only display data. It does **NOT** embed `@Model` objects (`Thread`, `Email`) which are `ModelContext`-bound and not safely `Sendable` across concurrency boundaries. The view layer fetches full `@Model` objects on `@MainActor` via the `threadId`/`emailId` when navigation is needed.

---

## 7. Architecture Overview

### 7.1 Component Diagram

```
Presentation Layer
├── SearchView.swift              # Search bar, filters, results (MV pattern)
├── SearchFilterChipsView.swift   # Horizontal filter chip bar
├── SearchResultRowView.swift     # Individual result with highlights
└── RecentSearchesView.swift      # Zero-state recent searches

Domain Layer
├── SearchEmailsUseCase.swift     # Orchestrates hybrid search
├── GenerateEmbeddingUseCase.swift # Query embedding via CoreML
└── SearchQueryParser.swift       # NL query → SearchQuery

Data Layer
├── SearchRepositoryImpl.swift    # Implements SearchRepositoryProtocol
├── FTS5Manager.swift             # SQLite FTS5 database wrapper (raw C API)
├── VectorSearchEngine.swift      # In-memory cosine similarity
└── RRFMerger.swift               # Reciprocal Rank Fusion
```

### 7.2 Data Flow

1. User types in search bar → 300ms debounce
2. `SearchQueryParser` extracts filters + remaining text
3. `SearchEmailsUseCase` dispatches in parallel:
   - a) FTS5 keyword search via `FTS5Manager` (returns BM25-ranked email IDs)
   - b) Semantic search: generate query embedding → `VectorSearchEngine` cosine similarity (returns similarity-ranked email IDs)
   - c) SwiftData predicate query for structured filters (returns filtered email IDs)
4. `RRFMerger` fuses keyword + semantic rankings, intersected with filter results
5. Results mapped to `SearchResult` with thread grouping + highlighting
6. `SearchView` displays results

### 7.3 MV Pattern (No ViewModels)

Per project architecture, `SearchView` uses `@State` and `@Environment`:

```swift
struct SearchView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var searchText = ""
    @State private var searchTokens: [SearchToken] = []
    @State private var results: [SearchResult] = []
    @State private var viewState: ViewState = .idle
    @State private var recentSearches: [String] = []
    @State private var scope: SearchScope = .allMail

    @Environment(SearchEmailsUseCase.self) private var searchUseCase

    enum ViewState {
        case idle, searching, results, empty
    }
}
```

---

## 8. Platform-Specific Considerations

### iOS
- Search bar via `.searchable()` modifier on NavigationStack
- Filter chips as horizontal `ScrollView` with `Button` elements
- Results in `List` matching `ThreadListView` style
- Keyboard avoidance handled by SwiftUI
- `.searchScopes()` for All Mail vs Current Folder toggle

### macOS (deferred)
- Search field in toolbar (Cmd+F focuses)
- Results in list pane (same as thread list)
- Keyboard shortcuts: Cmd+F (focus search), Escape (clear/dismiss)

---

## 9. Edge Cases

| # | Scenario | Expected Behavior |
|---|---------|-------------------|
| E-01 | No results | `ContentUnavailableView.search` with suggestion to broaden query |
| E-02 | Very short query (1-2 chars) | Skip semantic search; FTS5 prefix match only |
| E-03 | Query is only filters ("from john") | SwiftData predicate filter only, no FTS5/semantic |
| E-04 | Embeddings not available | Keyword-only search, no error shown |
| E-05 | FTS5 database corrupt | Rebuild FTS5 index automatically; show brief toast |
| E-06 | Search while sync in progress | Show stale results; newly synced emails appear on next search |
| E-07 | 100K+ emails | Performance may degrade; show "Searching..." indicator if >500ms |
| E-08 | Special characters in query | FTS5 handles via unicode61 tokenizer; escape FTS5 operators |
| E-09 | Multi-account search | Results include account indicator badge |
| E-10 | Empty search bar focused | Show zero-state with recent searches + top contacts |
| E-11 | Clear search | Return to previous thread list state; clear results |
| E-12 | Search during offline | Full functionality (all data is local) |

---

## 10. Alternatives Considered

| Alternative | Pros | Cons | Decision |
|-------------|------|------|----------|
| FTS5 only (no semantic) | Simple, fast, no AI dependency | Misses semantic matches ("budget" vs "financial") | Rejected — semantic search is a key differentiator |
| IMAP SEARCH | No local index, minimal storage | Requires network, slow, limited operators, no semantic | Rejected — must work offline |
| sqlite-vec extension | Optimized SIMD vector search | Additional C dependency, build complexity | Rejected for v1 — brute-force dot product sufficient for <100K emails |
| GRDB.swift for FTS5 | Safe Swift wrappers, migration support | 250KB dependency, learning curve | Rejected — raw SQLite C API keeps dependencies minimal |
| Separate search ViewModel | Encapsulates search logic | Violates MV pattern architecture | Rejected — use @State + use case injection |
| Core Spotlight integration | System-wide search | Limited to basic metadata, no semantic, no custom ranking | Not adopted — our search is richer |
| Porter stemmer in FTS5 | Better English word matching | Over-stems proper names and technical terms in email | Rejected — unicode61 with diacritic removal is safer for email content |

---

## 11. Open Questions

| # | Question | Resolution |
|---|----------|------------|
| 1 | FTS5 access layer | **Raw SQLite C API** — no dependency, consistent with llama.cpp C API usage |
| 2 | Vector search approach | **In-memory brute force** — sufficient for <100K emails, simpler than sqlite-vec |
| 3 | CoreML model scope | **MiniLM bundled for search**; DistilBERT bundling is defined by AI spec Section 5.4 and tracked under AI classification tasks (AI task IOS-A-01b). CoreMLClassifier.swift is shared — search implements embed(), classification implements classify()/detectSpam() |
| 4 | Reindex trigger | **Auto-detect** on first Search tab open; index progressively in background |
| 5 | Search tab placement | **Keep dedicated tab** — existing tab wired; add `.searchable()` within it |

---

## 12. Revision History

| Version | Date | Author | Change Summary |
|---------|------|--------|---------------|
| 1.0.0 | 2025-02-07 | Core Team | Extracted from monolithic spec v1.2.0 section 5.7 |
| 2.0.0 | 2026-02-10 | Core Team | Complete rewrite: hybrid FTS5+semantic architecture, RRF fusion, NL query parsing, detailed UX spec, performance budgets, edge cases, implementation tasks |
