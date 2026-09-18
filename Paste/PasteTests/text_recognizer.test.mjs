// Mirrors TextRecognizer's post-processing so CI / Linux agents can check it without
// Vision: Vision hands back unordered line observations in normalized coordinates
// (origin bottom-left), and we rebuild reading order from them.

import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const lineTolerance = 0.014;

const CJK_RANGES = [
  [0x3000, 0x303f],
  [0x3400, 0x4dbf],
  [0x4e00, 0x9fff],
  [0xf900, 0xfaff],
  [0xff00, 0xffef]
];

function isCJK(character) {
  if (!character) return false;
  const code = character.codePointAt(0);
  return CJK_RANGES.some(([low, high]) => code >= low && code <= high);
}

function joinFragments(pieces) {
  if (!pieces.length) return "";
  let result = pieces[0];
  for (const piece of pieces.slice(1)) {
    const bothCJK = isCJK(result[result.length - 1]) && isCJK(piece[0]);
    result += bothCJK ? piece : ` ${piece}`;
  }
  return result;
}

function assemble(fragments) {
  if (!fragments.length) return null;

  const ordered = [...fragments].sort((a, b) => {
    // Larger y is higher on screen, so descending y is top to bottom.
    if (Math.abs(a.midY - b.midY) > lineTolerance) return b.midY - a.midY;
    return a.minX - b.minX;
  });

  const lines = [];
  for (const fragment of ordered) {
    const current = lines[lines.length - 1];
    const last = current && current[current.length - 1];
    if (last && Math.abs(last.midY - fragment.midY) <= lineTolerance) {
      current.push(fragment);
    } else {
      lines.push([fragment]);
    }
  }

  const text = lines
    .map((line) => joinFragments(line.map((f) => f.text)))
    .join("\n")
    .trim();
  return text === "" ? null : text;
}

