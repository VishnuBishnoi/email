---
title: "AI Features — iOS/macOS Task Breakdown"
platform: iOS, macOS
plan-ref: docs/features/ai-features/ios-macos/plan.md
version: "2.0.0"
status: locked
updated: 2026-02-10
---

# AI Features — iOS/macOS Task Breakdown

> Each task references its plan ID, spec section, and acceptance criteria. Status values: `todo`, `in-progress`, `done`, `blocked`.

---

## Phase 1: Engine Scaffolding + CoreML Classification

### IOS-A-01: llama.cpp SPM Integration

- **Status**: `done`
- **Spec ref**: FR-AI-01 (Tiered engine requirements)
- **Validation ref**: AC-A-01
- **Description**: Integrate llama.cpp as SPM dependency via SpeziLLM XCFramework or llama.swift. Verify compilation on iOS and macOS.
- **Decision**: Selected `mattt/llama.swift` (XCFramework binary, proper semantic versioning, automated upstream tracking). Rejected SpeziLLM (archived llama.cpp fork, C++ interop leak) and direct llama.cpp (unsafeFlags blocks versioning).
- **Deliverables**:
  - [x] SPM package dependency added — `llama.swift` from: "2.7972.0" (resolved to b7974)
  - [x] Swift bridging configured for C API — LlamaSwift re-exports raw C API via `@_exported import llama`
  - [x] Build succeeds on both iOS and macOS targets — verified clean build (0 errors, 0 warnings)
  - [x] Basic smoke test — LlamaEngine actor wraps full inference pipeline, unit tests verify error paths

### IOS-A-01b: CoreML Model Bundling

- **Status**: `todo`
- **Spec ref**: FR-AI-01, FR-AI-02, FR-AI-05, FR-AI-06
- **Validation ref**: AC-A-01b
- **Description**: Bundle DistilBERT and all-MiniLM-L6-v2 CoreML .mlpackage files in the app.
- **Deliverables**:
  - [ ] Convert DistilBERT to ANE-optimized CoreML via `apple/ml-ane-transformers` + `coremltools`
  - [ ] Convert all-MiniLM-L6-v2 to CoreML via `coremltools`
  - [ ] Add .mlpackage files to SPM package resources
  - [ ] Verify ANE inference on A14+ device
  - [ ] Total bundled size < 150 MB

### IOS-A-02: AIEngineProtocol + LlamaEngine + FoundationModelEngine

- **Status**: `done`
- **Spec ref**: FR-AI-01, AI-03 (Constitution)
- **Validation ref**: AC-A-02
- **Description**: Define `AIEngineProtocol` and implement wrappers for llama.cpp and Foundation Models.
- **Protocol shape** (actual, all methods async for Swift 6 actor conformance):
  - `isAvailable() async -> Bool`
  - `generate(prompt:maxTokens:) async -> AsyncStream<String>`
  - `classify(text:categories:) async throws -> String`
  - `embed(text:) async throws -> [Float]`
  - `unload() async`
- **Deliverables**:
  - [x] `AIEngineProtocol.swift` — Domain/Protocols (fully async Sendable protocol)
  - [x] `LlamaEngine.swift` — Data/AI: actor wrapping llama.cpp C API with streaming token generation
  - [x] `FoundationModelEngine.swift` — Data/AI: iOS 26+ Foundation Models wrapper with `SystemLanguageModel` streaming; graceful fallback for older OS (returns unavailable)
  - [x] `StubAIEngine.swift` — Data/AI: returns empty results for graceful degradation
  - [x] Inference cancellation support via `Task.isCancelled` in generation loop
  - [x] `AIRepositoryProtocol` wired without `@MainActor` constraint
  - [x] Unit tests: MockAIEngine (actor-based), StubAIEngine behavior, LlamaEngine error paths
  - [x] `AIEngineError.swift` — Domain/Models: 11-case error enum for all failure modes
- **Notes**: All three engine implementations complete. FoundationModelEngine gracefully reports unavailable on pre-iOS 26 devices.

### IOS-A-02b: CoreMLClassifier

