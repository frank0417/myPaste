// Mirrors the memory-budget rules: never persist uncompressed TIFF, keep the
// decoded-image cache small, load embedding models lazily, and drop the shelf's
// SwiftUI tree while it is hidden.

import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../Paste");

function read(rel) {
  return fs.readFileSync(path.join(root, rel), "utf8");
}

// --- ClipboardMonitor stored-image choice --------------------------------------
// Prefer the pasteboard PNG; never keep tiffRepresentation. Oversize PNG/TIFF
// is re-encoded (PNG if it stays small, otherwise JPEG).
const MAX_PREFERRED_PNG_BYTES = 1_500_000;
const COMPACT_TIFF_BYTES = 800_000;
const COMPACT_ANY_BYTES = 3_000_000;
const DECODED_BUDGET = 48 * 1024 * 1024;
const PASTE_BUDGET = 8 * 1024 * 1024;
const THUMB_MAX_PIXEL = 240;
const PREVIEW_MAX_PIXEL = 1800;

function storedImageChoice({ hasPng, pngBytes, exceedsMaxEdge }) {
  if (hasPng && pngBytes > 32) {
    if (pngBytes <= MAX_PREFERRED_PNG_BYTES && !exceedsMaxEdge) return "png";
    return "compact";
  }
  return "compact";
}

function isTIFF(bytes) {
  if (!bytes || bytes.length < 4) return false;
  const [a, b, c, d] = bytes;
  return (a === 0x49 && b === 0x49 && c === 0x2a && d === 0x00)
    || (a === 0x4d && b === 0x4d && c === 0x00 && d === 0x2a);
}

function shouldCompactStoredImage(data) {
  if (isTIFF(data.magic)) return data.bytes >= COMPACT_TIFF_BYTES;
  return data.bytes >= COMPACT_ANY_BYTES;
}

function decodedCost(pixelsWide, pixelsHigh) {
  return Math.max(pixelsWide * pixelsHigh * 4, 1);
}

function downsampleMaxPixel(preferThumbnail) {
  return preferThumbnail ? THUMB_MAX_PIXEL : PREVIEW_MAX_PIXEL;
}

// --- EmbeddingIndex.prepare ----------------------------------------------------
// Load vectors from disk. Do not warmup English + CJK models at launch.
function embeddingPrepare() {
  return { loadFromDisk: true, warmupLatin: false, warmupCJK: false };
}

function embeddingBackfill({ missing, modelLoaded }) {
  return {
    queued: missing,
    drain: modelLoaded
  };
}

// --- Panel hosting -------------------------------------------------------------
// install creates an empty NSPanel; show attaches SwiftUI; hide drops it.
function panelLifecycle(event, state = { hosted: false, cacheReleased: false }) {
  switch (event) {
    case "install":
      return { hosted: false, cacheReleased: false };
    case "show":
      return { hosted: true, cacheReleased: false };
    case "hide":
      return { hosted: false, cacheReleased: true };
    default:
      return state;
  }
}

// --- AutoTagService.backfillIfNeeded -------------------------------------------
function autotagBackfill(items) {
  return items.filter((item) => item.autoTagsJSON == null).map((item) => item.id);
}

// --- ClipboardStore.compactOversizedImages -------------------------------------
// Walk oldest-first two at a time, advancing past createdAt, never loading the
// whole image table.
function compactWalk(items, { batchSize = 2, maxPasses = 20 } = {}) {
  const imageItems = items
    .filter((item) => item.contentTypeRaw === "image")
    .slice()
    .sort((a, b) => a.createdAt - b.createdAt)
    .map((item) => ({ ...item }));
  let after = -Infinity;
  let passes = 0;
  let compacted = 0;
  let peakLoaded = 0;
  while (passes < maxPasses) {
    const batch = imageItems.filter((item) => item.createdAt > after).slice(0, batchSize);
    if (batch.length === 0) break;
    peakLoaded = Math.max(peakLoaded, batch.length);
    for (const item of batch) {
      if (shouldCompactStoredImage(item)) {
        item.bytes = Math.floor(item.bytes / 10);
        item.magic = [0x89, 0x50, 0x4e, 0x47];
        compacted += 1;
      }
    }
    after = batch[batch.length - 1].createdAt;
    passes += 1;
  }
  return { compacted, passes, peakLoaded };
}

let failed = 0;
function assertEqual(actual, expected, name) {
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    console.error(`FAIL ${name}: expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`);
    failed += 1;
  } else {
    console.log(`PASS ${name}`);
  }
}
function assertTrue(cond, name) {
  assertEqual(Boolean(cond), true, name);
}

assertEqual(
  storedImageChoice({ hasPng: true, pngBytes: 220_000, exceedsMaxEdge: false }),
  "png",
  "a modest pasteboard PNG is stored as-is"
);
assertEqual(
  storedImageChoice({ hasPng: true, pngBytes: 4_000_000, exceedsMaxEdge: false }),
  "compact",
  "a huge pasteboard PNG is re-encoded"
);
assertEqual(
  storedImageChoice({ hasPng: true, pngBytes: 400_000, exceedsMaxEdge: true }),
  "compact",
  "a PNG past the pixel cap is downscaled"
);
assertEqual(
  storedImageChoice({ hasPng: false, pngBytes: 0, exceedsMaxEdge: false }),
  "compact",
  "TIFF-only pasteboards are never stored as TIFF"
);

assertTrue(isTIFF([0x49, 0x49, 0x2a, 0x00]), "little-endian TIFF magic");
assertTrue(isTIFF([0x4d, 0x4d, 0x00, 0x2a]), "big-endian TIFF magic");
assertEqual(isTIFF([0x89, 0x50, 0x4e, 0x47]), false, "PNG is not TIFF");

