// Locks every button and hint onto zh-Hans / zh-Hant / en so one locale cannot
// mix overlay English with a Chinese HUD, or a CJK glyph on an English toolbar.

import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../Paste");
const preview = fs.readFileSync(path.resolve(root, "../preview/index.html"), "utf8");

function read(rel) {
  return fs.readFileSync(path.join(root, rel), "utf8");
}

let failed = 0;
function assertTrue(cond, name) {
  if (!cond) {
    console.error(`FAIL ${name}`);
    failed += 1;
  } else {
    console.log(`PASS ${name}`);
  }
}

const l10n = read("Utilities/PanelL10n.swift");
const editor = read("Views/ScreenshotEditor.swift");
const service = read("Services/ScreenshotService.swift");
const settings = read("Views/SettingsView.swift");
const controller = read("Utilities/StatusItemController.swift");
const content = read("Views/ContentView.swift");
const hotkey = read("Utilities/HotKey.swift");
const store = read("Services/ClipboardStore.swift");
const previewPane = read("Views/PreviewPane.swift");
const history = read("Views/ClipboardHistoryPane.swift");
const row = read("Views/ClipboardItemRow.swift");

assertTrue(/case zhHans/.test(l10n) && /case zhHant/.test(l10n) && /case en/.test(l10n), "panel ships three languages");
assertTrue(editor.includes('.recognizeText: "Recognize text"'), "overlay OCR hint is English in English");
assertTrue(/hant: "辨識文字"/.test(l10n), "panel OCR uses Traditional Chinese");
assertTrue(/en: "Read"/.test(l10n), "panel OCR chip stays a short English verb");

for (const key of [
  "imageCopied", "modeRegion", "textCapture", "permissionTitle", "savedToDownloads", "ocrEmpty"
]) {
  assertTrue(editor.split(`.${key}:`).length >= 4, `ScreenshotL10n.${key} exists in all three languages`);
}

assertTrue(/ScreenshotL10n\.string\(\.imageCopied\)/.test(service), "HUD copied-image uses ScreenshotL10n");
assertTrue(/ScreenshotL10n\.string\(\.ocrEmpty\)/.test(service), "HUD empty OCR uses ScreenshotL10n");
assertTrue(/ScreenshotL10n\.modeTitle/.test(service), "capture-mode titles use ScreenshotL10n");
assertTrue(/ScreenshotL10n\.previewTitle/.test(service), "history titles use ScreenshotL10n");
assertTrue(/ScreenshotL10n\.downloadFileName/.test(service), "download names use ScreenshotL10n");
assertTrue(!/detail: "图片已复制"/.test(service), "ScreenshotService no longer hardcodes the copied HUD");
assertTrue(!/return "截取区域"/.test(service), "ScreenshotMode titles are no longer Chinese-only");

assertTrue(/PanelL10n\.openSettings/.test(controller), "overflow Open Settings is localized");
assertTrue(/PanelL10n\.settingsEllipsis/.test(controller), "status Settings… is localized");
assertTrue(/PanelL10n\.captureRegion/.test(controller), "capture-region menu is localized");
assertTrue(/PanelL10n\.pauseMonitoring/.test(controller), "pause/resume monitoring is localized");
assertTrue(/window\.title = PanelL10n\.settings/.test(controller), "settings window title follows the app language");
assertTrue(!/withTitle: "设置…"/.test(controller), "status menu no longer hardcodes 设置…");

assertTrue(/PanelL10n\.settingsTabHotkeys/.test(settings), "settings tabs are localized");
assertTrue(/PanelL10n\.screenshotSettingsHelp/.test(settings), "settings screenshot copy is localized");
assertTrue(/PanelL10n\.restoreAllDefaults/.test(settings), "restore-defaults chip is localized");
assertTrue(!/settingsCard\("快捷键"\)/.test(settings), "settings cards no longer hardcode 快捷键");

