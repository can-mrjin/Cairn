# Changelog

All notable changes to FlowIsland are documented in this file.

FlowIsland is built on the MIT-licensed foundation of [wxtsky/CodeIsland](https://github.com/wxtsky/CodeIsland).

## [v1.1.0] - 2026-11-26

### English
- **Notch Bar & Expanded Panel**: Minimalist collapsed notch bar showing the active agent icon, live phase/status text (thinking, reading, editing, creating, running, searching, delegating, compacting), and an unread completion dot. Configurable hover delay and panel width.
- **Session Hub**: Search sessions, filter by All / Unread / Running / Pinned, pin or archive cards, configure per-project silence rules, clear idle cards, and jump directly back to the matching terminal tab, IDE window, or Claude Desktop thread.
- **Inline Approvals & Questions**: Approve or deny tool calls, batch-approve waiting prompts, toggle per-turn bypass, and answer agent questions directly from the notch panel.
- **Subagent & Task Tracking**: Nested subagent trees (including Antigravity Swarm workers) and live task checklists inside session cards, with configurable root-only alerts.
- **Appearance & Settings**: Comfortable, Compact, and Minimal card layouts, Pure Black or translucent vibrancy surfaces, custom accent colors, and live preview in Settings.
- **Broad Local Agent Support**: Supports Claude Code (CLI, Desktop, Cowork, 3P), Google Antigravity, Codex, Cursor, Windsurf, Gemini CLI, OpenCode, Qwen Code, Trae, Qoder, Cline, and other hook-enabled agents locally with no cloud relay or telemetry.
- **Performance & Packaging**: Shared 20 fps animation clock with targeted redraws, macOS Apple Silicon packaging (`FlowIsland.app` / `FlowIsland.dmg`), and Sparkle update feed configured for `zepeng-jin/FlowIsland`.

### 中文
- **刘海状态条与展开面板**：收起态展示当前活跃的 Agent 图标、实时阶段状态（思考、读取、编辑、创建、执行、搜索、委派、压缩）以及未读完成绿点，支持自定义悬停延迟与面板宽度。
- **会话中心（Session Hub）**：支持关键词搜索、按全部/未读/运行中/置顶筛选、置顶或归档会话卡片、按项目配置静默规则、一键清理空闲卡片，并可点击直达对应终端标签页、IDE 窗口或 Claude 桌面端对话。
- **内联审批与提问**：无需切换当前窗口，即可在面板内批准或拒绝工具调用、批量批准等待中的请求、切换单轮放行并直接回答 Agent 提问。
- **子代理与任务追踪**：在会话卡片内展示嵌套子代理树（含 Antigravity Swarm 工作节点）与实时任务清单，支持仅主会话提醒。
- **外观与设置**：提供舒适、紧凑、极简三种卡片密度，纯黑或毛玻璃材质背景，自定义主题强调色，并支持在设置页实时预览。
- **广泛本地 Agent 支持**：本地兼容 Claude Code（CLI、Desktop、Cowork、3P）、Google Antigravity、Codex、Cursor、Windsurf、Gemini CLI、OpenCode、Qwen Code、Trae、Qoder、Cline 等基于 Hook 的工具，无云端中继与遥测。
- **性能与打包**：采用统一 20fps 动画时钟与局部重绘，面向 macOS Apple Silicon 打包（`FlowIsland.app` / `FlowIsland.dmg`），并将 Sparkle 更新源指向 `zepeng-jin/FlowIsland`。