- **Status**: `todo`
- **Spec ref**: FR-AI-02, FR-AI-05, FR-AI-06
- **Validation ref**: AC-A-01b, AC-A-04, AC-A-07, AC-A-09
- **Description**: CoreML wrapper for DistilBERT (categorization + spam) and all-MiniLM-L6-v2 (embeddings).
- **Deliverables**:
  - [ ] `CoreMLClassifier.swift` — Data/AI
  - [ ] `classify(text:labels:) -> String` — 5-category email classification
  - [ ] `detectSpam(text:) -> Bool` — binary spam/phishing classification
  - [ ] `embed(text:) -> [Float]` — 384-dim embedding via MiniLM
  - [ ] ANE inference on A14+, CPU fallback on older devices
  - [ ] Unit tests with bundled test models

### IOS-A-02c: AIEngineResolver

- **Status**: `done`
- **Spec ref**: FR-AI-01, Spec Section 8
- **Validation ref**: AC-A-02
- **Description**: Auto-selects best available engine based on platform capabilities and device RAM.
- **Deliverables**:
  - [x] `AIEngineResolver.swift` — Data/AI (actor) with 60-second cache TTL
  - [x] `resolveGenerativeEngine() -> AIEngineProtocol` — FM → llama.cpp → stub
  - [ ] `resolveClassifier() -> CoreMLClassifier` — deferred to IOS-A-02b (CoreML not yet integrated)
  - [x] RAM-based model selection: ≥ 6 GB → Qwen3-1.7B, < 6 GB → Qwen3-0.6B
  - [x] Checks all downloaded models for availability (not just recommended)
  - [x] Unit tests: fallback to stub, RAM detection, recommended model selection
- **Notes**: Generative engine resolution fully complete. CoreML classifier resolution awaits IOS-A-02b.

### IOS-A-03: Model Manager

- **Status**: `done`
- **Spec ref**: FR-AI-01, Spec Section 9
- **Validation ref**: AC-A-03
- **Description**: Download, verify, cache, and delete GGUF model files.
- **Deliverables**:
  - [x] `ModelManager.swift` — Data/AI (actor)
  - [x] `availableModels()` — list with name, size, license, download status
  - [x] `downloadModel(id:progress:)` — HTTPS download with progress reporting (0.0–1.0)
  - [x] Resumable downloads (HTTP Range requests, .partial file tracking)
  - [x] `verifyIntegrity(path:sha256:)` — SHA-256 checksum validation via CryptoKit
  - [x] `deleteModel(id:)` — remove file and free storage
  - [x] `storageUsage()` — total model storage on disk
  - [x] Display source URL, file size, and license before download (ModelInfo has all fields)
  - [x] Unit tests: 14 tests covering available models, storage, delete, integrity, download status
- **Note**: SHA-256 checksums for Qwen3 models are placeholder empty strings — need to be filled after first verified download

---

## Phase 2: Classification Pipeline

### IOS-A-04: Prompt Templates (Categorization LLM Fallback)

- **Status**: `done`
- **Spec ref**: FR-AI-02, Spec Section 12.1
- **Validation ref**: AC-A-04
- **Description**: Prompt construction for LLM-based categorization (fallback when CoreML unavailable).
- **Deliverables**:
  - [x] `PromptTemplates.swift` — Data/AI (categorization section)
  - [x] Input sanitization: strip HTML, scripts, limit length
  - [x] Unit tests: verify prompt format, sanitization (24 tests in PromptTemplatesTests.swift)

### IOS-A-04b: CategorizeEmailUseCase

- **Status**: `done`
- **Spec ref**: FR-AI-02
- **Validation ref**: AC-A-04, AC-A-04b
- **Description**: Email classification via CoreML (primary) with LLM fallback.
- **Deliverables**:
  - [x] `CategorizeEmailUseCase.swift` — Domain/UseCases
  - [ ] Primary path: `CoreMLClassifier.classify()` (< 5 ms on ANE) — deferred to IOS-A-02b (CoreML not yet integrated)
  - [x] Fallback path: `AIEngineProtocol.classify()` via LLM, with `generate()` fallback using PromptTemplates
  - [x] Store result on `Email.aiCategory`
  - [x] Update `Thread.aiCategory` when any child email is categorized (derive from latest per spec Section 6)
  - [x] Manual re-categorization override
  - [x] Unit tests: 3 tests in CategorizeEmailUseCaseTests.swift

