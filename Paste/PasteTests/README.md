# Logic Mirror Tests

These Node tests mirror Swift rules so CI / Linux agents can validate logic without Xcode.

```bash
node Paste/PasteTests/content_type_detector.test.mjs
node Paste/PasteTests/hotkey_shortcut.test.mjs
```

| Test | Mirrors |
|------|---------|
| `content_type_detector.test.mjs` | `ContentTypeDetector` classification and preview titles |
| `hotkey_shortcut.test.mjs` | `HotKeyShortcut` validation/display and `GlobalHotKeyManager.apply` fallback |
