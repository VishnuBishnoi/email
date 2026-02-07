---
title: "AI Features — iOS/macOS Task Breakdown"
platform: iOS, macOS
plan-ref: docs/features/ai-features/ios-macos/plan.md
version: "1.0.0"
status: draft
updated: 2025-02-07
---

# AI Features — iOS/macOS Task Breakdown

> Each task references its plan ID, spec section, and acceptance criteria. Status values: `todo`, `in-progress`, `done`, `blocked`.

---

### IOS-A-01: llama.cpp Integration

- **Status**: `todo`
- **Spec ref**: AI Features spec, FR-AI-01
- **Validation ref**: AC-A-01
- **Description**: Integrate llama.cpp as SPM dependency. Verify compilation on iOS and macOS.
- **Deliverables**:
  - [ ] SPM package dependency added
  - [ ] Swift bridging configured
  - [ ] Build succeeds on both iOS and macOS targets
  - [ ] Basic smoke test (load model, run simple inference)

### IOS-A-02: Llama Engine Wrapper

- **Status**: `todo`
- **Spec ref**: AI Features spec, FR-AI-01
- **Validation ref**: AC-A-02
- **Description**: Swift wrapper around llama.cpp C API exposing protocol-based interface.
- **Deliverables**:
  - [ ] `LlamaEngine.swift` — load model, run inference, unload model
  - [ ] Protocol-based interface (`AIEngineProtocol`)
  - [ ] Thread-safe inference execution
  - [ ] Memory management (model loading/unloading)
  - [ ] Inference cancellation support
  - [ ] Unit tests with small test model

### IOS-A-03: Model Manager

- **Status**: `todo`
- **Spec ref**: AI Features spec, FR-AI-01
- **Validation ref**: AC-A-03
- **Description**: Download, cache, and manage GGUF model files.
- **Deliverables**:
  - [ ] `ModelManager.swift` — download, verify, cache, delete
  - [ ] Download progress reporting
  - [ ] Download cancellation
  - [ ] Storage usage reporting
  - [ ] Model integrity verification (checksum)
  - [ ] Graceful degradation when no model available

### IOS-A-04 to IOS-A-07: Categorization Pipeline

- **Status**: `todo`
- **Spec ref**: AI Features spec, FR-AI-02
- **Validation ref**: AC-A-04
- **Description**: End-to-end email categorization from prompt to UI.
- **Deliverables**:
  - [ ] Prompt templates for categorization
  - [ ] `CategorizeEmailUseCase.swift` — single and batch
  - [ ] `AIProcessingQueue.swift` — background batch processing
  - [ ] Category badge in thread row
  - [ ] Category tab filtering in thread list
  - [ ] Manual re-categorization override
  - [ ] Unit tests for prompt parsing and categorization logic

### IOS-A-08 to IOS-A-10: Smart Reply Pipeline

- **Status**: `todo`
- **Spec ref**: AI Features spec, FR-AI-03
- **Validation ref**: AC-A-05
- **Description**: End-to-end smart reply from prompt to UI.
- **Deliverables**:
  - [ ] Prompt templates for smart reply generation
  - [ ] `SmartReplyUseCase.swift` — generate up to 3 suggestions
  - [ ] Smart reply chip UI in email detail
  - [ ] Tap to insert into composer
  - [ ] Async generation (non-blocking UI)
  - [ ] Unit tests for prompt construction and response parsing

### IOS-A-11 to IOS-A-13: Summarization Pipeline

- **Status**: `todo`
- **Spec ref**: AI Features spec, FR-AI-04
- **Validation ref**: AC-A-06
- **Description**: End-to-end thread summarization from prompt to UI.
- **Deliverables**:
  - [ ] Prompt templates for summarization
  - [ ] `SummarizeThreadUseCase.swift`
  - [ ] Summary display at top of email detail
  - [ ] On-demand trigger + auto for 3+ message threads
  - [ ] Summary caching
  - [ ] Unit tests

### IOS-A-19: AI Model Download in Onboarding

- **Status**: `todo`
- **Spec ref**: AI Features spec, FR-AI-01; Settings & Onboarding spec, FR-OB-01
- **Validation ref**: AC-A-08
- **Description**: Integrate model download step into onboarding flow.
- **Deliverables**:
  - [ ] Model download screen with progress
  - [ ] Skip option
  - [ ] Resume download if interrupted
  - [ ] Size disclosure before download
