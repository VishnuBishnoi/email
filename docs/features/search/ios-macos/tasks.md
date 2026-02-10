---
title: "Search — iOS/macOS Task Breakdown"
platform: iOS
plan-ref: docs/features/search/ios-macos/plan.md
version: "2.0.0"
status: draft
updated: 2026-02-10
---

# Search — iOS/macOS Task Breakdown

> Each task references its plan ID, spec section, and acceptance criteria. Status values: `todo`, `in-progress`, `done`, `blocked`.

> **This is the only unlocked feature.** All other features (email sync, composer, AI phases 1–3+5, polish, macOS adaptation) are complete and locked. Search is the remaining major work item.

---

### Existing Infrastructure

- `SearchIndex` SwiftData model exists (Domain/Models) — needs `accountId` field added
- `SearchRepositoryProtocol` defined (Domain/Protocols) with `search()`, `indexEmail()`, `removeFromIndex()` — needs expansion for hybrid search API
- `AIRepositoryImpl.generateEmbedding()` exists with FNV-1a hash-based 128D fallback — will be replaced by `CoreMLClassifier.embed()` returning 384D or nil
- `SearchPlaceholder.swift` shows "Search coming soon" placeholder — will be replaced by `SearchView`
- `AIProcessingQueue` has `generateEmbeddings()` hook — ready to wire
- `ThreadListView` has search tab wired to `SearchPlaceholder` — needs rewiring to `SearchView`

---

### IOS-A-14: FTS5 Foundation

- **Status**: `todo`
- **Spec ref**: FR-SEARCH-06
- **Validation ref**: AC-S-07
- **Description**: SQLite FTS5 full-text search database wrapper using raw C API. Separate `search.sqlite` database co-located with SwiftData store.
- **Deliverables**:
  - [ ] `FTS5Manager.swift` — actor wrapping raw SQLite C API
    - Open/close `search.sqlite` database
    - Create FTS5 virtual table with unicode61 tokenizer (no porter stemmer)
    - Insert email content (email_id, account_id, subject, body, sender_name, sender_email, folder_name)
    - Delete by email_id
    - Search with prefix matching (`query*`), BM25 ranking
    - Highlight matches via `highlight()` auxiliary function
    - Handle corrupt DB: detect and auto-rebuild
  - [ ] Unit tests: FTS5ManagerTests (10+ tests)
    - Insert and search
    - Prefix matching ("proj" → "project")
    - BM25 ranking (multi-term queries)
    - Delete and verify removal
    - Highlight output
    - Empty corpus search
    - Special character handling
    - Unicode/accented character search
    - DB lifecycle (open/close/reopen)
    - Corrupt DB recovery

---

### IOS-A-01b: CoreML Model Bundling (MiniLM)

- **Status**: `todo`
- **Spec ref**: FR-SEARCH-07, Search spec Section 3.2
- **Validation ref**: AC-S-06
- **Description**: Bundle all-MiniLM-L6-v2 CoreML model (.mlpackage) as SPM resource for 384-dim embedding generation. ~50MB bundled model. DistilBERT model bundling is defined by AI spec Section 5.4 and tracked under AI classification tasks.
- **Deliverables**:
  - [ ] Convert all-MiniLM-L6-v2 to CoreML format (.mlpackage)
  - [ ] Add to SPM package resources
  - [ ] Verify model loads on iOS 18 simulator and device
  - [ ] Document model source, license (Apache 2.0), and conversion steps

---

### IOS-A-16: GenerateEmbeddingUseCase

- **Status**: `todo`
- **Spec ref**: FR-SEARCH-07
- **Validation ref**: AC-S-06, AC-S-08
- **Description**: `CoreMLClassifier` wrapper (AI spec Section 7.1) + domain use case for generating query and batch embeddings. Returns nil when CoreML model is unavailable; search falls back to FTS5-only per AI spec Section 7.2.
- **Deliverables**:
  - [ ] `CoreMLClassifier.swift` — per AI spec Section 7.1: load MiniLM model for `embed()`, return 384-dim Float32 array. `classify()` and `detectSpam()` (DistilBERT) are separate deliverables under AI classification tasks.
  - [ ] `GenerateEmbeddingUseCase.swift` — domain use case
    - Single query embedding (for search)
    - Batch embedding (for indexing during sync)
    - L2 normalization of output vectors
    - Return nil if model unavailable (FTS5-only fallback per AI spec 7.2)
  - [ ] Unit tests: GenerateEmbeddingUseCaseTests (4+ tests)
    - Single embedding generation
    - Batch embedding generation
    - Nil return when model unavailable
    - Output dimension validation (384)

---

### IOS-A-15: SearchIndexManager + VectorSearchEngine