assertEqual(
  shouldCompactStoredImage({ magic: [0x49, 0x49, 0x2a, 0x00], bytes: 900_000 }),
  true,
  "an 800KB+ TIFF is compacted"
);
assertEqual(
  shouldCompactStoredImage({ magic: [0x49, 0x49, 0x2a, 0x00], bytes: 120_000 }),
  false,
  "a small TIFF is left alone"
);
assertEqual(
  shouldCompactStoredImage({ magic: [0x89, 0x50, 0x4e, 0x47], bytes: 2_000_000 }),
  false,
  "a 2MB PNG stays"
);
assertEqual(
  shouldCompactStoredImage({ magic: [0x89, 0x50, 0x4e, 0x47], bytes: 4_000_000 }),
  true,
  "a 3MB+ PNG is compacted"
);

assertEqual(decodedCost(240, 240), 240 * 240 * 4, "cache cost is decoded pixels");
assertTrue(decodedCost(2560, 1600) < DECODED_BUDGET, "one preview frame fits the 48MB budget");
assertTrue(DECODED_BUDGET < 256 * 1024 * 1024, "decoded budget is far below the old 256MB cap");
assertTrue(PASTE_BUDGET <= 8 * 1024 * 1024, "paste encodings are capped at 8MB");
assertEqual(downsampleMaxPixel(true), 240, "cards downsample to 240px");
assertEqual(downsampleMaxPixel(false), 1800, "detail views downsample to 1800px");

assertEqual(
  embeddingPrepare(),
  { loadFromDisk: true, warmupLatin: false, warmupCJK: false },
  "launch loads vectors, not NLContextualEmbedding models"
);
assertEqual(
  embeddingBackfill({ missing: 12, modelLoaded: false }),
  { queued: 12, drain: false },
  "backfill queues work but does not load a model while idle"
);
assertEqual(
  embeddingBackfill({ missing: 12, modelLoaded: true }),
  { queued: 12, drain: true },
  "backfill drains only after a model is already resident"
);

let panel = panelLifecycle("install");
assertEqual(panel.hosted, false, "install does not attach the SwiftUI tree");
panel = panelLifecycle("show", panel);
assertEqual(panel.hosted, true, "show attaches the shelf");
panel = panelLifecycle("hide", panel);
assertEqual(panel, { hosted: false, cacheReleased: true }, "hide drops the tree and the image cache");

assertEqual(
  autotagBackfill([
    { id: "a", autoTagsJSON: null },
    { id: "b", autoTagsJSON: "[\"image\"]" },
    { id: "c", autoTagsJSON: "[]" }
  ]),
  ["a"],
  "tag backfill only fetches rows that never received tags"
);

const library = [];
for (let i = 0; i < 10; i += 1) {
  library.push({
    id: String(i),
    contentTypeRaw: "image",
    createdAt: i + 1,
    bytes: 2_000_000,
    magic: [0x49, 0x49, 0x2a, 0x00]
  });
}
library.push({ id: "text", contentTypeRaw: "text", createdAt: 0, bytes: 40, magic: [] });
const walked = compactWalk(library);
assertEqual(walked.compacted, 10, "every oversized TIFF is rewritten");
assertEqual(walked.peakLoaded, 2, "compaction never materializes more than two images");
assertTrue(walked.passes <= 20, "compaction is capped");

const cacheSrc = read("Utilities/ImageCache.swift");
const monitorSrc = read("Services/ClipboardMonitor.swift");
const embedSrc = read("Services/EmbeddingIndex.swift");
const appSrc = read("PasteApp.swift");
const statusSrc = read("Utilities/StatusItemController.swift");

assertTrue(
  cacheSrc.includes("decodedBudgetBytes = 48 * 1024 * 1024"),
  "ImageCache decoded budget is 48MB"
);
assertTrue(
  !cacheSrc.includes("256 * 1024 * 1024"),
  "the old 256MB image cache cap is gone"
);
assertTrue(
  cacheSrc.includes("kCGImageSourceThumbnailMaxPixelSize"),
  "cards downsample via ImageIO instead of decoding the full bitmap"
);
assertTrue(
  cacheSrc.includes("makeMemoryPressureSource"),
  "decoded bitmaps are dropped under memory pressure"
);
assertTrue(
  monitorSrc.includes("storedImageData(from: pasteboard, image: image)"),
  "pasteboard captures go through storedImageData"
);
assertTrue(
  !monitorSrc.includes("imageData: tiff"),
  "clipboard images are no longer stored as uncompressed TIFF"
);
assertTrue(
  /func prepare\(\)[\s\S]*loadFromDiskIfNeeded\(\)/.test(embedSrc)
    && !embedSrc.includes("warmup(.latin)")
    && !embedSrc.includes("warmup(.cjk)"),
  "prepare no longer loads English and CJK embedding models"
);
assertTrue(
  !appSrc.includes("FetchDescriptor<ClipboardItem>())) ?? []"),
  "launch no longer fetches the entire history to backfill embeddings"
);
assertTrue(
  statusSrc.includes("ImageCache.shared.releaseMemory()"),
  "hiding the shelf releases decoded images"
);
assertTrue(
  /panel\?\.contentView = NSView\(\)/.test(statusSrc),
  "hiding the shelf drops the SwiftUI @Query tree"
);
const makePanelBody = statusSrc.split("private func makePanel()")[1]?.split("private func makeHostingView")[0] ?? "";
assertTrue(
  !makePanelBody.includes("makeHostingView"),
  "installing the status item does not attach MenuBarPanel"
);

if (failed > 0) {
  console.error(`\n${failed} test(s) failed`);
  process.exit(1);
}
console.log("\nAll memory budget tests passed.");
