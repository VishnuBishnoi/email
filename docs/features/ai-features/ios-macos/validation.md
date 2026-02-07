---
title: "AI Features — iOS/macOS Validation"
spec-ref: docs/features/ai-features/spec.md
plan-refs:
  - docs/features/ai-features/ios-macos/plan.md
  - docs/features/ai-features/ios-macos/tasks.md
version: "1.0.0"
status: draft
last-validated: null
---

# AI Features — Validation: Acceptance Criteria & Test Plan

> The key words **MUST**, **MUST NOT**, **REQUIRED**, **SHALL**, **SHALL NOT**, **SHOULD**, **SHOULD NOT**, **RECOMMENDED**, **MAY**, and **OPTIONAL** in this document are to be interpreted as described in [RFC 2119](https://www.ietf.org/rfc/rfc2119.txt).

---

## 1. Traceability Matrix

| Req ID | Requirement Summary | Keyword | Test Case IDs | Platform | Status |
|--------|-------------------|---------|---------------|----------|--------|
| FR-AI-01 | Engine requirements | MUST | AC-A-01, AC-A-02, AC-A-03 | Both | — |
| FR-AI-02 | Email categorization | MUST | AC-A-04, AC-A-04b | Both | — |
| FR-AI-03 | Smart reply | MUST | AC-A-05 | Both | — |
| FR-AI-04 | Thread summarization | MUST | AC-A-06 | Both | — |
| FR-AI-05 | Semantic search embeddings | MUST | AC-A-07 (Search) | Both | — |
| G-04 | AI categorization, smart reply, summarization | MUST | AC-A-04, AC-A-05, AC-A-06 | Both | — |

---

## 2. Acceptance Criteria

---

**AC-A-01**: llama.cpp Integration

- **Given**: The llama.cpp SPM package is added
- **When**: The project is built for iOS and macOS
- **Then**: The build **MUST** succeed on both platforms without errors
  AND a small GGUF model **MUST** load successfully
  AND a simple text generation prompt **MUST** return a coherent response
- **Priority**: Critical

---

**AC-A-02**: AI Engine Abstraction

- **Given**: An `AIEngineProtocol` and its llama.cpp implementation
- **When**: The protocol methods are called
- **Then**: `isModelAvailable()` **MUST** return `false` if no model is downloaded
  AND `loadModel(path:)` **MUST** load a GGUF model into memory
  AND `generate(prompt:)` **MUST** return generated text
  AND `unloadModel()` **MUST** free model memory
  AND the protocol **MUST** be implementable by an alternative engine without changing callers
- **Priority**: Critical

---

**AC-A-03**: Model Manager

- **Given**: A `ModelManager` instance with no models downloaded
- **When**: Model management operations are performed
- **Then**: `availableModels()` **MUST** list models with name, size, and download status
  AND `downloadModel(id:)` **MUST** download the GGUF file with progress reporting (0-100%)
  AND download **MUST** be cancellable
  AND `deleteModel(id:)` **MUST** remove the file and free storage
  AND `storageUsage()` **MUST** report total model storage accurately
- **Priority**: High

---

**AC-A-04**: Email Categorization

- **Given**: A synced email with subject "50% off shoes today only!"
- **When**: The categorization use case processes the email
- **Then**: The email **MUST** be categorized as `promotions`
  AND the category **MUST** be stored on the email entity
  AND the thread list **MUST** show the correct category badge
  AND the Promotions tab **MUST** include this thread
  AND manual re-categorization to `primary` **MUST** update the stored category

**AC-A-04b**: Batch Categorization

- **Given**: 50 uncategorized emails after sync
- **When**: Background categorization runs
- **Then**: All 50 emails **MUST** be categorized within 60 seconds
  AND the UI **MUST NOT** freeze during processing
  AND results **MUST** appear progressively in the thread list
- **Priority**: High

---

**AC-A-05**: Smart Reply

- **Given**: An email asking "Can you meet at 3pm tomorrow?"
- **When**: The smart reply use case is invoked
- **Then**: Up to 3 reply suggestions **MUST** be returned
  AND at least one suggestion **SHOULD** be affirmative
  AND at least one suggestion **SHOULD** be declining or alternative
  AND generation **MUST** complete within 3 seconds
  AND the UI **MUST NOT** block during generation
  AND tapping a suggestion **MUST** insert it into the composer body
- **Priority**: High

---

**AC-A-06**: Thread Summarization

- **Given**: A thread with 5 messages discussing a project deadline
- **When**: The summarize action is triggered
- **Then**: A summary of 2-4 sentences **MUST** be generated
  AND the summary **MUST** capture the key decision or action items
  AND the summary **MUST** be displayed at the top of the email detail
  AND the summary **MUST** be cached (not regenerated on revisit)
  AND threads with 3+ messages **SHOULD** auto-summarize on open
- **Priority**: High

---

**AC-A-08**: AI Onboarding

- **Given**: The user is on the AI model download step in onboarding
- **When**: The user taps "Download"
- **Then**: The model download **MUST** start with a visible progress bar
  AND the user **MUST** be able to skip without downloading
  AND if skipped, all AI features **MUST** show a "Download model to enable" state
  AND after download completes, AI features **MUST** begin working
- **Priority**: Medium

---

## 3. Edge Cases

| # | Scenario | Expected Behavior |
|---|---------|-------------------|
| E-04 | AI model file corrupted | Model fails to load; error displayed; user can re-download |
| E-09 | App killed during AI inference | Model state cleaned up on next launch; no corrupt cache |

---

## 4. Performance Validation

| Metric | Target | Hard Limit | Measurement Method | Failure Threshold |
|--------|--------|------------|--------------------|-------------------|
| AI categorization (single) | < 500ms | 2s | Wall clock on min-spec device | Fails if > 2s |
| AI batch categorization (100) | < 30s | 60s | Wall clock for full batch | Fails if > 60s |
| Smart reply generation | < 2s | 3s | Wall clock for 3 suggestions | Fails if > 3s |
| Embedding generation (100) | < 60s | — | Background processing time | — |
| Memory during AI | < 500MB above baseline | — | Instruments Allocations | Fails if > 500MB above |

---

## 5. Device Test Matrix

Refer to Foundation validation Section 5 for shared device test matrix.

---

## 6. Sign-Off

| Reviewer | Role | Date | Status |
|----------|------|------|--------|
| — | Spec Author | — | — |
| — | QA Lead | — | — |
| — | Engineering Lead | — | — |
