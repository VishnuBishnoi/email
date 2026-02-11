---
title: "Search — iOS/macOS Task Breakdown"
platform: iOS
plan-ref: docs/features/search/ios-macos/plan.md
version: "2.1.0"
status: locked
updated: 2026-02-11
---

# Search — iOS/macOS Task Breakdown

> Each task references its plan ID, spec section, and acceptance criteria. Status values: `todo`, `in-progress`, `done`, `blocked`.

> **All search tasks are complete.** All feature documents are now locked. AI Phase 4 forward-references (IOS-A-14..17, IOS-A-01b) are superseded by Search tasks IOS-S-00..05 — see ID note below.

---

### Existing Infrastructure (Completed)

- `SearchIndex` SwiftData model (Domain/Models) — `accountId` field present
- `SearchRepositoryProtocol` defined (Domain/Protocols) — expanded for hybrid search API
- `GenerateEmbeddingUseCase` exists with hash-based fallback (CoreML model bundling deferred to IOS-S-00)
- `SearchContentView.swift` replaces former `SearchPlaceholder`
- `AIProcessingQueue` wired with `SearchIndexManager` for embedding indexing
- `ThreadListView` search tab wired to `SearchContentView`

> **Task ID note**: AI Features tasks (Phase 4) define skeletal forward-references for search backend work under IDs IOS-A-14..17 (see AI tasks.md line 337). To avoid ID collision with the locked AI docs, Search uses its own namespace: IOS-S-00 through IOS-S-05. The AI forward-references are superseded by the detailed definitions below.

---

### IOS-S-01: FTS5 Foundation

- **Status**: `done`
- **Spec ref**: FR-SEARCH-06
- **Validation ref**: AC-S-07
- **Description**: SQLite FTS5 full-text search database wrapper using raw C API. Separate `search.sqlite` database co-located with SwiftData store.
- **Deliverables**:
  - [x] `FTS5Manager.swift` — actor wrapping raw SQLite C API
    - Open/close `search.sqlite` database
    - Create FTS5 virtual table with unicode61 tokenizer (no porter stemmer)
    - Insert email content (email_id, account_id, subject, body, sender_name, sender_email)
    - Delete by email_id
    - Search with prefix matching (`query*`), BM25 ranking
    - Highlight matches via `highlight()` auxiliary function
    - Handle corrupt DB: detect and auto-rebuild
  - [x] Unit tests: FTS5ManagerTests (10+ tests)
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

### IOS-S-00: CoreML Model Bundling (MiniLM — Search Scope)

- **Status**: `done` (hash-based fallback shipping; CoreML model bundling deferred post-V1)
- **Spec ref**: FR-SEARCH-07, Search spec Section 3.2
- **Validation ref**: AC-S-06
- **Description**: Bundle all-MiniLM-L6-v2 CoreML model (.mlpackage) as SPM resource for 384-dim embedding generation. ~50MB bundled model. DistilBERT model bundling is defined by AI spec Section 5.4 and tracked under AI classification tasks. AI task IOS-A-01b has broader scope (DistilBERT + MiniLM); this Search-scoped sub-task covers MiniLM only.
- **Deliverables**:
  - [x] `GenerateEmbeddingUseCase.swift` — enum-based use case with hash fallback (ships V1)
  - [ ] Convert all-MiniLM-L6-v2 to CoreML format (.mlpackage) — deferred post-V1
  - [ ] Add to SPM package resources — deferred post-V1
  - [ ] Verify model loads on iOS 18 simulator and device — deferred post-V1
  - [ ] Document model source, license (Apache 2.0), and conversion steps — deferred post-V1

---

### IOS-S-02: GenerateEmbeddingUseCase

- **Status**: `done`
- **Spec ref**: FR-SEARCH-07
- **Validation ref**: AC-S-06, AC-S-08
- **Description**: `CoreMLClassifier` wrapper (AI spec Section 7.1) + domain use case for generating query and batch embeddings. Returns nil when CoreML model is unavailable; search falls back to FTS5-only per AI spec Section 7.2.
- **Deliverables**:
  - [x] `GenerateEmbeddingUseCase.swift` — domain use case (enum-based, static methods)
    - Single query embedding (for search)
    - Batch embedding (for indexing during sync)
    - L2 normalization of output vectors
    - Return nil if model unavailable (FTS5-only fallback per AI spec 7.2)
  - [x] Unit tests: GenerateEmbeddingUseCaseTests
    - Single embedding generation
    - Batch embedding generation
    - Nil return when model unavailable
    - Output dimension validation

---

### IOS-S-03: SearchIndexManager + VectorSearchEngine

