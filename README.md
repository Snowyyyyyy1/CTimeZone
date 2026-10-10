# CTimeZone

给 Claude 单独设置时区的原生 macOS 小工具，系统时区保持不变。

*A small macOS app that gives Claude Code and Claude Desktop their own time zone without changing your Mac's.*

> 非官方项目，与 Anthropic 无关。“Claude” 是 Anthropic 的商标，这里只用来说明本工具作用的对象。

## 安装

1. 从 [Releases](https://github.com/Snowyyyyyy1/CTimeZone/releases) 下载最新的 `CTimeZone-<版本>.dmg`，把 App 拖进「应用程序」。
2. 首次打开：本项目没有 Apple Developer ID，App 只做了 ad-hoc 签名，macOS 会拦下。去「系统设置 → 隐私与安全性」点「仍要打开」，或在终端执行：

   ```bash
   xattr -dr com.apple.quarantine /Applications/CTimeZone.app
   ```

要求 macOS 14 或更高。

## 自动更新

App 内置 [Sparkle](https://sparkle-project.org)，每天在后台检查一次，下载好后在退出时安装；也可以从菜单 **CTimeZone → Check for Updates…** 手动检查。

- 更新包靠 appcast 里的 EdDSA 签名验证，公钥写在 `Project.swift`，私钥只在维护者手里。没有 Developer ID 也能安全更新。
- 只有装在 `/Applications` 或 `~/Applications` 的副本会自动更新；从构建目录或 DMG 里直接运行的副本不会。

## 作用范围

- **Claude Code + URL Handler**：写入 `~/.claude/settings.json` 的 `env.TZ`。两者共用同一份配置和同一个二进制，没法分开设置。
- **Claude Desktop**：通过 `/usr/bin/open -a /Applications/Claude.app --env TZ=<时区>` 注入启动环境，和 CLI 配置互不影响。

只改 `env.TZ`，保留 JSON 里的其他字段；根节点或 `env` 结构异常时直接报错，不会覆盖。

## 使用

1. 在左侧列表搜索并选择时区（城市名或地区都行，例如 `new york`）。上方的地图和时钟会先预览。
2. **Apply**：写入 `env.TZ`，同时把 Desktop 的启动时区设成同一个。**不会**重启 Claude Code，需要你自己重开会话。
3. **Use System**：只删除 `env.TZ`（保留 `env` 里的其他键），Desktop 切回系统时区。
4. **Open / Relaunch**：按目标时区启动 Claude Desktop。已有实例的时区不同时会先确认，再正常退出并重新启动；不用 `open -n`，也不强制退出。

## 行为说明

- 改 `env.TZ` 只影响新启动的 Claude Code 会话，已在运行的进程不受影响。
- Desktop 要经本工具启动才带上 `TZ`；直接从 Dock 或 Finder 打开的实例用的是系统时区。
- Claude Code 自身更新不影响设置，因为配置写在 `settings.json` 里。
- 只控制本地进程环境里的时区，**不代表** Claude 服务端检测到的时区。
- 不修改、不重签名 `Claude.app`，也不动 CLI 的符号链接。

## 写入、备份与回滚

- 原子写入（临时文件 + `replaceItemAt`），文件和备份的权限尽量设为 `0600`。
- 每次修改前，把原文件复制成同目录下的 `settings.json.<UTC 时间>.bak`。
- 回滚：点 **Use System**；或手动删掉 `env.TZ`；或用 `.bak` 覆盖回去。Desktop 只是启动参数，正常重新打开即恢复。

## 构建

依赖 [Tuist](https://tuist.dev)（版本见 `.mise.toml`）和 Xcode。

```bash
./run-app.sh               # 生成工程、构建 Debug 并启动
scripts/install-app.sh     # 构建 Release 并装到 ~/Applications

TUIST_SKIP_UPDATE_CHECK=1 tuist generate --no-open
xcodebuild test -workspace CTimezone.xcworkspace -scheme CTimezoneKit \
  -destination 'platform=macOS' -derivedDataPath .build CODE_SIGNING_ALLOWED=NO
```

## 发布（维护者）

推一个 `vX.Y.Z` 标签，`.github/workflows/release.yml` 会构建通用二进制、打 DMG、发 GitHub Release，再把签好名的 appcast 推到 `gh-pages`。

```bash
git tag v0.2.0 && git push origin v0.2.0
```

一次性准备：

- `scripts/export-sparkle-key.sh <owner/repo>`：把钥匙串里的 Sparkle 私钥写进仓库的 `SPARKLE_PRIVATE_ED_KEY` secret。私钥丢失意味着已安装的副本再也收不到更新。
- 仓库 Settings → Pages 指向 `gh-pages` 分支。

## 致谢

- [Sparkle](https://github.com/sparkle-project/Sparkle)（MIT）负责自动更新。
- 世界地图的陆地数据来自 [Natural Earth](https://www.naturalearthdata.com)（公共领域）。
- 时区坐标在运行时读取 macOS 自带的 `/usr/share/zoneinfo/zone.tab`。

## License

[AGPL-3.0](LICENSE)。修改后分发或作为网络服务提供时，需要以同一许可证公开源码。