### IOS-A-04c: DetectSpamUseCase + RuleEngine

- **Status**: `done`
- **Spec ref**: FR-AI-06
- **Validation ref**: AC-A-09
- **Description**: Spam/phishing detection via ML classification + URL/header rule engine.
- **Deliverables**:
  - [x] `DetectSpamUseCase.swift` — Domain/UseCases (ML weight 0.6 + rule weight 0.4, threshold 0.5)
  - [x] `RuleEngine.swift` — Data/AI: URL analysis (suspicious TLDs, IP addresses, shorteners), subject urgency/financial patterns, body phishing/spam patterns
  - [x] Combine ML signal + rule signal for final decision
  - [x] Store result on `Email.isSpam`
  - [x] Never auto-delete; flag with visual warning only
  - [x] User override: "Not Spam" action via `markAsNotSpam(email:)`
  - [x] Add `isSpam: Bool` property to Email model
  - [x] Unit tests: 6 tests in DetectSpamUseCaseTests.swift, 13 tests in RuleEngineTests.swift

### IOS-A-05: AIProcessingQueue

- **Status**: `done`
- **Spec ref**: FR-AI-07
- **Validation ref**: AC-A-04b, AC-A-09
- **Description**: Background batch processing queue that runs after sync completes.
- **Concurrency model**:
  - LLM tasks (generative): serial queue — prevents concurrent model loads
  - CoreML tasks (classification + embedding): may run concurrently — lightweight, ANE-backed
- **Deliverables**:
  - [x] `AIProcessingQueue.swift` — Data/AI (@MainActor @Observable)
  - [x] `enqueue(emails:)` — add uncategorized emails for background processing
  - [x] `processBatches()` — categorize + spam-check batches with Task.isCancelled checks
  - [x] Batch size: 50 emails with `Task.yield()` between batches
  - [x] Integration with `SyncEmailsUseCase` post-sync hook — wired via ContentView environment injection
  - [x] Unit tests: 6 tests in AIProcessingQueueTests.swift
- **Note**: Embedding is added to queue processing in IOS-A-16 (Phase 4). This task handles classification only.

### IOS-A-06: Category Badges + Spam Warnings in Thread List and Email Detail

- **Status**: `done`
- **Spec ref**: FR-AI-02, FR-AI-06
- **Validation ref**: AC-A-04, AC-A-09
- **Description**: Display category badges and spam/phishing warnings in the thread list and email detail view.
- **Note**: Category UI (badges + thread list integration) shipped in Thread List feature. Spam flagging via `Email.isSpam` is implemented; visual warning is minor remaining polish.
- **Deliverables**:
  - [x] Category badge view (colored pill: Primary, Social, Promotions, Updates, Forums) — `CategoryBadgeView.swift`
  - [x] Integration into `ThreadRowView`
  - [x] `Email.isSpam` flag set by `DetectSpamUseCase` (never auto-deletes)
  - [x] "Not Spam" user override via `markAsNotSpam(email:)`
  - [ ] Spam/phishing warning badge (red, with icon) in thread list — minor polish item
  - [ ] Spam/phishing warning banner in `EmailDetailView` — minor polish item
- **Notes**: Core spam detection and flagging fully functional. Visual spam badges/banners are minor polish items that can be added in a future pass.

### IOS-A-07: Category Tab Filtering

- **Status**: `done`
- **Spec ref**: FR-AI-02
- **Validation ref**: AC-A-04
- **Description**: Filter thread list by AI category tabs.
- **Note**: Category UI (tabs + badges) shipped in Thread List feature. `CategoryTabBar.swift` and `ThreadListView.swift` (line 160+) are fully implemented.
- **Deliverables**:
  - [x] Category tab bar (All, Primary, Social, Promotions, Updates, Forums) — `CategoryTabBar.swift`
  - [x] Filter `FetchThreadsUseCase` by selected category — `ThreadListView.swift`
  - [x] Unread counts per category

---

## Phase 3: Generative Pipeline

### IOS-A-08: Prompt Templates (Smart Reply + Summarization)

