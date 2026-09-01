function detect(text) {
  const trimmed = text.trim();
  if (/^#([0-9A-Fa-f]{3}|[0-9A-Fa-f]{6}|[0-9A-Fa-f]{8})$/.test(trimmed)) return "color";
  if (/^(https?:\/\/|www\.)\S+$/i.test(trimmed) && !trimmed.includes("\n")) return "link";
  if (looksLikeCode(trimmed)) return "code";
  if (trimmed.length > 120 || trimmed.includes("\n")) return "snippet";
  return "text";
}

function looksLikeCode(text) {
  const hints = [
    "func ", "import ", "const ", "let ", "var ", "class ", "def ", "#!/",
    "{", "}", "=>", "console.", "SELECT ", "CREATE TABLE", "</", "<?"
  ];
  const lines = text.split("\n");
  if (lines.length < 2) {
    return hints.some((h) => text.includes(h)) && text.length > 24;
  }
  const hintHits = hints.filter((h) => text.includes(h)).length;
  const indentLines = lines.filter((l) => l.startsWith("  ") || l.startsWith("\t")).length;
  return hintHits >= 2 || (hintHits >= 1 && indentLines >= 2);
}

function previewTitle(text, type) {
  const firstLine = text.split(/\n/)[0] ?? text;
  const clipped = firstLine.length > 80 ? firstLine.slice(0, 77) + "…" : firstLine;
  if (type === "link") {
    return clipped.replace("https://", "").replace("http://", "");
  }
  return clipped;
}

let failed = 0;
function assertEqual(actual, expected, name) {
  if (actual !== expected) {
    console.error(`FAIL ${name}: expected ${expected}, got ${actual}`);
    failed += 1;
  } else {
    console.log(`PASS ${name}`);
  }
}

assertEqual(detect("https://example.com/path"), "link", "detect link");
assertEqual(detect("www.apple.com"), "link", "detect www link");
assertEqual(detect("#0F766E"), "color", "detect hex color");
assertEqual(detect("#fff"), "color", "detect short hex");
assertEqual(
  detect(`import Foundation\nfunc greet(_ name: String) {\n  print(name)\n}`),
  "code",
  "detect code"
);
assertEqual(detect("你好，Paste"), "text", "detect plain text");
assertEqual(previewTitle("a".repeat(100), "text").endsWith("…"), true, "clip long title");
assertEqual(previewTitle("a".repeat(100), "text").length, 78, "clip length");

if (failed > 0) {
  console.error(`\n${failed} test(s) failed`);
  process.exit(1);
}
console.log("\nAll content-type detector tests passed.");