- **Status**: `done`
- **Spec ref**: FR-SEARCH-08, FR-SEARCH-07
- **Validation ref**: AC-S-09
- **Description**: Incremental search index management during sync, and in-memory vector search engine for semantic similarity.
- **Deliverables**:
  - [x] `SearchIndex.swift` — `accountId` field present
  - [x] `SearchIndexManager.swift` — @MainActor managing incremental indexing (single owner of all FTS5 + SearchIndex mutations)
    - `indexEmail(email:)` — insert into FTS5 + generate embedding + upsert SearchIndex
    - `removeEmail(emailId:)` — delete FTS5 row + delete SearchIndex entry
    - `openIndex()` / `reindexIfNeeded()` — wired to app startup via VaultMailApp.swift
  - [x] `AIProcessingQueue` delegates embedding work through `SearchIndexManager`
  - [x] Wired into app startup: `searchIndexManager.openIndex()` + `searchIndexManager.reindexIfNeeded()`
  - [x] `VectorSearchEngine.swift` — in-memory cosine similarity via Accelerate.vDSP_dotpr
    - Load pre-normalized embeddings from SwiftData SearchIndex entries
    - Brute-force dot product for cosine similarity
    - Return top-50 results by similarity score
  - [x] Unit tests: SearchIndexManagerTests, VectorSearchEngineTests

---

### IOS-S-04: SearchEmailsUseCase + QueryParser + RRFMerger

- **Status**: `done`
- **Spec ref**: FR-SEARCH-04, FR-SEARCH-05, FR-SEARCH-03
- **Validation ref**: AC-S-05, AC-S-06, AC-S-07
- **Description**: Natural language query parser, RRF fusion merger, and the main search orchestration use case.
- **Deliverables**:
  - [x] `SearchQuery.swift` — SearchQuery, SearchFilters, SearchScope models
  - [x] `SearchResult.swift` — SearchResult, MatchSource models
  - [x] `SearchQueryParser.swift` — NL query parsing
    - Extract sender filter ("from john", "from user@email.com")
    - Extract date range ("last week", "yesterday", "in January", "before March") via NSDataDetector + regex
    - Extract attachment filter ("with attachments", "has attachment", "with files")
    - Extract category filter ("promotions", "social emails")
    - Extract read status ("unread", "read")
    - Return remaining text as free-text query
    - Complete in <5ms
  - [x] `RRFMerger.swift` — Reciprocal Rank Fusion
    - Configurable k parameter (default: 60)
    - Configurable weight per source (semantic: 1.5x, keyword: 1.0x)
    - Merge two ranked lists into single scored list
    - Deduplicate by email ID
  - [x] `SearchEmailsUseCase.swift` — hybrid search orchestration (@MainActor)
    - Parse query via SearchQueryParser
    - Execute FTS5 + semantic search in parallel (async let)
    - Merge via RRFMerger
    - Apply structured filters via SwiftData predicate
    - Group results by thread
    - Return SearchResult array sorted by score
    - Graceful fallback: keyword-only if embeddings unavailable
  - [x] `SearchRepositoryProtocol` — expanded for hybrid search
  - [x] `SearchRepositoryImpl.swift` — thin wrapper delegating to SearchEmailsUseCase
  - [x] Unit tests: SearchQueryParserTests, RRFMergerTests, SearchEmailsUseCaseTests

---

### IOS-S-05: Search UI

- **Status**: `done`
- **Spec ref**: FR-SEARCH-01, FR-SEARCH-02, FR-SEARCH-03, FR-SEARCH-09
- **Validation ref**: AC-S-01, AC-S-02, AC-S-03, AC-S-04, AC-S-10, AC-S-12
- **Description**: Search bar, filters, results display, recent searches. **MV pattern** (no ViewModels) per project architecture — uses @State, @Environment, .task.
- **Deliverables**:
  - [x] `SearchContentView.swift` — main search view (MV pattern)
    - `.searchable` search bar
    - Debounced search via `.task(id:)`
    - View states: idle (zero-state), searching (spinner), results (list), empty
    - Result count display
    - Integration with `SearchEmailsUseCase`
  - [x] `SearchFilterChipsView.swift` — horizontal scrollable filter chips
    - Tappable chips for structured filters
    - Active filter indication
  - [x] `HighlightedThreadRowView.swift` — individual result row with highlighted matching terms
  - [x] `RecentSearchesView.swift` — zero-state content
    - Recent searches stored in UserDefaults
    - "Clear Recent Searches" button
    - Tap to execute recent search
  - [x] Wired into ContentView — SearchContentView replaces SearchPlaceholder
  - [x] SearchEmailsUseCase passed through ContentView
  - [x] Accessibility annotations present