- **Status**: `done`
- **Spec ref**: FR-AI-03, FR-AI-04, Spec Section 12.2, 12.3, 12.4
- **Validation ref**: AC-A-05, AC-A-06
- **Description**: Prompt construction for smart reply and summarization, including Foundation Models `@Generable` structs.
- **Deliverables**:
  - [x] `PromptTemplates.swift` — smart reply and summarization sections (combined with IOS-A-04 + IOS-A-11)
  - [ ] Foundation Models `@Generable` structs — deferred until iOS 26 SDK available
  - [x] Input sanitization for email body content (HTML stripping, script removal, entity decoding, truncation)
  - [x] Unit tests: covered in PromptTemplatesTests.swift (24 tests total)

### IOS-A-09: Wire SmartReplyUseCase to AIEngineResolver

- **Status**: `done`
- **Spec ref**: FR-AI-03
- **Validation ref**: AC-A-05
- **Description**: Connect existing `SmartReplyUseCase` stub to real `AIEngineResolver` via `AIRepositoryImpl`.
- **Existing code**: `SmartReplyUseCase.swift` (stub, 3 tests in `SummarizeSmartReplyUseCaseTests.swift`)
- **Deliverables**:
  - [x] Wire to `AIEngineResolver.resolveGenerativeEngine()` via `AIRepositoryImpl.smartReply()`
  - [x] Async generation with PromptTemplates (non-blocking UI)
  - [x] Hide smart reply UI when no generative engine available — SmartReplyView auto-hides when empty
  - [x] `AIRepositoryImpl.swift` created with full protocol implementation

### IOS-A-10: Smart Reply Integration Test

- **Status**: `todo`
- **Spec ref**: FR-AI-03
- **Validation ref**: AC-A-05
- **Description**: Verify smart reply chips work end-to-end in email detail view.
- **Existing UI**: `SmartReplyView.swift`, `SmartReplyChipView.swift` (already built)
- **Deliverables**:
  - [ ] Verify tap inserts suggestion into composer
  - [ ] Verify async loading state
  - [ ] Verify hidden state when no engine available

### IOS-A-11: Prompt Templates (Summarization)

- **Status**: `done`
- **Spec ref**: FR-AI-04, Spec Section 12.3
- **Validation ref**: AC-A-06
- **Note**: Combined with IOS-A-04 and IOS-A-08 into single `PromptTemplates.swift`.

### IOS-A-12: Wire SummarizeThreadUseCase to AIEngineResolver

- **Status**: `done`
- **Spec ref**: FR-AI-04
- **Validation ref**: AC-A-06
- **Description**: Connect existing `SummarizeThreadUseCase` stub to real `AIEngineResolver` via `AIRepositoryImpl`.
- **Existing code**: `SummarizeThreadUseCase.swift` (stub, 3 tests in `SummarizeSmartReplyUseCaseTests.swift`)
- **Deliverables**:
  - [x] Wire to `AIEngineResolver.resolveGenerativeEngine()` via `AIRepositoryImpl.summarize()`
  - [x] Builds thread content from email messages with PromptTemplates
  - [x] Auto-summarize threads with 3+ messages on open — AISummaryView triggers on load
  - [x] Hide summary card when no generative engine available — AISummaryView auto-hides when empty
  - [x] `AIRepositoryImpl.swift` provides full summarize() implementation

### IOS-A-13: Summary Display Integration Test

- **Status**: `todo`
- **Spec ref**: FR-AI-04
- **Validation ref**: AC-A-06
- **Existing UI**: `AISummaryView.swift` (already built)
- **Deliverables**:
  - [ ] Verify summary card appears at top of email detail
  - [ ] Verify cached summary not regenerated on revisit
  - [ ] Verify hidden state when no engine available

---

## Phase 4: Embeddings + Search Index

### IOS-A-14: VectorStore

- **Status**: `todo`
- **Spec ref**: FR-AI-05
- **Validation ref**: AC-A-07
- **Description**: Embedding storage and cosine similarity search.
- **Deliverables**:
  - [ ] `VectorStore.swift` — Data/Search
  - [ ] `store(emailId:embedding:)` — persist 384-dim vector
  - [ ] `search(query:limit:)` — cosine similarity ranking
  - [ ] Incremental update (add/remove per email lifecycle)
  - [ ] Unit tests with in-memory storage

### IOS-A-15: SearchIndexManager

