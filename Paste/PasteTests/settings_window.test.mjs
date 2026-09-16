// Locks the "快捷键设置…" wiring so CI / Linux agents can catch a regression
// without Xcode. Two failures stacked here in 1.5.6:
//
// 1. SwiftUI `Menu` inside the non-activating shelf NSPanel highlighted items
//    but never ran their actions — clicking "快捷键设置…" did nothing.
// 2. `NSApp.sendAction(showSettingsWindow:)` is a no-op for an LSUIElement
//    accessory app, so even a fired action never produced a window.

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
  /popPanelOverflowMenu\(pasteSelected:/.test(topBar),
  "ellipsis button pops an AppKit overflow menu"
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
  /func popPanelOverflowMenu\(pasteSelected:/.test(controller),
  "StatusItemController pops the panel overflow menu"
);
assertTrue(
  /addMenuItem\(menu, title: "快捷键设置…"/.test(controller),
  "overflow NSMenu includes 快捷键设置…"
);
assertTrue(
  /menu\.addItem\(withTitle: "快捷键设置…"/.test(controller),
  "status-item menu still includes 快捷键设置…"
);
assertTrue(
  /@objc private func menuOpenHotkeySettings\(\)\s*\{\s*openSettings\(tab: \.hotkeys\)/.test(controller),
  "快捷键设置… lands on the hotkeys tab"
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
  "openSettings still accepts a tab so 快捷键设置… can deep-link"
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
  /tabItem \{ Label\("快捷键"/.test(settings),
  "SettingsView still has a 快捷键 tab"
);
assertTrue(
  /\.tag\(AppState\.SettingsTab\.hotkeys\)/.test(settings),
  "快捷键 tab is tagged so menus can select it"
);

if (failed > 0) {
  console.error(`\n${failed} test(s) failed`);
  process.exit(1);
}
console.log("\nAll settings window tests passed.");
