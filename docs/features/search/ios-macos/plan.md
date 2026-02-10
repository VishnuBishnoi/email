---
title: "Search — iOS/macOS Implementation Plan"
platform: iOS
spec-ref: docs/features/search/spec.md
version: "2.0.0"
status: locked
assignees:
  - Core Team
target-milestone: V1.0
---

# Search — iOS/macOS Implementation Plan

---

## 1. Scope

This plan covers the full search feature: FTS5 full-text index, semantic embedding search, hybrid RRF fusion, natural language query parsing, and the search UI. The implementation spans Data, Domain, and Presentation layers.

**Task IDs**: Search uses its own namespace (IOS-S-00..05) to avoid collision with locked AI docs. AI Phase 4 forward-references (IOS-A-14..17) are superseded by the IOS-S-xx tasks defined here.

**Backend tasks** (IOS-S-00, IOS-S-01–04) build the search infrastructure. **UI task** (IOS-S-05) builds the search interface. All tasks are tracked in this plan and the corresponding tasks file.

---

## 2. Platform Context

Refer to Foundation plan Section 2. Search is fully local (no server-side IMAP SEARCH). All components work offline. macOS adaptation is deferred — iOS search UI only for V1.

---

## 3. Architecture Mapping

### Files — Data Layer

| File | Layer | Purpose |
|------|-------|---------|
| `FTS5Manager.swift` | Data/Search | SQLite FTS5 database wrapper (raw C API) — create, insert, delete, search, highlight |
| `VectorSearchEngine.swift` | Data/Search | In-memory cosine similarity on pre-normalized 384-dim embeddings |
| `RRFMerger.swift` | Data/Search | Reciprocal Rank Fusion scoring: merge keyword + semantic rankings |
| `SearchRepositoryImpl.swift` | Data/Search | Implements `SearchRepositoryProtocol` — orchestrates FTS5 + vector + SwiftData |
| `SearchIndexManager.swift` | Data/Search | Incremental index build during sync (FTS5 insert + embedding generation) |

### Files — Domain Layer

| File | Layer | Purpose |
|------|-------|---------|
| `SearchEmailsUseCase.swift` | Domain/UseCases | Orchestrates hybrid search: parse → FTS5 + semantic in parallel → RRF merge → filter |
| `GenerateEmbeddingUseCase.swift` | Domain/UseCases | Query + batch embedding generation via CoreML (all-MiniLM-L6-v2) |
| `SearchQueryParser.swift` | Domain/UseCases | Natural language query → SearchQuery (regex + NSDataDetector) |
| `SearchQuery.swift` | Domain/Models | SearchQuery, SearchFilters, SearchScope model types |
| `SearchResult.swift` | Domain/Models | SearchResult, MatchSource model types |

### Files — Presentation Layer

| File | Layer | Purpose |
|------|-------|---------|
| `SearchView.swift` | Presentation/Views/Search | Search bar, results list, view states (MV pattern, @State + @Environment) |
| `SearchFilterChipsView.swift` | Presentation/Views/Search | Horizontal filter chip bar below search |
| `SearchResultRowView.swift` | Presentation/Views/Search | Individual result row with highlights and snippet |
| `RecentSearchesView.swift` | Presentation/Views/Search | Zero-state: recent searches + suggested contacts |

### Files — AI/CoreML

| File | Layer | Purpose |
|------|-------|---------|
| `all-MiniLM-L6-v2.mlpackage` | Resources | CoreML embedding model (384-dim, 50MB, bundled) |
| `CoreMLClassifier.swift` | Data/AI | CoreML wrapper per AI spec Section 7.1 — search scope implements embed() (MiniLM); classify()/detectSpam() (DistilBERT) are separate deliverables under AI classification tasks |

### Existing Files to Modify

| File | Change |
|------|--------|
| `SearchIndex.swift` | Add `accountId: String` field |
| `SearchRepositoryProtocol.swift` | Expand protocol to support hybrid search API |
| `SearchPlaceholder.swift` | Replace with `SearchView` |
| `ContentView.swift` / tab navigation | Wire `SearchView` into Search tab |
| `AIProcessingQueue.swift` | Refactor `generateEmbeddings()` to delegate to `SearchIndexManager.indexEmail()`; remove all direct SearchIndex manipulation. SearchIndexManager is the single entry point for indexing, called during sync via AIProcessingQueue |
| `EmailRepositoryImpl.swift` | Hook `SearchIndexManager.removeEmail()` in `deleteEmail()` |
| `AccountRepositoryImpl.swift` | Hook `SearchIndexManager.removeAllForAccount()` in `removeAccount()` |

---

## 4. Implementation Phases

### Phase 1: FTS5 Foundation (IOS-S-01)

| Task | Description | Dependencies |
|------|-------------|-------------|
| IOS-S-01a | `FTS5Manager` — SQLite C API wrapper: open/close DB, create FTS5 table, insert/delete/search/highlight | None |
| IOS-S-01b | Unit tests for FTS5Manager (insert, search, prefix match, BM25 ranking, delete, highlight) | IOS-S-01a |

