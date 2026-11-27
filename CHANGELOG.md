# Changelog

All notable changes to FlowIsland are documented in this file.

FlowIsland is built on the MIT-licensed foundation of [wxtsky/CodeIsland](https://github.com/wxtsky/CodeIsland).

## [v1.1.2] - 2026-11-27

### English
- **Hover-to-Expand While Auto-Hidden**: When **Auto-hide When No Active Session** is enabled, moving the pointer over the notch still smoothly reveals and expands the Session Hub panel, then hides cleanly again after the collapse animation finishes.
- **Optional Menu Bar Icon**: Added a **Show Menu Bar Icon** toggle beneath **Auto-hide When No Active Session** so you can keep the menu bar completely clean and still expand via notch hover.
- **Subagent Activity Accounting**: Included active subagents in `deriveSessionSummary` so auto-hide never hides the island while Swarm workers or subagents are still running.

### 中文
- **自动隐藏后支持悬停展开**：开启「无活跃会话时自动隐藏」后，平时隐藏不占空间，鼠标移到刘海区域仍可正常悬停展开面板，移开播完收起动画后再自动隐藏。
- **可选隐藏菜单栏图标**：在「无活跃会话时自动隐藏」下方新增「显示菜单栏图标」开关，可关闭顶部菜单栏图标保持简洁，同时照常通过悬停刘海唤出面板。
- **子代理活跃计数修复**：`deriveSessionSummary`计入子代理运行状态，避免主对话暂停但子代理仍在干活时被误判空闲而自动隐藏。

## [v1.1.1] - 2026-11-27

### English
- **Collapsed Notch Width & Polish**: Set the notched MacBook collapsed-width slider minimum to `100%` (`100%–150%`), removed dead padding so `100%` hugs the physical camera cutout closely (`-59pt` to `-66pt`), synced display-choice changes without per-drag IPC, and fixed GPU shimmer sweeps freezing after Space switches or panel transitions.
- **Stable Ordering & Adaptive Model Tags**: Sorted the session list stably by pinned order then main conversation creation time (`startTime` descending) so cards stop jumping on tool updates; locked the collapsed bar to the topmost active conversation in that same order; and widened model badges adaptively up to `220pt` using proportional font metrics.
- **Subagent Trees & Active Delegating State**: Auto-synthesized parent coordinator cards when Swarm workers arrive first, kept small subagent trees expanded by default, lit up parent cards green (with awake mascot and `Delegating` status) while subagents are working, and fixed a Swift exclusivity conflict crash during subagent folding.
- **Quieter Sound & Zero-Stutter Clicks**: Resolved Swarm worker parent links synchronously before sound decisions so subagents stay silent under root-only mode, surfaced the subagent notification timing picker directly in Sound Settings, quieted default session-start/boot chimes, and eliminated completion-card click stutter by keeping single-card collapse layout and moving LaunchServices activation off the main thread.
- **Reliability & Layout Fixes**: Synced silhouette paths on bounds resize, applied `notchAnimationSpeed` scaling to GPU transitions, prevented clipped bottom gaps on tall cards, added an archived-sessions toggle to the top bar, cleared stale compaction/`liveCodexOutput` states on idle, improved prompt-prefix silence filtering and unread badge coverage, and added concurrent `Claude` / `Claude-3p` watching.

### 中文
- **刘海收起态宽度与动效优化**：刘海屏 MacBook 的「收起态宽度」下限修正为真实物理刘海 `100%`（`100%–150%`），移除多余盲留白使 `100%` 紧贴刘海（缩窄 `59–66pt`），联动多屏切换且无拖动 IPC 开销；修复切桌面或展开收起后状态扫光偶发卡死的问题。
- **稳定排序与模型标签自适应**：会话列表严格按「手动置顶 → 主对话创建时间最新」稳定排序，不再随工具刷新乱跳；收起态顶栏按同一顺序优先锁定最靠前的活跃主对话；模型标签改用比例字体测宽并放宽至自适应 `220pt`，长模型名完整显示。
- **子代理树与协作中状态**：Swarm 子代理先于主对话到达时自动合成父节点折叠成树，小规模子代理默认展开可见；子代理运行期间主对话自动亮绿灯、保持工作吉祥物并在顶栏显示「协作中」；修复折叠更新时的 Swift 独占访问闪退。
- **声音防乱响与完成弹窗零卡顿**：发声决策前同步补查 Swarm 父子关系确保子代理在「仅主对话」模式下严格静音，在声音设置页直接提供子代理提醒时机选择，默认关闭会话开始与启动音效；修复完成弹窗点击收起首帧爆出全列表与主线程阻塞 LaunchServices 导致的卡顿。
- **稳定性与布局修复**：修复面板尺寸变化后遮罩路径错位，统一应用动画速度设置，修复长命令与大字号列表底部裁切，顶部栏新增归档会话切换，空闲时自动清理压缩状态与残留输出文本，完善 Prompt 前缀静默规则与未读角标覆盖，并支持 `Claude` 与 `Claude-3p` 双目录并发监听。

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