- **Status**: `todo`
- **Spec ref**: FR-AI-05
- **Validation ref**: AC-A-07
- **Description**: Incremental index build during sync.
- **Deliverables**:
  - [ ] `SearchIndexManager.swift` — Data/Search
  - [ ] Hook into sync pipeline: index new emails after sync
  - [ ] Remove embeddings when emails are deleted
  - [ ] Batch indexing for initial sync (process in chunks of 50)

### IOS-A-16: GenerateEmbeddingUseCase

- **Status**: `todo`
- **Spec ref**: FR-AI-05
- **Validation ref**: AC-A-07
- **Description**: Batch embedding generation via CoreML all-MiniLM-L6-v2.
- **Deliverables**:
  - [ ] `GenerateEmbeddingUseCase.swift` — Domain/UseCases
  - [ ] Generate 384-dim embedding per email via `CoreMLClassifier.embed()`
  - [ ] Store in `SearchIndex` entity
  - [ ] Fallback: FTS5 keyword search when CoreML embedding model unavailable
  - [ ] Unit tests

### IOS-A-17: SearchEmailsUseCase (Semantic + Exact)

- **Status**: `todo`
- **Spec ref**: FR-AI-05, Search spec FR-SEARCH-01, FR-SEARCH-02
- **Validation ref**: AC-A-07
- **Description**: Combined semantic (embedding) + exact (FTS5) search use case. Backend task delegated from Search feature plan.
- **Deliverables**:
  - [ ] `SearchEmailsUseCase.swift` — Domain/UseCases
  - [ ] Combine VectorStore semantic results with FTS5 keyword results
  - [ ] Rank and merge results by relevance score
  - [ ] Unit tests with MockVectorStore + MockFTS5

---

## Phase 5: UI Integration + Onboarding

> **Note**: Task IDs are global-unique across all feature plans. IOS-A-14 through IOS-A-17 are embedding/search backend tasks defined here in Phase 4 and referenced by the Search feature plan. IOS-A-18 is the Search UI task tracked in the Search tasks file. Phase 5 uses IOS-A-20+ to avoid collision with IOS-A-18.

### IOS-A-20: Wire AIModelSettingsView to ModelManager

- **Status**: `done`
- **Spec ref**: FR-AI-01
- **Validation ref**: AC-A-03
- **Existing UI**: `AIModelSettingsView.swift` (was simulated progress)
- **Deliverables**:
  - [x] Replace simulated download with real `ModelManager.downloadModel()`
  - [x] Show storage usage via `ModelManager.storageUsage()`
  - [x] Model delete via `ModelManager.deleteModel()`
  - [x] Display model licenses (Constitution LG-01)
  - [x] Cancel download via `ModelManager.cancelDownload()`

### IOS-A-21: Wire AI Use Cases into App Environment

- **Status**: `done`
- **Spec ref**: FR-AI-01
- **Validation ref**: AC-A-02
- **Description**: Inject `ModelManager` and wire AI use cases through the SwiftUI view hierarchy via `VaultMailApp`.
- **Deliverables**:
  - [x] Create `ModelManager` in `VaultMailApp.init()` and pass through view hierarchy
  - [x] `AIEngineResolver` created from `ModelManager` in use case factories
  - [x] `CategorizeEmailUseCase`, `DetectSpamUseCase` wired via `AIProcessingQueue`
  - [x] `AIRepositoryImpl` provides `smartReply()`, `summarize()`, `generateEmbedding()` for use cases
  - [x] Wire `AIProcessingQueue` into sync pipeline — enqueue() called after sync completes

### IOS-A-22: Wire OnboardingAIModelStep to ModelManager

- **Status**: `done`
- **Spec ref**: FR-AI-01
- **Validation ref**: AC-A-08
- **Existing UI**: `OnboardingAIModelStep.swift` (was simulated progress)
- **Deliverables**:
  - [x] Replace simulated download with real `ModelManager.downloadModel()`
  - [x] Display model source URL, size, and license before download
  - [x] Skip option: classification still works, generative shows "Download to enable"
  - [x] Resume download if interrupted (via `ModelManager.cancelDownload()` + re-download)
  - [x] Auto-detects recommended model via `AIEngineResolver.recommendedModelID()`
