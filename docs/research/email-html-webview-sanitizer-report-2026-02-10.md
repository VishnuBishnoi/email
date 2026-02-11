# Email HTML Rendering in Mobile WebView: Research + Implementation Report

Date: February 10, 2026  
Project: VaultMail (`/Users/vishnudutt/email`)

## Scope
Investigate best practices for rendering untrusted email HTML in mobile WebViews, compare common industry approaches, and harden this app's HTML sanitizer/render pipeline.

## Key Findings
1. Remote content should be blocked by default, with user-controlled opt-in per message/sender.
2. HTML sanitization must include URI scheme controls and bypass-resistant normalization (entity/whitespace obfuscation).
3. CSP should be used as defense-in-depth to constrain resource loading even after sanitization.
4. WebView execution environment should stay constrained: JavaScript disabled, non-persistent data store, external browser for links.

## Industry Patterns Observed
- Thunderbird: blocks remote content by default; supports trusted sender exceptions.
- Apple Mail: privacy-first remote-content controls (including privacy protection behavior).
- Microsoft Defender Safe Links: industry pattern for link rewriting/click-time evaluation.
- OWASP/DOMPurify guidance: sanitize untrusted HTML, avoid sanitizer bypass via mutation/obfuscation.

## Changes Implemented

### 1) Sanitizer hardening
File: `/Users/vishnudutt/email/VaultMailPackage/Sources/VaultMailFeature/Domain/Utilities/HTMLSanitizer.swift`

- Added stripping of high-risk container tags:
  - `svg`, `math`, `template`
- Removed `srcset` attributes to prevent alternate remote image fetch paths.
- Removed inline `style` attributes when they include `url(...)` or `@import`.
- Expanded URI allow-list enforcement:
  - Supports quoted and unquoted attributes.
  - Canonicalizes URI values before validation (entity decoding + control/whitespace stripping).
  - Blocks obfuscated schemes such as `jav&#x61;script:`.
- Updated CSP generation in `injectDynamicTypeCSS(...)`:
  - Default: `img-src data:`
  - Remote images enabled: `img-src http: https: data:`

### 2) WebView render pipeline fix
File: `/Users/vishnudutt/email/VaultMailPackage/Sources/VaultMailFeature/Presentation/EmailDetail/HTMLEmailView.swift`

- Removed duplicate HTML wrapping/styling stage.
- `HTMLEmailView` now loads the already-built full HTML document directly.

### 3) Correct remote-image policy wiring
File: `/Users/vishnudutt/email/VaultMailPackage/Sources/VaultMailFeature/Presentation/EmailDetail/MessageBubbleView.swift`

- Passed `allowRemoteImages: shouldLoadRemote` into final HTML document/CSP generation.

### 4) Regression test additions
File: `/Users/vishnudutt/email/VaultMailPackage/Tests/VaultMailFeatureTests/HTMLSanitizerTests.swift`

Added tests for:
- Unquoted `javascript:` URI blocking.
- Entity-obfuscated `javascript:` URI blocking.
- `srcset` stripping.
- Inline style URL-load stripping.
- CSP behavior for remote-images disabled/enabled.

## Verification
Command run:
- `swift test --filter HTMLSanitizer` (in `/Users/vishnudutt/email/VaultMailPackage`)

Result:
- Passed: 37 tests
- Failures: 0

## Security/Behavior Impact Summary
- Improves resistance against common sanitizer bypass patterns.
- Reduces privacy leakage from non-`img src` remote fetch vectors.
- Aligns CSP behavior with user choice on remote image loading.
- Removes duplicate HTML wrapping in rendering path, simplifying and reducing transformation risk.

## References
- OWASP XSS Prevention Cheat Sheet: https://cheatsheetseries.owasp.org/cheatsheets/Cross_Site_Scripting_Prevention_Cheat_Sheet.html
- DOMPurify: https://github.com/cure53/DOMPurify
- MDN CSP `img-src`: https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Content-Security-Policy/img-src
- Thunderbird remote content behavior: https://support.mozilla.org/en-US/kb/remote-content-in-messages
- Apple Mail privacy controls: https://support.apple.com/en-afri/guide/mail/mlhlae4a4fe6/mac
- Apple Mail privacy protection details: https://support.apple.com/my-mm/guide/mail/mlhl03be2866/mac
- Microsoft Defender Safe Links policy: https://learn.microsoft.com/en-us/defender-office-365/safe-links-policies-configure
