// Mirrors the memoization and coalescing rules added for smoothness so CI / Linux
// agents can check them without Xcode: keyword-field cache invalidation, the
// excess-only history trim, and the pasteboard capture coalescing.

// --- KeywordScorer.fields(for:) ------------------------------------------------
// The cache key covers everything about an item that can change after ingest:
// the last-used date and both tag lists. Anything else is written once at insert.

function makeFieldsCache() {
  let cache = new Map();
  return {
    fingerprint(item) {
      return `${item.updatedAt}|${item.favoriteTagsJSON ?? ""}|${item.autoTagsJSON ?? ""}`;
    },
    fields(item) {
      const fp = this.fingerprint(item);
      const cached = cache.get(item.id);
      if (cached && cached.fingerprint === fp) return { ...cached, hit: true };
      const fields = { built: true, title: item.title };
      cache.set(item.id, { fingerprint: fp, fields });
      return { fields, hit: false };
    }
  };
}

// --- ClipboardStore.enforceHistoryLimit ----------------------------------------
// Count first; only when over the cap, fetch just the oldest excess and delete it.
// Favorites and pins neither count nor are trimmed.
function enforceHistoryLimit(items, limit) {
  const counting = items.filter((i) => !i.isPinned && !i.isFavorite);
  const excess = counting.length - limit;
  if (excess <= 0) return items;
  const stale = counting
    .slice()
    .sort((a, b) => a.updatedAt - b.updatedAt)
    .slice(0, excess);
  const dropped = new Set(stale.map((i) => i.id));
  return items.filter((i) => !dropped.has(i.id));
}

// --- ClipboardMonitor capture coalescing ---------------------------------------
// One capture at a time; a pasteboard change during an in-flight capture sets a
// pending flag, and finishing a capture with the flag set captures once more.
function makeMonitor() {
  return {
    inFlight: false,
    pending: false,
    captures: 0,
    poll(changeChanged) {
      if (!changeChanged) return;
      if (this.inFlight) {
        this.pending = true;
        return;
      }
      this.startCapture();
    },
    startCapture() {
      this.inFlight = true;
      this.captures += 1;
    },
    finishCapture() {
      this.inFlight = false;
      if (this.pending) {
        this.pending = false;
        this.startCapture();
      }
    }
  };
}

// --- EmbeddingIndex.notify coalescing ------------------------------------------
// First notification goes out immediately; bursts collapse into one trailing
// notification per interval, so a backfill cannot storm the UI with re-renders.
function makeNotifier(interval = 0.4) {
  return {
    last: -Infinity,
    trailingScheduled: false,
    sent: 0,
    notify(now) {
      const elapsed = now - this.last;
      if (elapsed >= interval) {
        this.last = now;
        this.sent += 1;
        return "immediate";
      }
      if (this.trailingScheduled) return "skipped";
      this.trailingScheduled = true;
      return "scheduled";
    },
    fireTrailing(now) {
      this.trailingScheduled = false;
      this.last = now;
      this.sent += 1;
    }
  };
}

// --- Tag list memoization -------------------------------------------------------
// Decoded tag lists are cached against the raw stored JSON string, so a render
// only pays the decode when the value actually changed.
function makeTagListCache() {
  const cache = new Map();
  return {
    tags(item) {
      const cached = cache.get(item.id);
      if (cached && cached.raw === item.tagsJSON) return { tags: cached.tags, hit: true };
      const tags = item.tagsJSON ? JSON.parse(item.tagsJSON) : [];
      cache.set(item.id, { raw: item.tagsJSON, tags });
      return { tags, hit: false };
    }
  };
}

