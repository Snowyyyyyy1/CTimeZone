# 更新日志

每个版本的说明会原样出现在 GitHub Release 和应用内的更新提示里。发版前必须先在这里写好对应版本的条目，否则发布流程会停下。

## 0.2.0 — 2026-10-10

### 新增

- **Dock 启动器**：在 CTimeZone 的「Dock Launcher」一行点 **Add to Dock…**，会在 `~/Applications` 生成 `Claude · <城市>.app`。把它拖进 Dock，以后直接点它打开 Claude，不用再先开 CTimeZone。Spotlight 和 Raycast 也能搜到。
- 启动器按当时的设置处理三种情况：
  - Claude 没在运行：按目标时区启动；
  - Claude 已经以目标时区运行：直接切到前台；
  - Claude 以别的时区运行：先询问 **Relaunch**（正常退出后按目标时区重启）还是 **Just Open**（直接切到前台）。
- 在 CTimeZone 里换时区后，启动器会自动改名（例如 `Claude · Tokyo`），Dock 里的图标继续可用。
- 启动器图标在本机用你的 Claude 图标加一个 CTimeZone 小角标生成。

### 改进

- 默认窗口尺寸下能完整显示全部内容，包括新增的启动器一行。

### 说明

- 启动器随 CTimeZone 一起自动更新，不需要单独下载。
- Claude 运行时，Dock 里会同时出现启动器和 Claude 本身两个图标，这是系统行为。建议把官方 Claude 图标移出 Dock，只留启动器。

## 0.1.0 — 2026-10-10

首个公开版本。

- 不改系统时区，单独为 Claude Code（`~/.claude/settings.json` 的 `env.TZ`）和 Claude Desktop（启动环境）设置时区。
- 点阵世界地图，实时显示昼夜，并标出 Mac 和 Claude 的时区位置；两个时钟显示时差。
- 时区列表可按城市或地区搜索，显示 GMT 偏移。
- 基于 Sparkle 的自动更新，更新包用 EdDSA 签名校验。
