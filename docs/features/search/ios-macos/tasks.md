---
title: "Search — iOS/macOS Task Breakdown"
platform: iOS, macOS
plan-ref: docs/features/search/ios-macos/plan.md
version: "1.1.0"
status: draft
updated: 2026-02-10
---

# Search — iOS/macOS Task Breakdown

> Each task references its plan ID, spec section, and acceptance criteria. Status values: `todo`, `in-progress`, `done`, `blocked`.

> **This is the only unlocked feature.** All other features (email sync, composer, AI phases 1–3+5, polish, macOS adaptation) are complete and locked. Search is the remaining major work item.

> Note: Backend tasks IOS-A-14 through IOS-A-17 (embedding engine, vector store, search index manager, search use case) are tracked in the AI Features task file. This file tracks the search-specific UI task.

---

### IOS-A-14 to IOS-A-17: Semantic Search Backend (tracked in AI Features tasks)

> These backend tasks are defined and tracked in `docs/features/ai-features/ios-macos/tasks.md`. See that file for full deliverables, status, and spec refs.

| Task ID | Description | Status | Tracked In |
|---------|-------------|--------|------------|
| IOS-A-01b | CoreML Model Bundling (DistilBERT + MiniLM) | `todo` | AI Features tasks |
| IOS-A-02b | CoreMLClassifier wrapper | `todo` | AI Features tasks |
| IOS-A-14 | `VectorStore` — embedding storage + cosine similarity | `todo` | AI Features tasks |
| IOS-A-15 | `SearchIndexManager` — incremental index build during sync | `todo` | AI Features tasks |
| IOS-A-16 | `GenerateEmbeddingUseCase` — batch embeddings via CoreML | `todo` | AI Features tasks |
| IOS-A-17 | `SearchEmailsUseCase` — semantic + exact combined search | `todo` | AI Features tasks |

### Existing Infrastructure

- `SearchIndex` SwiftData model exists (Domain/Models)
- `SearchRepositoryProtocol` defined (Domain/Protocols) with `search()` method — no implementation yet
- `AIRepositoryImpl.generateEmbedding()` exists with hash-based 128D fallback — needs CoreML MiniLM for real 384D embeddings
- `SearchPlaceholder.swift` shows "Search coming soon" placeholder
- `AIProcessingQueue` has `generateEmbeddings()` hook — ready to wire

### IOS-A-18: Search UI

- **Status**: `todo`
- **Spec ref**: Search spec, FR-SEARCH-01, FR-SEARCH-02, FR-SEARCH-03
- **Validation ref**: AC-A-07
- **Description**: Search bar, results display, and filters. Depends on backend tasks IOS-A-14..17. **Note**: Use MV pattern (no ViewModels) per project architecture.
- **Deliverables**:
  - [ ] `SearchView.swift` — search bar, results, filters (MV pattern, @State + @Environment)
  - [ ] Recent searches persistence (UserDefaults or SwiftData)
  - [ ] Integration with `SearchEmailsUseCase` for combined semantic + keyword results
  - [ ] Wire into ThreadListView navigation
  - [ ] Unit and integration tests
