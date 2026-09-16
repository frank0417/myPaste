# Logic Mirror Tests

These Node tests mirror Swift rules so CI / Linux agents can validate logic without Xcode.

```bash
node Paste/PasteTests/content_type_detector.test.mjs
node Paste/PasteTests/hybrid_search.test.mjs
node Paste/PasteTests/hotkey_shortcut.test.mjs
node Paste/PasteTests/screenshot_editor.test.mjs
node Paste/PasteTests/screenshot_service.test.mjs
node Paste/PasteTests/text_recognizer.test.mjs
node Paste/PasteTests/favorites_retention.test.mjs
node Paste/PasteTests/performance_cache.test.mjs
node Paste/PasteTests/memory_budget.test.mjs
node Paste/PasteTests/settings_window.test.mjs
```

| Test | Mirrors |
|------|---------|
| `content_type_detector.test.mjs` | `ContentTypeDetector` classification and preview titles |
| `hybrid_search.test.mjs` | `KeywordScorer` tokenizing/scoring and `HybridSearch.fuse` ranking |
| `hotkey_shortcut.test.mjs` | `HotKeyShortcut` validation/display and `GlobalHotKeyManager.apply` fallback |
| `screenshot_editor.test.mjs` | `ScreenshotLayout` selection/handle/toolbar geometry and crop math |
| `screenshot_service.test.mjs` | `ScreenshotMode` screencapture fallback flags and `ScreenshotService` outcome/payload/pasteboard rules |
| `text_recognizer.test.mjs` | `TextRecognizer` reading-order assembly, CJK joining and character counting |
| `favorites_retention.test.mjs` | `RetentionPolicy` expiry/sweep rules and `FavoriteTagCatalog` category normalization |
| `performance_cache.test.mjs` | `KeywordScorer` field memoization, excess-only history trim, capture coalescing |
| `memory_budget.test.mjs` | Image storage/cache budgets, lazy embeddings, panel unload, TIFF compaction walk |
| `settings_window.test.mjs` | Panel overflow uses NSMenu; Settings is an owned window, not `showSettingsWindow:` |
| `panel_typography.test.mjs` | Shelf type ramp and PanelL10n zh-Hans / zh-Hant / en chrome |
| `chrome_l10n.test.mjs` | Overlay HUD, menus, settings, and preview chrome share one language per locale |