assertTrue(/PanelL10n\.hotkeyNeedModifier/.test(hotkey), "hotkey rejection copy is localized");
assertTrue(/PanelL10n\.hotkeyClash/.test(hotkey), "hotkey clash copy is localized");
assertTrue(/PanelL10n\.hotkeyPanel/.test(hotkey), "hotkey row titles are localized");

assertTrue(/PanelL10n\.screenshot/.test(content), "main-window screenshot menu is localized");
assertTrue(/PanelL10n\.modeAndRecognize/.test(content), "recognize-text capture menu is localized");
assertTrue(/PanelL10n\.clearHistoryTitle/.test(content), "clear-history alert is localized");

assertTrue(/ScreenshotL10n\.hudRecognizedMenu/.test(store), "history OCR HUD follows ScreenshotL10n");
assertTrue(/ScreenshotL10n\.stripOCRSuffix/.test(store), "OCR subtitle stripping understands every language");

assertTrue(/PanelL10n\.paste/.test(previewPane) && /PanelL10n\.recognizeText/.test(previewPane), "preview pane actions are localized");
assertTrue(/PanelL10n\.list/.test(history) && /PanelL10n\.recentlyCopied/.test(history), "history pane chrome is localized");
assertTrue(/PanelL10n\.paste/.test(row) && /PanelL10n\.delete/.test(row), "row context menu is localized");

assertTrue(/id="shotOCR"[\s\S]*?>Aa</.test(preview), "English overlay OCR uses a language-neutral Aa glyph");
assertTrue(!/>文</.test(preview), "preview toolbar no longer shows a CJK 文 glyph");
assertTrue(/\.shot-toast \{/.test(preview), "toast CSS selector is intact");
assertTrue(/const UI = \{/.test(preview) && /"zh-Hans":/.test(preview) && /"zh-Hant":/.test(preview) && /en: \{/.test(preview), "preview chrome has three language tables");
assertTrue(/function applyLanguage\(lang\)/.test(preview), "language switch updates all chrome, not only overlay hints");
assertTrue(/data-i18n="simulateShot"/.test(preview), "hero screenshot button is in the chrome table");
assertTrue(/data-i18n="tabHotkeys"/.test(preview), "settings tabs are in the chrome table");
assertTrue(/imageCopied: "Image copied"/.test(preview) && /imageCopied: "图片已复制"/.test(preview) && /imageCopied: "圖片已複製"/.test(preview), "toast copy exists in all three languages");
assertTrue(/recognizeText: "Recognize text"/.test(preview) && /recognizeText: "识别文字"/.test(preview) && /recognizeText: "辨識文字"/.test(preview), "OCR hint exists in all three languages");

function blockAfter(source, marker) {
  const start = source.indexOf(marker);
  if (start < 0) return "";
  const from = source.indexOf("{", start);
  let depth = 0;
  for (let i = from; i < source.length; i += 1) {
    if (source[i] === "{") depth += 1;
    if (source[i] === "}") {
      depth -= 1;
      if (depth === 0) return source.slice(from, i + 1);
    }
  }
  return "";
}

const englishHints = blockAfter(preview.slice(preview.indexOf("const SHOT_HINTS")), "\n      en: {");
const englishUI = blockAfter(preview.slice(preview.indexOf("const UI =")), "\n      en: {");
assertTrue(englishHints.includes("Image copied") && !/[\u4e00-\u9fff]/.test(englishHints), "English overlay hints have no CJK");
assertTrue(englishUI.includes("Simulate screenshot") && !/[\u4e00-\u9fff]/.test(englishUI), "English preview chrome has no CJK");
const hantUI = blockAfter(preview.slice(preview.indexOf("const UI =")), '"zh-Hant": {');
assertTrue(hantUI.includes("模擬截圖") && !hantUI.includes("Simulate screenshot"), "Traditional preview chrome is not mixed with English labels");

if (failed > 0) {
  console.error(`\n${failed} test(s) failed`);
  process.exit(1);
}
console.log("\nAll chrome localization tests passed.");
