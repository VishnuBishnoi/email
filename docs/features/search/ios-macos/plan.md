---
title: "Search — iOS/macOS Implementation Plan"
platform: iOS
spec-ref: docs/features/search/spec.md
version: "2.0.0"
status: draft
assignees:
  - Core Team
target-milestone: V1.0
---

# Search — iOS/macOS Implementation Plan

---

## 1. Scope

This plan covers the full search feature: FTS5 full-text index, semantic embedding search, hybrid RRF fusion, natural language query parsing, and the search UI. The implementation spans Data, Domain, and Presentation layers.

**Backend tasks** (IOS-A-01b, IOS-A-14–17) build the search infrastructure. **UI task** (IOS-A-18) builds the search interface. All tasks are tracked in this plan and the corresponding tasks file.

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
| `SyncEmailsUseCase.swift` | Hook `SearchIndexManager` for incremental indexing |
| `AIProcessingQueue.swift` | Wire embedding generation during batch processing; set `accountId` on new SearchIndex entries |
| `EmailRepositoryImpl.swift` | Hook `SearchIndexManager.removeEmail()` in `deleteEmail()` |
| `AccountRepositoryImpl.swift` | Hook `SearchIndexManager.removeAllForAccount()` in `removeAccount()` |

---

## 4. Implementation Phases

### Phase 1: FTS5 Foundation (IOS-A-14)

| Task | Description | Dependencies |
|------|-------------|-------------|
| IOS-A-14a | `FTS5Manager` — SQLite C API wrapper: open/close DB, create FTS5 table, insert/delete/search/highlight | None |
| IOS-A-14b | Unit tests for FTS5Manager (insert, search, prefix match, BM25 ranking, delete, highlight) | IOS-A-14a |

### Phase 2: CoreML Embedding Model (IOS-A-01b + IOS-A-16)

| Task | Description | Dependencies |
|------|-------------|-------------|
| IOS-A-01b | Bundle all-MiniLM-L6-v2 CoreML model (.mlpackage) in SPM resources | None |
| IOS-A-16a | `CoreMLClassifier` — implement embed() method per AI spec Section 7.1: load MiniLM model, tokenize text, run inference, return 384-dim Float32. classify()/detectSpam() are separate deliverables under AI classification tasks | IOS-A-01b |
| IOS-A-16b | `GenerateEmbeddingUseCase` — single query + batch embedding with CoreML → nil (FTS5-only fallback) | IOS-A-16a |
| IOS-A-16c | Unit tests for embedding generation (model loaded, output dimensions, normalization) | IOS-A-16b |

### Phase 3: Search Index & Vector Search (IOS-A-15)

| Task | Description | Dependencies |
|------|-------------|-------------|
| IOS-A-15a | `SearchIndexManager` — incremental FTS5 + embedding indexing during sync | IOS-A-14, IOS-A-16 |
| IOS-A-15b | `VectorSearchEngine` — load embeddings from SwiftData into memory, brute-force cosine similarity | IOS-A-16 |
| IOS-A-15c | Wire `SearchIndexManager` into `SyncEmailsUseCase` and `AIProcessingQueue` | IOS-A-15a |
| IOS-A-15d | Update `SearchIndex` model: add `accountId` field | None |
| IOS-A-15e | Unit tests for index manager and vector search | IOS-A-15a, IOS-A-15b |

### Phase 4: Search Use Case & Query Parser (IOS-A-17)

| Task | Description | Dependencies |
|------|-------------|-------------|
| IOS-A-17a | `SearchQueryParser` — regex + NSDataDetector for NL filter extraction | None |
| IOS-A-17b | `RRFMerger` — Reciprocal Rank Fusion scoring with configurable k and weights | None |
| IOS-A-17c | `SearchEmailsUseCase` — orchestrate parse → parallel FTS5 + semantic → RRF merge → filter | IOS-A-14, IOS-A-15b, IOS-A-17a, IOS-A-17b |
| IOS-A-17d | `SearchRepositoryImpl` — implement `SearchRepositoryProtocol` | IOS-A-17c |
| IOS-A-17e | Unit tests for parser, merger, and use case | IOS-A-17a–d |

### Phase 5: Search UI (IOS-A-18)

| Task | Description | Dependencies |
|------|-------------|-------------|
| IOS-A-18a | `SearchView` — search bar, view states, debounced search, scope picker | IOS-A-17 |
| IOS-A-18b | `SearchFilterChipsView` — horizontal filter chips, tap to toggle | IOS-A-18a |
| IOS-A-18c | `SearchResultRowView` — result row with highlights, snippet, match source indicator | IOS-A-18a |
| IOS-A-18d | `RecentSearchesView` — zero-state with recent searches + top contacts | IOS-A-18a |
| IOS-A-18e | Wire into ContentView (replace SearchPlaceholder), environment injection | IOS-A-18a |
| IOS-A-18f | Accessibility annotations (labels, hints, Dynamic Type, VoiceOver) | IOS-A-18a–d |
| IOS-A-18g | Unit + integration tests | IOS-A-18a–f |

---

## 5. Dependency Graph

```
IOS-A-01b (CoreML model bundling)
    |
    v
IOS-A-16 (GenerateEmbeddingUseCase)
    |                               IOS-A-14 (FTS5Manager)
    |                                   |
    v                                   v
IOS-A-15 (SearchIndexManager + VectorSearchEngine)
    |                                   |
    +-----------------------------------+
    |
    v
IOS-A-17 (SearchEmailsUseCase + QueryParser + RRFMerger)
    |
    v
IOS-A-18 (Search UI)
```

**Parallelizable**: IOS-A-01b + IOS-A-14 can be built concurrently (no dependency between them). IOS-A-17a (QueryParser) and IOS-A-17b (RRFMerger) can also be built concurrently.

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
