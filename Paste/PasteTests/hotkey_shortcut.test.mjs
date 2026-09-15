// Mirrors HotKeyShortcut validation/display rules so CI / Linux agents can check them
// without Xcode. Key codes and modifier masks come from Carbon.HIToolbox.

const cmdKey = 0x0100;
const shiftKey = 0x0200;
const optionKey = 0x0800;
const controlKey = 0x1000;

const KEY = {
  v: 0x09,
  q: 0x0c,
  three: 0x14,
  four: 0x15,
  five: 0x17,
  tab: 0x30,
  space: 0x31,
  escape: 0x35,
  command: 0x37,
  shift: 0x38,
  option: 0x3a,
  control: 0x3b,
  capsLock: 0x39,
  fn: 0x3f,
  f1: 0x7a
};

const MODIFIER_KEY_CODES = new Set([
  0x37, 0x36, 0x38, 0x3c, 0x3a, 0x3d, 0x3b, 0x3e, 0x39, 0x3f
]);

const RESERVED = [
  { keyCode: KEY.space, carbon: cmdKey, name: "⌘Space（聚焦搜索）" },
  { keyCode: KEY.tab, carbon: cmdKey, name: "⌘⇥（切换 App）" },
  { keyCode: KEY.q, carbon: cmdKey, name: "⌘Q（退出 App）" },
  { keyCode: KEY.three, carbon: cmdKey | shiftKey, name: "⇧⌘3（截屏）" },
  { keyCode: KEY.four, carbon: cmdKey | shiftKey, name: "⇧⌘4（截屏）" },
  { keyCode: KEY.five, carbon: cmdKey | shiftKey, name: "⇧⌘5（截屏）" }
];

// HotKeyAction: the two mutually exclusive surfaces plus the screenshot trigger,
// each with its own binding.
const ACTION = {
  panel: { id: 1, shortTitle: "剪贴板面板", storageKey: "globalHotKeyShortcut" },
  mainWindow: { id: 2, shortTitle: "主窗口", storageKey: "mainWindowHotKeyShortcut" },
  screenshot: { id: 3, shortTitle: "截图", storageKey: "screenshotHotKeyShortcut" }
};

const DEFAULTS = {
  panel: { keyCode: KEY.v, carbonModifiers: cmdKey | shiftKey },
  mainWindow: { keyCode: KEY.v, carbonModifiers: cmdKey | optionKey },
  screenshot: { keyCode: KEY.four, carbonModifiers: cmdKey | shiftKey | controlKey }
};

const DEFAULT = DEFAULTS.panel;

function isComplete({ keyCode, carbonModifiers }) {
  if (MODIFIER_KEY_CODES.has(keyCode)) return false;
  return (carbonModifiers & (cmdKey | controlKey | optionKey)) !== 0;
}

function rejectionReason(shortcut) {
  if (MODIFIER_KEY_CODES.has(shortcut.keyCode)) {
    return "请在按住修饰键的同时按一个字母、数字或功能键";
  }
  if (!isComplete(shortcut)) {
    return "快捷键需要包含 ⌘ / ⌃ / ⌥ 中的至少一个";
  }
  const match = RESERVED.find(
    (r) => r.keyCode === shortcut.keyCode && r.carbon === shortcut.carbonModifiers
  );
  if (match) return `${match.name} 已被系统占用，请换一个组合`;
  return null;
}

function display({ keyCode, carbonModifiers }, keyName) {
  let s = "";
  if (carbonModifiers & controlKey) s += "⌃";
  if (carbonModifiers & optionKey) s += "⌥";
  if (carbonModifiers & shiftKey) s += "⇧";
  if (carbonModifiers & cmdKey) s += "⌘";
  return s + keyName;
}

function carbonModifiers({ command, shift, option, control }) {
  let carbon = 0;
  if (command) carbon |= cmdKey;
  if (shift) carbon |= shiftKey;
  if (option) carbon |= optionKey;
  if (control) carbon |= controlKey;
  return carbon;
}

const sameShortcut = (a, b) =>
  Boolean(a) && Boolean(b) && a.keyCode === b.keyCode && a.carbonModifiers === b.carbonModifiers;

// Mirrors GlobalHotKeyManager.apply: validate, reject a combo the other action already
// owns, and keep the previous binding when the system refuses the registration.
function apply(bindings, action, shortcut, { registrationSucceeds = true } = {}) {
  const reason = rejectionReason(shortcut);
  if (reason) return { result: { rejected: reason }, bindings };

  const clash = Object.keys(bindings).find(
    (other) => other !== action && sameShortcut(bindings[other], shortcut)
  );
  if (clash) {
    return {
      result: { rejected: `与「${ACTION[clash].shortTitle}」快捷键相同，请换一个` },
      bindings
    };
  }
  if (!registrationSucceeds) {
    return { result: { rejected: "该组合已被其他 App 占用，请换一个" }, bindings };
  }
  return { result: { applied: true }, bindings: { ...bindings, [action]: shortcut } };
}

