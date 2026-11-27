<div align="center">

<img src="logo.png" width="88" height="88" alt="Cairn Logo" />

# Cairn

Keep track of your AI coding agents right from the MacBook notch.

[English](README.md) · [简体中文](README.zh-CN.md) · [Releases](https://github.com/zepeng-jin/Cairn/releases)

</div>

---

## Features

- **Minimalist Notch Bar**: Shows the most active agent on the left and its live status on the right (thinking, reading, editing, creating, running, searching, delegating, compacting). Displays a clean green dot when an unread reply finishes.
- **Session Hub**: Hover or click to expand all active and recent sessions. Filter by **All / Unread / Running / Pinned**, search conversations, pin or archive cards, configure silence rules, and jump straight back to the exact terminal tab, IDE window, or Claude Desktop conversation.
- **Inline Approvals & Questions**: Approve or deny tool calls, batch-approve pending prompts, toggle turn bypass, or answer agent questions without leaving your current window.
- **Subagent & Task Tracking**: View nested subagent trees (including Antigravity Swarm workers) and live task checklists directly inside each session card, with root-only alert options.
- **Customizable Appearance**: Switch between Comfortable, Compact, and Minimal card layouts, Pure Black or translucent vibrancy surfaces, custom accent colors, panel width, and hover delay — with a live preview in Settings.
- **Broad Agent Support**: Works locally with Claude Code (CLI, Desktop, Cowork, 3P), Google Antigravity, Codex, Cursor, Windsurf, Gemini CLI, OpenCode, Qwen Code, Trae, Qoder, Cline, and other hook-enabled agents. No cloud relay, no telemetry.

## Installation

### Download

1. Download `Cairn.dmg` from [GitHub Releases](https://github.com/zepeng-jin/Cairn/releases) (macOS 14+, Apple Silicon).
2. Drag `Cairn.app` into `/Applications`.
3. If macOS Gatekeeper blocks first launch on an unnotarized build, run:
   ```bash
   xattr -cr /Applications/Cairn.app
   ```
4. Launch Cairn and enable the hooks for your agents in **Settings**.

### Build from Source

Requires macOS 14+ and Xcode / Swift 5.9+:

```bash
git clone https://github.com/zepeng-jin/Cairn.git
cd Cairn
swift build
```

To build a standalone `.app` bundle:

```bash
./build.sh
```

## License & Acknowledgements

Released under the [GNU General Public License v3.0](LICENSE) (`GPL-3.0`). Any redistributed modifications or derivative works must also be released under GPL-3.0.

Built upon [wxtsky/CodeIsland](https://github.com/wxtsky/CodeIsland) (original MIT copyright notice preserved in [THIRD_PARTY_LICENSES.md](THIRD_PARTY_LICENSES.md)) — thanks to `@wxtsky` and all contributors for the original foundation and hook ecosystem.