// --- Filter memo ----------------------------------------------------------------
// The filtered list is a pure function of the query, the filter state and the
// item fingerprints; identical inputs return the previous result untouched.
function makeFilterMemo() {
  let key = null;
  let value = [];
  return {
    filtered(fingerprint, compute) {
      if (key === fingerprint) return { value, hit: true };
      value = compute();
      key = fingerprint;
      return { value, hit: false };
    }
  };
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

const item = { id: "a", updatedAt: 1000, favoriteTagsJSON: null, autoTagsJSON: null, title: "hello" };

const cache = makeFieldsCache();
assertEqual(cache.fields(item).hit, false, "first access builds the fields");
assertEqual(cache.fields(item).hit, true, "same fingerprint hits the cache");
assertEqual(cache.fields({ ...item, updatedAt: 1001 }).hit, false, "a paste (updatedAt bump) rebuilds");
assertEqual(
  cache.fields({ ...item, updatedAt: 1001, favoriteTagsJSON: "[\"工作\"]" }).hit,
  false,
  "tagging a favorite rebuilds"
);
assertEqual(
  cache.fields({ ...item, updatedAt: 1001, favoriteTagsJSON: "[\"工作\"]" }).hit,
  true,
  "the rebuilt entry is cached again"
);

const base = { isFavorite: false, isPinned: false };
const history = [
  { id: "1", updatedAt: 100, ...base },
  { id: "2", updatedAt: 200, ...base },
  { id: "3", updatedAt: 300, ...base },
  { id: "fav", updatedAt: 50, ...base, isFavorite: true },
  { id: "pin", updatedAt: 60, ...base, isPinned: true }
];
assertEqual(
  enforceHistoryLimit(history, 4).map((i) => i.id),
  ["1", "2", "3", "fav", "pin"],
  "at the cap nothing is trimmed"
);
assertEqual(
  enforceHistoryLimit(history, 2).map((i) => i.id),
  ["2", "3", "fav", "pin"],
  "over the cap only the oldest unprotected excess is deleted"
);
assertEqual(
  enforceHistoryLimit(history, 2).some((i) => i.isFavorite || i.isPinned),
  true,
  "favorites and pins survive the trim"
);

const monitor = makeMonitor();
monitor.poll(true);
assertEqual(monitor.captures, 1, "a change starts a capture");
monitor.poll(true);
monitor.poll(true);
assertEqual(monitor.captures, 1, "changes during a capture do not pile up");
monitor.finishCapture();
assertEqual(monitor.captures, 2, "finishing with a pending change captures once more");
monitor.finishCapture();
assertEqual(monitor.captures, 2, "no pending change, no extra capture");
monitor.poll(false);
assertEqual(monitor.captures, 2, "an unchanged change count never captures");

const notifier = makeNotifier();
assertEqual(notifier.notify(0), "immediate", "the first update goes out at once");
assertEqual(notifier.notify(0.1), "scheduled", "a burst schedules one trailing update");
assertEqual(notifier.notify(0.2), "skipped", "further updates in the burst are skipped");
assertEqual(notifier.notify(0.3), "skipped", "the burst stays collapsed");
notifier.fireTrailing(0.4);
assertEqual(notifier.sent, 2, "a 4-update burst produced 2 renders");
assertEqual(notifier.notify(0.9), "immediate", "after the interval, updates flow again");

const tagCache = makeTagListCache();
const tagged = { id: "t", tagsJSON: "[\"工作\"]" };
assertEqual(tagCache.tags(tagged).hit, false, "first tag read decodes");
assertEqual(tagCache.tags(tagged).hit, true, "same raw JSON hits the cache");
assertEqual(tagCache.tags({ ...tagged, tagsJSON: "[\"灵感\"]" }).hit, false, "a tag change re-decodes");
assertEqual(
  tagCache.tags({ ...tagged, tagsJSON: "[\"灵感\"]" }).tags,
  ["灵感"],
  "the re-decoded value is the new one"
);

const memo = makeFilterMemo();
let computes = 0;
const compute = () => { computes += 1; return ["x"]; };
assertEqual(memo.filtered("k1", compute).hit, false, "first filter computes");
assertEqual(memo.filtered("k1", compute).hit, true, "identical inputs reuse the result");
assertEqual(memo.filtered("k2", compute).hit, false, "any input change recomputes");
assertEqual(computes, 2, "three reads, two computations");

if (failed > 0) {
  console.error(`\n${failed} test(s) failed`);
  process.exit(1);
}
console.log("\nAll performance cache tests passed.");
