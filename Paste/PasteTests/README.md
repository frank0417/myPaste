# Logic Mirror Tests

These Node tests mirror Swift rules so CI / Linux agents can validate logic without Xcode.

```bash
node Paste/PasteTests/content_type_detector.test.mjs
node Paste/PasteTests/hybrid_search.test.mjs
node Paste/PasteTests/hotkey_shortcut.test.mjs
node Paste/PasteTests/screenshot_service.test.mjs
node Paste/PasteTests/text_recognizer.test.mjs
node Paste/PasteTests/favorites_retention.test.mjs
```

| Test | Mirrors |
|------|---------|
| `content_type_detector.test.mjs` | `ContentTypeDetector` classification and preview titles |
| `hybrid_search.test.mjs` | `KeywordScorer` tokenizing/scoring and `HybridSearch.fuse` ranking |
| `hotkey_shortcut.test.mjs` | `HotKeyShortcut` validation/display and `GlobalHotKeyManager.apply` fallback |
| `screenshot_service.test.mjs` | `ScreenshotMode` screencapture flags and `ScreenshotService` outcome/payload/pasteboard rules |
| `text_recognizer.test.mjs` | `TextRecognizer` reading-order assembly, CJK joining and character counting |
| `favorites_retention.test.mjs` | `RetentionPolicy` expiry/sweep rules and `FavoriteTagCatalog` category normalization |
