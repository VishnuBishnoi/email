---
title: "Search — iOS/macOS Task Breakdown"
platform: iOS, macOS
plan-ref: docs/features/search/ios-macos/plan.md
version: "1.0.0"
status: draft
updated: 2025-02-07
---

# Search — iOS/macOS Task Breakdown

> Each task references its plan ID, spec section, and acceptance criteria. Status values: `todo`, `in-progress`, `done`, `blocked`.

> Note: Backend tasks IOS-A-14 through IOS-A-17 (embedding engine, vector store, search index manager, search use case) are tracked in the AI Features task file. This file tracks the search-specific UI task.

---

### IOS-A-14 to IOS-A-18: Semantic Search Pipeline

- **Status**: `todo`
- **Spec ref**: Search spec, FR-SEARCH-01, FR-SEARCH-02, FR-SEARCH-03; AI Features spec, FR-AI-05
- **Validation ref**: AC-A-07
- **Description**: End-to-end semantic search from indexing to UI.
- **Deliverables**:
  - [ ] `EmbeddingEngine.swift` — generate embeddings from text
  - [ ] `VectorStore.swift` — store and query embeddings
  - [ ] `SearchIndexManager.swift` — build and incrementally update index
  - [ ] `SearchEmailsUseCase.swift` — semantic + exact combined search
  - [ ] `SearchView.swift` — search bar, results, filters
  - [ ] `SearchViewModel.swift`
  - [ ] Recent searches persistence
  - [ ] Unit and integration tests