// Mirrors GlobalHotKeyManager.dispatch: the Carbon hot key id selects the action.
function actionForHotKeyID(id) {
  return Object.keys(ACTION).find((name) => ACTION[name].id === id) ?? null;
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

assertEqual(rejectionReason(DEFAULT), null, "default shift-cmd-V is valid");
assertEqual(display(DEFAULT, "V"), "⇧⌘V", "default renders as shift-cmd-V");
assertEqual(
  display({ keyCode: KEY.f1, carbonModifiers: controlKey | optionKey | shiftKey | cmdKey }, "F1"),
  "⌃⌥⇧⌘F1",
  "modifier glyph order"
);

assertTrue(!isComplete({ keyCode: KEY.command, carbonModifiers: cmdKey }), "modifier-only press incomplete");
assertTrue(!isComplete({ keyCode: KEY.capsLock, carbonModifiers: cmdKey }), "caps lock incomplete");
assertTrue(!isComplete({ keyCode: KEY.v, carbonModifiers: shiftKey }), "shift alone incomplete");
assertTrue(isComplete({ keyCode: KEY.v, carbonModifiers: optionKey }), "option+letter complete");
assertTrue(isComplete({ keyCode: KEY.v, carbonModifiers: controlKey }), "control+letter complete");

assertEqual(
  rejectionReason({ keyCode: KEY.v, carbonModifiers: 0 }),
  "快捷键需要包含 ⌘ / ⌃ / ⌥ 中的至少一个",
  "bare key rejected"
);
assertEqual(
  rejectionReason({ keyCode: KEY.q, carbonModifiers: cmdKey }),
  "⌘Q（退出 App） 已被系统占用，请换一个组合",
  "cmd-Q rejected"
);
assertEqual(
  rejectionReason({ keyCode: KEY.space, carbonModifiers: cmdKey }),
  "⌘Space（聚焦搜索） 已被系统占用，请换一个组合",
  "cmd-space rejected"
);
assertEqual(
  rejectionReason({ keyCode: KEY.q, carbonModifiers: cmdKey | optionKey }),
  null,
  "opt-cmd-Q is allowed"
);
assertEqual(
  rejectionReason({ keyCode: KEY.escape, carbonModifiers: cmdKey }),
  null,
  "cmd-esc is allowed"
);

assertEqual(
  carbonModifiers({ command: true, shift: true }),
  cmdKey | shiftKey,
  "cocoa flags map to carbon"
);

// Per-action defaults must differ, or the two surfaces would fight over one combo.
assertEqual(rejectionReason(DEFAULTS.mainWindow), null, "main window default is valid");
assertEqual(display(DEFAULTS.mainWindow, "V"), "⌥⌘V", "main window default renders as opt-cmd-V");
assertTrue(
  !sameShortcut(DEFAULTS.panel, DEFAULTS.mainWindow),
  "panel and main window defaults differ"
);
assertEqual(ACTION.panel.storageKey, "globalHotKeyShortcut", "panel keeps the legacy storage key");

// The screenshot default must clear the system ⇧⌘4 it deliberately echoes.
assertEqual(rejectionReason(DEFAULTS.screenshot), null, "screenshot default is valid");
assertEqual(display(DEFAULTS.screenshot, "4"), "⌃⇧⌘4", "screenshot default renders as ctrl-shift-cmd-4");
assertEqual(
  rejectionReason({ keyCode: KEY.four, carbonModifiers: cmdKey | shiftKey }),
  "⇧⌘4（截屏） 已被系统占用，请换一个组合",
  "system screenshot combo stays rejected"
);
assertTrue(
  !sameShortcut(DEFAULTS.screenshot, DEFAULTS.panel) && !sameShortcut(DEFAULTS.screenshot, DEFAULTS.mainWindow),
  "screenshot default differs from both window defaults"
);

// A rejected combo must not clear the working shortcut.
const bindings = {
  panel: DEFAULTS.panel,
  mainWindow: DEFAULTS.mainWindow,
  screenshot: DEFAULTS.screenshot
};
let out = apply(bindings, "panel", { keyCode: KEY.q, carbonModifiers: cmdKey });
assertTrue("rejected" in out.result, "reserved combo reports rejection");
assertEqual(out.bindings.panel, DEFAULTS.panel, "reserved combo keeps previous hotkey");

out = apply(bindings, "panel", { keyCode: KEY.f1, carbonModifiers: cmdKey }, { registrationSucceeds: false });
assertTrue("rejected" in out.result, "taken combo reports rejection");
assertEqual(out.bindings.panel, DEFAULTS.panel, "taken combo keeps previous hotkey");

// Assigning the other surface's combo is reported instead of silently stealing it.
out = apply(bindings, "panel", DEFAULTS.mainWindow);
assertEqual(
  out.result.rejected,
  "与「主窗口」快捷键相同，请换一个",
  "duplicate across actions rejected"
);
assertEqual(out.bindings.panel, DEFAULTS.panel, "duplicate keeps previous hotkey");

// Re-applying an action's own combo is not a duplicate.
out = apply(bindings, "panel", DEFAULTS.panel);
assertTrue("applied" in out.result, "re-applying own combo is fine");

out = apply(bindings, "mainWindow", { keyCode: KEY.f1, carbonModifiers: controlKey | optionKey });
assertTrue("applied" in out.result, "valid combo applies");
assertEqual(
  out.bindings.mainWindow.carbonModifiers,
  controlKey | optionKey,
  "valid combo becomes current"
);
assertEqual(out.bindings.panel, DEFAULTS.panel, "applying one action leaves the other alone");

out = apply(bindings, "mainWindow", DEFAULTS.screenshot);
assertEqual(
  out.result.rejected,
  "与「截图」快捷键相同，请换一个",
  "stealing the screenshot combo is rejected"
);

assertEqual(actionForHotKeyID(1), "panel", "hot key id 1 is the shelf panel");
assertEqual(actionForHotKeyID(2), "mainWindow", "hot key id 2 is the main window");
assertEqual(actionForHotKeyID(3), "screenshot", "hot key id 3 is the screenshot");
assertEqual(actionForHotKeyID(4), null, "unknown hot key id is ignored");

if (failed > 0) {
  console.error(`\n${failed} test(s) failed`);
  process.exit(1);
}
console.log("\nAll hotkey shortcut tests passed.");
