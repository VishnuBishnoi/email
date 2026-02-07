---
title: "Search — iOS/macOS Validation"
spec-ref: docs/features/search/spec.md
plan-refs:
  - docs/features/search/ios-macos/plan.md
  - docs/features/search/ios-macos/tasks.md
version: "1.0.0"
status: draft
last-validated: null
---

# Search — Validation: Acceptance Criteria & Test Plan

> The key words **MUST**, **MUST NOT**, **REQUIRED**, **SHALL**, **SHALL NOT**, **SHOULD**, **SHOULD NOT**, **RECOMMENDED**, **MAY**, and **OPTIONAL** in this document are to be interpreted as described in [RFC 2119](https://www.ietf.org/rfc/rfc2119.txt).

---

## 1. Traceability Matrix

| Req ID | Requirement Summary | Keyword | Test Case IDs | Platform | Status |
|--------|-------------------|---------|---------------|----------|--------|
| FR-SEARCH-01 | Search interface | MUST | AC-A-07 | Both | — |
| FR-SEARCH-02 | Search architecture | MUST | AC-A-07 | Both | — |
| FR-SEARCH-03 | Result ranking | MUST | AC-A-07 | Both | — |
| G-05 | AI semantic search | MUST | AC-A-07 | Both | — |

---

## 2. Acceptance Criteria

---

**AC-A-07**: Semantic Search

- **Given**: 1000 synced and indexed emails, including one about "quarterly budget review"
- **When**: The user searches for "financial planning meeting"
- **Then**: The email about "quarterly budget review" **MUST** appear in search results (semantic match)
  AND results **MUST** be ranked by relevance
  AND first results **MUST** appear within 2 seconds
  AND exact-match filters (sender, date) **MUST** narrow results correctly
  AND search results **MUST** be tappable to navigate to the email detail
- **Priority**: High

---

## 3. Edge Cases

| # | Scenario | Expected Behavior |
|---|---------|-------------------|
| E-11 | Search with no results | Empty state with helpful message; no crash |

---

## 4. Performance Validation

| Metric | Target | Hard Limit | Measurement Method | Failure Threshold |
|--------|--------|------------|--------------------|-------------------|
| Search first results | < 1s | 3s | Time from query submit to first result visible (10K corpus) | Fails if > 3s |

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
