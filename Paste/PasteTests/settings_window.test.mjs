// Locks the panel overflow / status menus and the owned Settings window so
// CI / Linux agents can catch a regression without Xcode.
//
// SwiftUI `Menu` inside the non-activating shelf NSPanel highlighted items
// but never ran their actions. `NSApp.sendAction(showSettingsWindow:)` is a
// no-op for an LSUIElement accessory app, so even a fired action never
// produced a window.

import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../Paste");

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

const controller = read("Utilities/StatusItemController.swift");
const panel = read("Views/MenuBarPanel.swift");
const settings = read("Views/SettingsView.swift");
const appState = read("Models/AppState.swift");

const topBarStart = panel.indexOf("private var topBar: some View");
const topBarEnd = panel.indexOf("private var searchRow: some View", topBarStart);
const topBar = panel.slice(topBarStart, topBarEnd);
assertTrue(topBarStart > 0 && topBarEnd > topBarStart, "topBar is defined");

assertTrue(
  /popPanelOverflowMenu\(\)/.test(topBar),
  "ellipsis button pops an AppKit overflow menu"
);
assertTrue(
  !/popPanelOverflowMenu\(pasteSelected:/.test(topBar),
  "overflow menu no longer takes pasteSelected"
);
assertTrue(
  !/Menu\s*\{/.test(topBar),
  "topBar no longer uses SwiftUI Menu (its actions do not fire in the panel)"
);
assertTrue(
  /Image\(systemName: "ellipsis"\)/.test(topBar),
  "overflow control is still the ellipsis button"
);

assertTrue(
  /func popPanelOverflowMenu\(\)/.test(controller),
  "StatusItemController pops the panel overflow menu"
);
assertTrue(
  /addMenuItem\(menu, title: PanelL10n\.openSettings/.test(controller),
  "overflow NSMenu still includes Open Settings"
);
assertTrue(
  /menu\.addItem\(withTitle: PanelL10n\.settingsEllipsis/.test(controller),
  "status-item menu still includes Settings…"
);
assertTrue(
  !/粘贴选中项/.test(controller),
  "overflow NSMenu no longer includes 粘贴选中项"
);
assertTrue(
  !/截取区域并识字/.test(controller),
  "menus no longer include 截取区域并识字（只存文字）"
);
assertTrue(
  !/快捷键设置…/.test(controller),
  "menus no longer include 快捷键设置…"
);
assertTrue(
  !/menuOpenHotkeySettings/.test(controller),
  "hotkey-settings menu action is gone"
);
assertTrue(
  !/menuCaptureRegionOCR/.test(controller),
  "OCR-only capture menu action is gone"
);
assertTrue(
  !/runPanelPasteSelected/.test(controller),
  "paste-selected overflow action is gone"
);
assertTrue(
  /@objc private func menuToggleMonitoring\(\)/.test(controller),
  "pause/resume monitoring remains on the overflow menu"
);

assertTrue(
  /private var settingsWindow: NSWindow\?/.test(controller),
  "settings are hosted in an owned NSWindow"
);
assertTrue(
  /NSHostingController\(rootView: root\)/.test(controller),
  "owned settings window hosts SettingsView"
);
assertTrue(
  /settingsWindowIdentifier = "PasteNestSettings"/.test(controller),
  "owned settings window has a stable identifier"
);
assertTrue(
  !/sendAction\(Selector\(\("showSettingsWindow:"\)\)/.test(controller),
  "openSettings no longer depends on showSettingsWindow: (dead in accessory apps)"
);
assertTrue(
  /func openSettings\(tab: AppState\.SettingsTab\? = nil\)/.test(controller),
  "openSettings still accepts a tab so Settings 修改… can deep-link"
);
assertTrue(
  /presentSettingsWindow\(\)/.test(controller),
  "openSettings presents the owned window"
);

assertTrue(
  /if sender === panel \{[\s\S]*hidePanel\(\)[\s\S]*return false/.test(controller),
  "windowShouldClose only intercepts the shelf panel"
);
assertTrue(
  /func windowShouldClose\([\s\S]*return true/.test(controller),
  "settings window close button is allowed to close"
);

assertTrue(
  /case hotkeys/.test(appState),
  "AppState has a hotkeys settings tab"
);
assertTrue(
  /case \.hotkeys: return PanelL10n\.settingsTabHotkeys/.test(settings),
  "SettingsView still has a Hotkeys tab"
);
assertTrue(/PanelL10n\.settingsTabGeneral/.test(settings), "settings tabs are localized");
assertTrue(/PanelL10n\.listenClipboard/.test(settings), "general preferences are localized");
assertTrue(/PanelL10n\.screenshotSettingsHelp/.test(settings), "screenshot help follows the app language");
assertTrue(/PanelL10n\.restoreAllDefaults/.test(settings), "restore-defaults chip is localized");
assertTrue(!/restoreDefaultsDetail/.test(settings), "restore-defaults card has no detail paragraph");
assertTrue(!/\.disabled\(HotKeyAction/.test(settings), "restore-all is not disabled at factory shortcuts");
assertTrue(
  /PasteTheme\.backgroundGradient/.test(settings),
  "settings use the same warm gradient as the main panel"
);
assertTrue(
  /shelfPill\(\)/.test(settings),
  "settings tabs sit in a shelf pill like the panel nav"
);
assertTrue(
  /titlebarAppearsTransparent = true/.test(controller),
  "settings window chrome is transparent so the panel gradient shows through"
);
assertTrue(
  /setContentSize\(NSSize\(width: 560, height: 560\)\)/.test(controller),
  "settings window is sized for the card layout"
);

if (failed > 0) {
  console.error(`\n${failed} test(s) failed`);
  process.exit(1);
}
console.log("\nAll settings window tests passed.");
