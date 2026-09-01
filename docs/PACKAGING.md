# Paste — 安装包打包说明

本仓库提供一键脚本，在 **macOS + Xcode** 上生成可分发的安装包。

## 产物

| 文件 | 说明 |
|------|------|
| `dist/Paste.app` | 应用程序 |
| `dist/Paste-1.0.0.dmg` | 拖拽安装镜像（推荐日常分发） |
| `dist/Paste-1.0.0.pkg` | 可选，标准安装器（`--pkg`） |
| `dist/SHA256.txt` | 校验和 |

## 本地打包（Mac）

```bash
# 1) 本地测试包（ad-hoc 签名，可本机安装）
./scripts/package.sh

# 或
make package

# 2) Developer ID 签名 DMG（对外分发）
./scripts/package.sh --sign --team YOUR_TEAM_ID

# 3) 签名 + PKG
./scripts/package.sh --sign --pkg

# 4) 签名 + 公证（需先配置 notarytool）
#    xcrun notarytool store-credentials PasteNotary \
#      --apple-id YOU@EMAIL --team-id TEAMID --password APP_SPECIFIC_PASSWORD
./scripts/package.sh --sign --pkg --notarize

# 5) App Store Connect 导出
./scripts/package.sh --app-store
```

### 安装 DMG

1. 双击打开 `Paste-x.y.z.dmg`
2. 将 **Paste** 拖到 **Applications**
3. 若提示「无法验证开发者」：系统设置 → 隐私与安全性 → **仍要打开**  
   （已公证的签名包通常不会出现此提示）

## GitHub Actions

仓库已包含工作流 `.github/workflows/package-macos.yml`：

1. GitHub → Actions → **Package macOS** → Run workflow
2. 或推送标签：`git tag v1.0.0 && git push origin v1.0.0`
3. 在 Artifacts 中下载 `Paste-*-macos.zip`（内含 `.dmg`）

> CI 默认产出 **ad-hoc / 未公证** 包，便于冒烟验证。对外正式分发请在已登录 Developer ID 的 Mac 上执行 `--sign --notarize`。

## 环境变量（可选）

| 变量 | 含义 |
|------|------|
| `MARKETING_VERSION` | 版本号，默认 `1.0.0` |
| `CURRENT_PROJECT_VERSION` | Build 号，默认 `1` |
| `PRODUCT_BUNDLE_IDENTIFIER` | Bundle ID |
| `CODE_SIGN_IDENTITY` | 签名身份 |
| `DEVELOPMENT_TEAM` | Team ID |
| `NOTARY_PROFILE` | notarytool 钥匙串配置名，默认 `PasteNotary` |

## 注意

- 当前 Linux / Cloud Agent 环境 **无法** 真正编译 `.app`，脚本会明确提示去 Mac 或 Actions 执行。
- 上架 Mac App Store 时请使用可区分的应用显示名（如 myPaste），并配置真实 Team / iCloud 容器。
