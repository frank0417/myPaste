const { chromium } = require('playwright-core');
const fs = require('fs');

const OUT = '/workspace/appstore-assets/source';
const PREVIEW = 'file:///workspace/Paste/preview/index.html';

(async () => {
  fs.mkdirSync(OUT, { recursive: true });
  const browser = await chromium.launch({
    executablePath: '/usr/local/bin/google-chrome',
    headless: true,
    args: ['--no-sandbox', '--force-device-scale-factor=2', '--font-render-hinting=none'],
  });
  const page = await browser.newPage({
    deviceScaleFactor: 2,
    viewport: { width: 1600, height: 1100 },
  });
  await page.goto(PREVIEW, { waitUntil: 'networkidle' });
  await page.waitForTimeout(1500);

  // 页面背景透明化, 便于合成到营销画布
  await page.addStyleTag({
    content: `body { background: transparent !important; }
              .stage { margin: 0 auto; }`,
  });
  await page.waitForTimeout(300);

  // 1. 主窗口 (全部列表 + 预览)
  const win = await page.$('section.window');
  await win.screenshot({ path: `${OUT}/01-main-window.png`, omitBackground: true });
  console.log('01 main window done');

  // 2. 搜索状态
  await page.fill('#search', '同步');
  await page.waitForTimeout(500);
  await win.screenshot({ path: `${OUT}/02-search.png`, omitBackground: true });
  await page.fill('#search', '');
  await page.waitForTimeout(400);
  console.log('02 search done');

  // 3. 代码类型筛选 (点侧边栏 代码)
  await page.click('.sidebar .nav-item[data-filter="code"]');
  await page.waitForTimeout(400);
  await win.screenshot({ path: `${OUT}/03-filter-code.png`, omitBackground: true });
  await page.click('.sidebar .nav-item[data-filter="all"]');
  await page.waitForTimeout(300);
  console.log('03 filter done');

  // 4. 菜单栏面板
  const menubar = await page.$('section.menubar');
  await menubar.screenshot({ path: `${OUT}/04-menubar-panel.png`, omitBackground: true });
  console.log('04 menubar done');

  // 5. 设置 - 快捷键
  await page.click('[data-settings-tab="hotkeys"]');
  await page.waitForTimeout(400);
  const settings = await page.$('section.settings-window');
  await settings.screenshot({ path: `${OUT}/05-settings-hotkeys.png`, omitBackground: true });
  console.log('05 settings done');

  // 6. 截图标注 (打开覆盖层并拖出选区)
  await page.click('#simulateShot');
  await page.waitForTimeout(800);
  await page.mouse.move(420, 380);
  await page.mouse.down();
  await page.mouse.move(1180, 760, { steps: 24 });
  await page.mouse.up();
  await page.waitForTimeout(600);
  const overlay = await page.$('#shotOverlay');
  await overlay.screenshot({ path: `${OUT}/06-screenshot-annotator.png` });
  console.log('06 shot overlay done');

  await browser.close();
  console.log('all captures done');
})().catch(e => { console.error(e); process.exit(1); });
