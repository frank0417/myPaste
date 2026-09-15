// Locks the shelf search-field wiring so CI / Linux agents can catch a
// regression without Xcode. The floating panel is a borderless NSPanel;
// unless it overrides canBecomeKey, makeFirstResponder is a no-op and the
// search box cannot accept input. SwiftUI TextField is also unreliable
// there, so the field must be a native NSTextField representable.

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

assertTrue(
  /final class ClipboardShelfPanel:\s*NSPanel/.test(controller),
  "ClipboardShelfPanel subclasses NSPanel"
);
assertTrue(
  /override var canBecomeKey:\s*Bool\s*\{\s*true\s*\}/.test(controller),
  "ClipboardShelfPanel canBecomeKey is true"
);
assertTrue(
  /let panel = ClipboardShelfPanel\(/.test(controller),
  "makePanel constructs ClipboardShelfPanel, not a plain NSPanel"
);
assertTrue(
  !/let panel = NSPanel\(/.test(controller),
  "StatusItemController no longer instantiates a bare NSPanel"
);

assertTrue(
  /PanelSearchField\(/.test(panel),
  "search pill hosts PanelSearchField"
);
assertTrue(
  !/TextField\("搜索剪贴板/.test(panel),
  "search pill no longer uses SwiftUI TextField"
);
assertTrue(
  !/struct SearchFieldAccessor/.test(panel),
  "broken superview-walking SearchFieldAccessor is gone"
);
assertTrue(
  /private final class PanelSearchTextField:\s*NSTextField/.test(panel),
  "search editor is a native NSTextField"
);
assertTrue(
  /override var mouseDownCanMoveWindow:\s*Bool\s*\{\s*false\s*\}/.test(panel),
  "search field clicks do not drag the movable-background panel"
);
assertTrue(
  /\.focusable\(!showSearch\)/.test(panel),
  "panel is not focusable while the search box owns the keyboard"
);

// The AppKit field reports no natural size; without a fixed height SwiftUI gives
// it the whole remaining panel height and the pill balloons.
assertTrue(
  /func sizeThatFits\(_ proposal: ProposedViewSize, nsView: PanelSearchFieldHost/.test(panel),
  "search field reports a one-line size to SwiftUI"
);
assertTrue(
  /\.frame\(height: PanelSearchField\.fieldHeight\)/.test(panel),
  "search field is pinned to one line in the pill"
);
assertTrue(
  /\.fixedSize\(horizontal: false, vertical: true\)/.test(panel),
  "search pill hugs its content vertically"
);
const pillWidth = panel.match(/\.shelfPill\(tint: [^\n]*\)\s*\n\s*\.frame\(maxWidth: (\d+)\)/);
assertTrue(
  pillWidth !== null && Number(pillWidth[1]) <= 340,
  "search pill is capped at a compact width"
);

// The search row is content inside the panel card, under the nav bar — not a
// separate capsule floating above the surface.
const cardStart = panel.indexOf("private var panelCard: some View");
const cardEnd = panel.indexOf("private var topBar: some View", cardStart);
const cardBody = panel.slice(cardStart, cardEnd);
assertTrue(cardStart > 0 && cardEnd > cardStart, "panelCard is defined");
assertTrue(/searchRow/.test(cardBody), "search row lives inside the panel card");
assertTrue(!/searchPill/.test(panel), "the detached search pill is gone");

// One surface for the whole window, drawn by the root: the card and the detail
// overlay supply content only. A second background, inset, or shadow at the
// window edge is cut off by the window bounds and shows up as a translucent frame.
const bodyStart = panel.indexOf("var body: some View {");
const bodyEnd = panel.indexOf("private var isSearchFieldEditing", bodyStart);
const rootBody = panel.slice(bodyStart, bodyEnd);
assertTrue(/\.panelSurface\(\)/.test(rootBody), "root draws the shared panel surface");
assertTrue(!/\.shadow\(/.test(rootBody), "root draws no clipped shadow");
assertTrue(
  !/\.padding\(\.horizontal, 8\)/.test(rootBody) && !/\.padding\(\.bottom, 10\)/.test(rootBody),
  "panel content is not inset from the window edges"
);
assertTrue(!/\.background/.test(cardBody) && !/\.shadow\(/.test(cardBody), "panelCard draws no background or shadow of its own");
const overlayStart = panel.indexOf("struct ClipboardItemDetailOverlay");
const overlayBodyEnd = panel.indexOf("private var detailHeader", overlayStart);
const overlayBody = panel.slice(overlayStart, overlayBodyEnd);
assertTrue(
  !/\.shadow\(/.test(overlayBody) && !/RoundedRectangle\(cornerRadius/.test(overlayBody),
  "detail overlay draws no background or shadow of its own"
);

// Corner geometry comes from the theme so every surface shares one radius set,
// and nothing falls back to a hard-cornered rectangle.
const theme = read("Utilities/PasteTheme.swift");
assertTrue(/static let panelCornerRadius: CGFloat = \d+/.test(theme), "theme defines the panel radius");
assertTrue(/static let cardCornerRadius: CGFloat = \d+/.test(theme), "theme defines the card radius");
assertTrue(/func panelSurface\(\)/.test(theme), "theme defines the shared panel surface");
assertTrue(/style: \.continuous/.test(theme), "theme shapes use continuous corners");
assertTrue(
  !/RoundedRectangle\(cornerRadius: \d+, style: \.circular\)/.test(panel)
    && !/RoundedRectangle\(cornerRadius: \d+\)/.test(panel),
  "panel never falls back to a circular-cornered rectangle"
);

if (failed > 0) {
  console.error(`\n${failed} test(s) failed`);
  process.exit(1);
}
console.log("\nAll panel search tests passed.");
