// Locks the shelf type ramp, capsule buttons, and zh-Hans / zh-Hant / en
// chrome so Linux CI can catch a regression without Xcode.

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

const theme = read("Utilities/PasteTheme.swift");
const l10n = read("Utilities/PanelL10n.swift");
const panel = read("Views/MenuBarPanel.swift");
const favorites = read("Views/FavoritesFolderView.swift");
const timeline = read("Views/TimelineOutlineView.swift");
const pbx = read("../Paste.xcodeproj/project.pbxproj");

assertTrue(/enum Typography/.test(theme), "PasteTheme has a Typography ramp");
assertTrue(/static var usesCJKLayout: Bool/.test(theme), "type sizes key off CJK vs Latin");
assertTrue(/static var chipMinimumScale: CGFloat/.test(theme), "chips can shrink for long English labels");
assertTrue(/containsCJK/.test(theme), "preview spacing inspects whether the text is CJK");
assertTrue(/func lineSpacing\(for text: String\)/.test(theme), "CJK previews get extra line spacing");
assertTrue(/func shelfChipLabel\(\)/.test(theme), "chip labels share one modifier");
assertTrue(/struct ShelfAccentButtonStyle: ButtonStyle/.test(theme), "primary actions use a capsule accent style");
assertTrue(/struct ShelfQuietButtonStyle: ButtonStyle/.test(theme), "secondary actions use a hairline capsule style");
assertTrue(/static var buttonHorizontalPadding: CGFloat/.test(theme), "button padding keys off CJK vs Latin");
assertTrue(/static var actionGap: CGFloat/.test(theme), "icon-to-title gap keys off CJK vs Latin");
assertTrue(/struct ShelfActionLabel: View/.test(theme), "action labels are a dedicated view, not system Label");
assertTrue(/ViewThatFits\(in: \.horizontal\)/.test(panel), "detail footer collapses to icons when English is too wide");
assertTrue(/ShelfActionLabel\(/.test(panel), "footer uses ShelfActionLabel");
assertTrue(/dynamicTypeSize\(DynamicTypeSize\.medium \.\.\. DynamicTypeSize\.xLarge\)/.test(panel), "panel caps Dynamic Type so chips stay on one line");
assertTrue(/shelfIconHitTarget\(\)/.test(panel), "icon buttons share one hit target size");

assertTrue(/enum PanelL10n/.test(l10n), "panel chrome is localized");
assertTrue(/case zhHans/.test(l10n) && /case zhHant/.test(l10n) && /case en/.test(l10n), "zh-Hans, zh-Hant, and English are covered");
assertTrue(/return \.zhHans/.test(l10n), "unrecognized locales fall back to zh-Hans");
assertTrue(/en: "Board"/.test(l10n) && /hant: "剪貼板"/.test(l10n), "clipboard tab has a short English label");
assertTrue(/en: "Saved"/.test(l10n), "favorites tab uses a short English label");
assertTrue(/en: "Listening"/.test(l10n), "status text has an English form");
assertTrue(/en: "Paste"/.test(l10n) && /en: "Copy"/.test(l10n), "footer actions are localized");
assertTrue(/en: "Read"/.test(l10n) && /en: "Save"/.test(l10n), "OCR and download use short English verbs");
assertTrue(/en: "Search…"/.test(l10n), "search placeholder stays short in English");
assertTrue(/characters"/.test(l10n), "character counts have a plural English form");

assertTrue(/PanelL10n\.clipboard/.test(panel), "top bar uses localized tab titles");
assertTrue(/shelfChipLabel\(\)/.test(panel), "board tabs use the shared chip label");
assertTrue(/ScrollView\(\.horizontal/.test(panel), "tabs scroll instead of overflowing long English labels");
assertTrue(/minimumScaleFactor/.test(panel), "panel labels can shrink instead of clipping");
assertTrue(/ShelfAccentButtonStyle/.test(panel), "onboarding and paste use the accent capsule");
assertTrue(/ShelfQuietButtonStyle/.test(panel), "copy / OCR / download use the quiet capsule");
assertTrue(!/\.buttonStyle\(\.borderedProminent\)/.test(panel), "panel no longer uses system borderedProminent buttons");
assertTrue(!/\.buttonStyle\(\.bordered\)/.test(panel), "panel no longer uses system bordered buttons");
assertTrue(/PanelL10n\.searchPlaceholder/.test(panel), "search field placeholder is localized");
assertTrue(/PasteTheme\.Typography\.preview/.test(panel), "card previews use the preview type");
assertTrue(/lineSpacing\(PasteTheme\.Typography\.lineSpacing/.test(panel), "card previews space CJK and Latin differently");

assertTrue(/PanelL10n\.allFavorites/.test(favorites), "favorites chips are localized");
assertTrue(/shelfChipLabel\(\)/.test(favorites), "favorites chips use the shared chip label");
assertTrue(/PanelL10n\.timelineEmpty/.test(timeline), "timeline empty state is localized");
assertTrue(/PanelL10n\.today/.test(timeline), "timeline day headings are localized");
assertTrue(/hasher\.combine\(PanelL10n\.language\.rawValue\)/.test(timeline), "timeline cache invalidates when the language changes");

assertTrue(/PanelL10n\.contentType/.test(read("Models/ClipboardItem.swift")), "content-type chips follow the panel language");
assertTrue(/PanelL10n\.autoTag/.test(read("Services/AutoTagService.swift")), "auto-tag chips follow the panel language");
assertTrue(/PanelL10n\.keptFavorite/.test(read("Utilities/RetentionPolicy.swift")), "retention captions follow the panel language");

assertTrue(/PanelL10n\.openSettings/.test(read("Utilities/StatusItemController.swift")), "overflow menu titles follow the panel language");
assertTrue(/ScreenshotL10n\.string\(\.imageCopied\)/.test(read("Services/ScreenshotService.swift")), "screenshot HUD follows ScreenshotL10n");

if (failed > 0) {
  console.error(`\n${failed} test(s) failed`);
  process.exit(1);
}
console.log("\nAll panel typography tests passed.");