function characterCount(text) {
  return [...text].filter((c) => !/\s/u.test(c)).length;
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

const frag = (text, midY, minX) => ({ text, midY, minX });

assertEqual(assemble([]), null, "no observations means no text");

// Vision's order is not guaranteed, so a bottom line handed to us first must still
// come out last.
assertEqual(
  assemble([frag("第二行", 0.3, 0.1), frag("第一行", 0.7, 0.1)]),
  "第一行\n第二行",
  "lines are ordered top to bottom"
);

// Two observations on one visual line join into that line, left to right.
assertEqual(
  assemble([frag("好用的 Mac 工具。", 0.5, 0.45), frag("安静、", 0.502, 0.1)]),
  "安静、好用的 Mac 工具。",
  "same-line fragments join left to right without a CJK space"
);
assertEqual(
  assemble([frag("world", 0.5, 0.4), frag("hello", 0.5, 0.1)]),
  "hello world",
  "latin fragments keep their space"
);
assertEqual(
  joinFragments(["岸上", "PasteStack"]),
  "岸上 PasteStack",
  "a CJK/latin boundary keeps a space"
);
assertEqual(joinFragments(["单独一段"]), "单独一段", "a lone fragment is unchanged");

// Just inside and just outside the tolerance.
assertEqual(
  assemble([frag("B", 0.5, 0.5), frag("A", 0.51, 0.1)]),
  "A B",
  "a 0.01 gap is still one line"
);
assertEqual(
  assemble([frag("B", 0.5, 0.5), frag("A", 0.53, 0.1)]),
  "A\nB",
  "a 0.03 gap splits into two lines"
);

// Three lines arriving shuffled, each with two fragments.
assertEqual(
  assemble([
    frag("iCloud 里。", 0.30, 0.55),
    frag("我们做常驻菜单栏", 0.62, 0.30),
    frag("数据留在你自己的设备和", 0.30, 0.10),
    frag("岸上是一家独立工作室。", 0.62, 0.10),
    frag("第一款应用是", 0.10, 0.10)
  ]),
  "岸上是一家独立工作室。我们做常驻菜单栏\n数据留在你自己的设备和 iCloud 里。\n第一款应用是",
  "shuffled multi-line block rebuilds in reading order"
);

assertTrue(isCJK("安"), "han character is CJK");
assertTrue(isCJK("。"), "fullwidth punctuation is CJK");
assertTrue(!isCJK("M"), "latin letter is not CJK");
assertTrue(!isCJK(undefined), "missing character is not CJK");

assertEqual(characterCount("安静、好用的 Mac 工具。"), 12, "whitespace is not counted");
assertEqual(characterCount("a\nb c"), 3, "newlines are not counted");

function preparedScale(width, height, minSide = 180) {
  const side = Math.min(width, height);
  return side > 0 && side < minSide ? 2 : 1;
}
assertEqual(preparedScale(966, 442), 1, "a Retina UI crop is not upscaled");
assertEqual(preparedScale(80, 40), 2, "a tiny crop is doubled so Vision has enough pixels");
assertEqual(preparedScale(180, 180), 1, "a crop on the minimum side is left as-is");

const swift = fs.readFileSync(
  path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../Paste/Services/TextRecognizer.swift"),
  "utf8"
);
assertTrue(/func recognize\(cgImage: CGImage\)/.test(swift), "overlay OCR can skip the PNG round-trip");
assertTrue(/func recognize\(preparedCGImage: CGImage\)/.test(swift), "Vision can run on a bitmap copied off the freeze");
assertTrue(/func preparedImage\(from image: CGImage\)/.test(swift), "ScreenCaptureKit crops are copied into a disconnected sRGB bitmap");
assertTrue(/CGColorSpace\.sRGB/.test(swift) && /premultipliedLast/.test(swift), "prepared OCR bitmaps are 8-bit sRGB RGBA");
assertTrue(/minimumPreparedSide = 180/.test(swift), "tiny UI crops are upscaled before Vision");
assertTrue(/VNImageRequestHandler\(cgImage:/.test(swift), "Vision reads the cropped CGImage directly");
assertTrue(/recognitionLevel = level/.test(swift) && /\.fast/.test(swift), "sparse UI text tries .fast first");
assertTrue(/minimumTextHeight = \(level == \.fast\) \? 0 : 0\.008/.test(swift), "fast OCR does not drop small UI labels");
assertTrue(/automaticallyDetectsLanguage = true/.test(swift), "a language-pack miss still falls back to auto-detect");
assertTrue(/import ImageIO/.test(swift), "PNG history items decode through ImageIO before Vision");

const overlay = fs.readFileSync(
  path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../Paste/Views/ScreenshotOverlay.swift"),
  "utf8"
);
assertTrue(
  /TextRecognizer\.preparedImage\(from: cropped\)/.test(overlay),
  "the overlay copies the crop off the IOSurface before leaving the main thread"
);
assertTrue(
  /TextRecognizer\.recognize\(preparedCGImage: prepared\)/.test(overlay),
  "the overlay recognizes the prepared freeze pixels, not a re-encoded PNG"
);
assertTrue(
  !/TextRecognizer\.recognize\(cgImage: cropped\)/.test(overlay),
  "overlay OCR no longer hands Vision the live freeze crop"
);
assertTrue(
  !/TextRecognizer\.recognize\(imageData: data\)/.test(overlay),
  "overlay OCR no longer PNG-encodes the crop first"
);
assertTrue(/ocrPanelUsesLightAppearance/.test(overlay), "OCR card forces aqua so text is not white-on-white");
assertTrue(/ocrPanelTextColorHex/.test(overlay), "OCR ink is an explicit dark color, not labelColor");
assertTrue(/preferredColorScheme\(\.light\)/.test(overlay), "OCR card stays in light color scheme");
assertTrue(/ScreenshotL10n\.string\(\.ocrWorking\)/.test(overlay), "recognizing state has visible copy, not only a spinner");
assertTrue(!/textColor = \.labelColor/.test(overlay), "OCR text view does not use appearance-adaptive labelColor");
assertTrue(/class ScreenshotOCRScrollView/.test(overlay), "OCR text container width follows the card");
assertTrue(/setAttributedString\(NSAttributedString\(string: text, attributes: attributes\)\)/.test(overlay), "recognized text is painted with explicit dark attributes");

if (failed > 0) {
  console.error(`\n${failed} test(s) failed`);
  process.exit(1);
}
console.log("\nAll text recognizer tests passed.");