- **Status**: `todo`
- **Spec ref**: FR-SEARCH-08, FR-SEARCH-07
- **Validation ref**: AC-S-09
- **Description**: Incremental search index management during sync, and in-memory vector search engine for semantic similarity.
- **Deliverables**:
  - [ ] Update `SearchIndex.swift` — add `accountId: String = ""` (lightweight SwiftData migration with default)
  - [ ] Implement `SearchIndexManager.backfillAccountIds()`:
    - Fetch all SearchIndex entries where accountId is empty string
    - For each, fetch corresponding Email by emailId, set accountId from email.accountId
    - Batch save (100 entries per save)
    - Wire into app startup with UserDefaults guard (`searchIndexAccountIdBackfillComplete`)
  - [ ] Update `AIProcessingQueue.generateEmbeddings()` to set `accountId` on new SearchIndex entries
  - [ ] `SearchIndexManager.swift` — actor managing incremental indexing
    - On new email sync: insert into FTS5 + generate embedding + upsert SearchIndex
    - On email delete: `removeEmail(emailId:)` — delete FTS5 row + delete SearchIndex entry
    - On account delete: `removeAllForAccount(accountId:)` — bulk-delete FTS5 rows + SearchIndex entries by accountId
    - On sync reconciliation: clean up orphaned FTS5/SearchIndex entries for server-missing emails
    - Auto-detect unindexed emails and index progressively in background
    - Full reindex capability (for Settings > "Rebuild Search Index")
    - Wire into `SyncEmailsUseCase` sync pipeline
    - Wire into `AIProcessingQueue` batch processing
  - [ ] Wire `removeEmail()` into `EmailRepositoryImpl.deleteEmail()`
  - [ ] Wire `removeAllForAccount()` into `AccountRepositoryImpl.removeAccount()`
  - [ ] `VectorSearchEngine.swift` — in-memory cosine similarity
    - Load pre-normalized embeddings from SwiftData SearchIndex entries
    - Brute-force dot product for cosine similarity
    - Return top-50 results by similarity score
    - Account-scoped loading for memory efficiency
  - [ ] Unit tests: SearchIndexManagerTests (8+ tests including deletion + backfill), VectorSearchEngineTests (5+ tests)

---

### IOS-A-17: SearchEmailsUseCase + QueryParser + RRFMerger

- **Status**: `todo`
- **Spec ref**: FR-SEARCH-04, FR-SEARCH-05, FR-SEARCH-03
- **Validation ref**: AC-S-05, AC-S-06, AC-S-07
- **Description**: Natural language query parser, RRF fusion merger, and the main search orchestration use case.
- **Deliverables**:
  - [ ] `SearchQuery.swift` — SearchQuery, SearchFilters, SearchScope models
  - [ ] `SearchResult.swift` — SearchResult, MatchSource models
  - [ ] `SearchQueryParser.swift` — NL query parsing
    - Extract sender filter ("from john", "from user@email.com")
    - Extract date range ("last week", "yesterday", "in January", "before March") via NSDataDetector + regex
    - Extract attachment filter ("with attachments", "has attachment", "with files")
    - Extract category filter ("promotions", "social emails")
    - Extract read status ("unread", "read")
    - Return remaining text as free-text query
    - Complete in <5ms
  - [ ] `RRFMerger.swift` — Reciprocal Rank Fusion
    - Configurable k parameter (default: 60)
    - Configurable weight per source (semantic: 1.5x, keyword: 1.0x)
    - Merge two ranked lists into single scored list
    - Deduplicate by email ID
  - [ ] `SearchEmailsUseCase.swift` — hybrid search orchestration
    - Parse query via SearchQueryParser
    - Execute FTS5 + semantic search in parallel (async let)
    - Merge via RRFMerger
    - Apply structured filters via SwiftData predicate
    - Group results by thread
    - Return SearchResult array sorted by score
    - Graceful fallback: keyword-only if embeddings unavailable
  - [ ] Update `SearchRepositoryProtocol` — expand for hybrid search
  - [ ] `SearchRepositoryImpl.swift` — implement expanded protocol
  - [ ] Unit tests: SearchQueryParserTests (10+), RRFMergerTests (5+), SearchEmailsUseCaseTests (8+)

---

### IOS-A-18: Search UI

- **Status**: `todo`
- **Spec ref**: FR-SEARCH-01, FR-SEARCH-02, FR-SEARCH-03, FR-SEARCH-09
- **Validation ref**: AC-S-01, AC-S-02, AC-S-03, AC-S-04, AC-S-10, AC-S-12
- **Description**: Search bar, filters, results display, recent searches. **MV pattern** (no ViewModels) per project architecture — uses @State, @Environment, .task.
- **Deliverables**:
  - [ ] `SearchView.swift` — main search view (MV pattern)
    - `.searchable(text:tokens:isPresented:placement:)` search bar
    - `.searchScopes()` for All Mail vs Current Folder
    - 300ms debounced search via `.task(id:)`
    - View states: idle (zero-state), searching (spinner), results (list), empty (ContentUnavailableView)
    - Result count display
    - Integration with `SearchEmailsUseCase` via @Environment
  - [ ] `SearchFilterChipsView.swift` — horizontal scrollable filter chips
    - Tappable chips for: Sender, Date, Attachment, Folder, Category, Read/Unread
    - Active filter indication
    - Chip tap opens filter picker (sheet or inline)
  - [ ] `SearchResultRowView.swift` — individual result row
    - Subject with highlighted matching terms
    - Body snippet with match context
    - Sender, date, attachment indicator
    - Match source indicator (keyword / semantic / both)
    - Account indicator for multi-account
  - [ ] `RecentSearchesView.swift` — zero-state content
    - Last 10 recent searches (UserDefaults)
    - Top 5 frequent contacts as suggested searches
    - "Clear Recent Searches" button
    - Tap to execute recent/suggested search
  - [ ] Wire into ContentView — replace `SearchPlaceholder` with `SearchView`
  - [ ] Environment injection: wire `SearchEmailsUseCase` into environment
  - [ ] Accessibility annotations:
    - `accessibilityLabel("Search emails")` on search bar
    - Filter chip labels ("Filter: From John Smith")
    - Result row accessible descriptions
    - Empty state VoiceOver announcement
    - Recent search labels
    - Dynamic Type support across all elements
  - [ ] Unit + integration tests: SearchView integration, recent searches persistence, filter chip behavior