### Phase 2: CoreML Embedding Model (IOS-S-00 + IOS-S-02)

| Task | Description | Dependencies |
|------|-------------|-------------|
| IOS-S-00 | Bundle all-MiniLM-L6-v2 CoreML model (.mlpackage) in SPM resources | None |
| IOS-S-02a | `CoreMLClassifier` — implement embed() method per AI spec Section 7.1: load MiniLM model, tokenize text, run inference, return 384-dim Float32. classify()/detectSpam() are separate deliverables under AI classification tasks | IOS-S-00 |
| IOS-S-02b | `GenerateEmbeddingUseCase` — single query + batch embedding with CoreML → nil (FTS5-only fallback) | IOS-S-02a |
| IOS-S-02c | Unit tests for embedding generation (model loaded, output dimensions, normalization) | IOS-S-02b |

### Phase 3: Search Index & Vector Search (IOS-S-03)

| Task | Description | Dependencies |
|------|-------------|-------------|
| IOS-S-03a | `SearchIndexManager` — incremental FTS5 + embedding indexing during sync | IOS-S-01, IOS-S-02 |
| IOS-S-03b | `VectorSearchEngine` — load embeddings from SwiftData into memory, brute-force cosine similarity | IOS-S-02 |
| IOS-S-03c | Wire `SearchIndexManager` into `AIProcessingQueue` (single delegation path: sync → AIProcessingQueue → SearchIndexManager) | IOS-S-03a |
| IOS-S-03d | Update `SearchIndex` model: add `accountId` field | None |
| IOS-S-03e | Unit tests for index manager and vector search | IOS-S-03a, IOS-S-03b |

### Phase 4: Search Use Case & Query Parser (IOS-S-04)

| Task | Description | Dependencies |
|------|-------------|-------------|
| IOS-S-04a | `SearchQueryParser` — regex + NSDataDetector for NL filter extraction | None |
| IOS-S-04b | `RRFMerger` — Reciprocal Rank Fusion scoring with configurable k and weights | None |
| IOS-S-04c | `SearchEmailsUseCase` — orchestrate parse → parallel FTS5 + semantic → RRF merge → filter | IOS-S-01, IOS-S-03b, IOS-S-04a, IOS-S-04b |
| IOS-S-04d | `SearchRepositoryImpl` — implement `SearchRepositoryProtocol` | IOS-S-04c |
| IOS-S-04e | Unit tests for parser, merger, and use case | IOS-S-04a–d |

### Phase 5: Search UI (IOS-S-05)

| Task | Description | Dependencies |
|------|-------------|-------------|
| IOS-S-05a | `SearchView` — search bar, view states, debounced search, scope picker | IOS-S-04 |
| IOS-S-05b | `SearchFilterChipsView` — horizontal filter chips, tap to toggle | IOS-S-05a |
| IOS-S-05c | `SearchResultRowView` — result row with highlights, snippet, match source indicator | IOS-S-05a |
| IOS-S-05d | `RecentSearchesView` — zero-state with recent searches + top contacts | IOS-S-05a |
| IOS-S-05e | Wire into ContentView (replace SearchPlaceholder), environment injection | IOS-S-05a |
| IOS-S-05f | Accessibility annotations (labels, hints, Dynamic Type, VoiceOver) | IOS-S-05a–d |
| IOS-S-05g | Unit + integration tests | IOS-S-05a–f |

---

## 5. Dependency Graph

```
IOS-S-00 (CoreML model bundling)
    |
    v
IOS-S-02 (GenerateEmbeddingUseCase)
    |                               IOS-S-01 (FTS5Manager)
    |                                   |
    v                                   v
IOS-S-03 (SearchIndexManager + VectorSearchEngine)
    |                                   |
    +-----------------------------------+
    |
    v
IOS-S-04 (SearchEmailsUseCase + QueryParser + RRFMerger)
    |
    v
IOS-S-05 (Search UI)
```

**Parallelizable**: IOS-S-00 + IOS-S-01 can be built concurrently (no dependency between them). IOS-S-04a (QueryParser) and IOS-S-04b (RRFMerger) can also be built concurrently.

---

## 6. Risks and Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| CoreML model conversion issues | Medium | High | Test .mlpackage early; fall back to FTS5-only keyword search if conversion fails |
| FTS5 not available in iOS SQLite | Low | High | iOS bundles SQLite with FTS5 enabled by default since iOS 8 |
| Memory pressure from in-memory vectors (50K+ emails) | Medium | Medium | Lazy loading by account; unload when Search tab not visible |
| BM25 ranking quality for email content | Low | Low | Email text is well-structured (subject, body, sender); BM25 works well |
| Raw SQLite C API memory management | Medium | Medium | Careful `sqlite3_finalize` / `sqlite3_close` in deinit; unit test lifecycle |
| Search performance degrades at 100K+ | Low | Medium | Document as known limitation; brute-force vector search is O(n) |
