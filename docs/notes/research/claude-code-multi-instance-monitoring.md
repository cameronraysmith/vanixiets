# Monitoring dozens of Claude Code instances at once

**Claude Code's hooks system is the foundational layer for all monitoring and notification approaches**, providing 12 lifecycle events that can trigger shell commands, AI evaluations, or subagent checks. Around this official primitive, a rich ecosystem of community-built session managers, orchestration platforms, and dashboards has emerged—led by Claude Squad (6k stars), Claude-Flow (11.4k stars), and CCManager (831 stars). For teams running 5–50+ concurrent instances, the most robust approach in February 2026 combines the official Claude Agent SDK for programmatic control, hooks-driven notifications via ntfy.sh or Slack webhooks, and a TUI session manager like Claude Squad or CCManager for visual oversight.

Anthropic also ships built-in OpenTelemetry support for enterprise observability, an experimental Agent Teams feature for native multi-agent coordination, and a full TypeScript/Python SDK for programmatic spawning and streaming. No official real-time multi-session dashboard exists yet, but several community tools fill that gap convincingly.

---

## The hooks system powers everything

Claude Code's hooks system is the single most important feature for monitoring. Configured in `~/.claude/settings.json` (user-wide), `.claude/settings.json` (project), or `.claude/settings.local.json` (local), hooks fire at **12 lifecycle events** that cover the full agent lifecycle:

| Event | Purpose for monitoring |
|-------|----------------------|
| **Stop** | Agent finished responding—trigger completion alerts |
| **Notification** | Agent needs attention (idle, permission prompt, auth) |
| **SubagentStop** | A delegated subagent completed its work |
| **SubagentStart** | A subagent was spawned |
| **SessionStart / SessionEnd** | Track session lifecycle across instances |
| **PreToolUse / PostToolUse** | Monitor tool execution in real time |
| **PermissionRequest** | Agent is blocked waiting for permission |
| **UserPromptSubmit** | User submitted input |

Three hook execution types exist. **Command hooks** run shell scripts and receive event JSON on stdin—ideal for sending notifications. **Prompt hooks** invoke Claude Haiku for single-turn evaluation (e.g., "does this tool call look safe?"). **Agent hooks** spawn a subagent with Read/Grep/Glob tools to verify conditions before proceeding.

A practical notification configuration looks like this:

```json
{
  "hooks": {
    "Notification": [{
      "matcher": "permission_prompt|idle_prompt",
      "hooks": [{ "type": "command", "command": "curl -d \"Claude needs input\" ntfy.sh/$NTFY_TOPIC" }]
    }],
    "Stop": [{
      "matcher": "",
      "hooks": [{ "type": "command", "command": "terminal-notifier -message 'Task complete' -sound default" }]
    }],
    "SubagentStop": [{
      "matcher": "",
      "hooks": [{ "type": "command", "command": "/path/to/log-subagent-completion.sh" }]
    }]
  }
}
```

Hooks run asynchronously by default—Claude continues without waiting. Exit code 0 means success, exit code 2 feeds stderr back to Claude as a blocking error. Hooks can also return structured JSON with fields like `decision`, `reason`, `permissionDecision`, and `systemMessage` for fine-grained control. The `/hooks` slash command inside Claude Code provides an interactive manager for viewing, adding, and deleting hooks without editing files. Default timeout is **60 seconds**, configurable up to 10 minutes for tool hooks.

---

## Official Anthropic infrastructure beyond hooks

Anthropic provides several official capabilities beyond the hooks system that matter for multi-instance monitoring.

**The Claude Agent SDK** (formerly "Claude Code SDK") is available as `@anthropic-ai/claude-agent-sdk` on npm and as a Python package. It exposes an async generator-based `query()` function that streams `SDKMessage` objects in real time, with full support for hooks, subagents, MCP servers, abort controllers, and budget caps. This is the correct foundation for building custom monitoring dashboards—you can programmatically spawn dozens of instances, stream their events, and react to state changes. The SDK supports `includePartialMessages` for real-time streaming and `--output-format stream-json` for NDJSON event streams from the CLI.

**OpenTelemetry integration** is built into Claude Code and activated via environment variables:

```bash
export CLAUDE_CODE_ENABLE_TELEMETRY=1
export OTEL_METRICS_EXPORTER=otlp
export OTEL_LOGS_EXPORTER=otlp
export OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4317
```

This exports events like `claude_code.user_prompt`, `claude_code.tool_result`, `claude_code.api_request`, and `claude_code.api_error` with attributes including tool name, duration, cost, and model info. The community project **claude-code-otel** provides a complete Docker Compose stack routing this data through an OTel Collector into Prometheus + Loki + Grafana, with pre-built dashboards.

**Agent Teams** is Anthropic's experimental built-in multi-agent feature, enabled with `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`. A Team Lead spawns Teammates as independent Claude Code instances, each with their own context window. They communicate through a peer-to-peer inbox system and coordinate via a shared task list with dependency tracking. In tmux or iTerm2, teammates appear as split panes. This is the native approach to multi-agent work but has limitations: no session resumption with in-process teammates, no nested teams, and each teammate consumes a full Claude instance's tokens.

**Console analytics** at `console.anthropic.com/claude-code` provide organization-level metrics: lines of code accepted, daily active users/sessions, spend, and per-user breakdowns. The Analytics API exposes this programmatically. However, **no official real-time multi-session dashboard exists** for watching live agent activity across instances.

---

## Session managers for visual oversight of many agents

For the day-to-day experience of watching 5–50 concurrent instances, community-built TUI session managers are the most practical tools.

**Claude Squad** (smtg-ai/claude-squad, **6k stars**, AGPL-3.0) is the most popular. It provides a terminal TUI managing multiple AI agents in separate tmux-backed workspaces with git worktree isolation. Each agent works on its own branch, preventing code conflicts. Install with `brew install claude-squad` and run with `cs`. It supports auto-yes mode (`cs -y`), custom programs (Aider, OpenCode, Gemini CLI), and background task completion. The main limitation is its hard tmux dependency.

**CCManager** (kbwo/ccmanager, **831 stars**, MIT) is a self-contained alternative requiring no tmux. It displays actual session state (active/busy/waiting) directly in its menu, supports session data copying for git worktrees, and offers **state hooks**—custom commands that fire on session status changes. It handles Claude Code, Gemini CLI, Codex CLI, Cursor Agent, and others. Multi-project mode (`npx ccmanager --multi-project`) is particularly useful for managing agents across repositories. CCManager also includes an auto-approval feature using Claude Haiku to analyze and approve safe operations.

**Agent of Empires** (njbrake/agent-of-empires) is a Rust-based TUI with Docker sandboxing, diff views for reviewing git changes, and per-repo configuration. **claude-tmux** (nielsgroen/claude-tmux) provides a Ratatui-based TUI with live ANSI-colored preview of selected sessions, fuzzy filtering, and git worktree support, accessible via `Ctrl-b, Ctrl-c` from any tmux session.

For larger-scale orchestration, **Claude-Flow** (ruvnet/claude-flow, **11.4k stars**) is an enterprise-grade platform with 60+ specialized agents, swarm intelligence, and 175+ MCP tools. **claude-code-orchestrator** (mohsen1) uses the Claude Agent SDK with a Director → Engineering Managers → Workers architecture for fully hands-off long-horizon tasks with API key rotation. **ccswarm** (nwiizo) provides Rust-native orchestration with a master Claude for intelligent task delegation and 93% token reduction via session persistence.

---

## Notification approaches ranked by use case

The notification landscape has matured significantly. Here are the most robust approaches by scenario.

**For mobile push notifications**, ntfy.sh is the clear winner—a single `curl` command in a hook sends push notifications to any phone. The public server works for personal use; self-host with token auth for teams. **Pushover** offers more reliable delivery with priority levels and quiet hours. The dedicated **claudecode-pushover-integration** package adds rate limiting (max 1 notification per 30 seconds) and smart queueing. **Pushcut** (iOS, $2/month) integrates with Apple Watch and can detect whether your terminal is focused, only sending notifications when you're away.

**For team visibility**, Slack webhooks are straightforward—a `curl` POST in a Stop or Notification hook. The **claude-notifications-go** plugin provides preset webhook formats for Slack (color-coded attachments), Discord (rich embeds), and Telegram (bot-based). Anthropic also ships a native Claude Code Slack integration where `@Claude` in channels creates web sessions with thread-based progress updates.

**For local desktop alerts**, `terminal-notifier` (macOS) or `notify-send` (Linux) are the standards. The cross-platform **code-notify** tool (`brew install mylee04/tools/code-notify`) supports Claude Code, Codex, and Gemini CLI with unified notification, sound, and voice configuration via simple `cn on`, `cn sound on`, `cn voice on` commands. The **Claude Code Notifier** macOS menu bar app adds session tracking, webhook support, quiet hours, and iOS/Android companion apps.

**For remote SSH sessions**, OSC escape sequences are a hidden gem—`printf '\033]777;notify;Title;Message\007'` works through SSH tunnels in VS Code (with the Terminal Notification extension), iTerm2, and Windows Terminal. This means hooks can trigger notifications on your local machine even when Claude Code runs on a remote server, with zero additional infrastructure.

---

## Remote server patterns that actually work

Running Claude Code on remote servers is common for leveraging powerful hardware or maintaining persistent sessions. The dominant pattern combines three layers: **mosh for connection resilience, tmux for session persistence, and hooks for notifications**.

Mosh (Mobile Shell) is critical for mobile or intermittent connections—it survives WiFi-to-cellular transitions, handles phone sleeping, and reconnects after tunnel outages. Combined with tmux, sessions persist regardless of connection state. A proven architecture from community blogs: Phone (Termux/Blink) → mosh → jump server → SSH → work server running Claude Code in tmux. One-command aliases make this ergonomic: `alias cc="mosh home -- ssh -t work 'tmux attach -t claude'"`.

**Tailscale** is the most recommended VPN for simplicity—zero-config mesh networking that makes remote servers accessible from anywhere. The **claude-code-monitor** tool by onikan27 explicitly supports Tailscale for remote access to its mobile web UI (`ccm -t`), providing a QR code for phone access.

**Web-based terminal solutions** like **ttyd** (`ttyd -p 7681 tmux attach -t claude`) or **GoTTY** share terminal sessions over WebSocket, enabling browser-based monitoring of Claude Code sessions. For a more complete remote development experience, **code-server** (VS Code in the browser) alongside tmux provides both code editing and terminal monitoring.

Anthropic's own cloud execution feature—prefixing messages with `&` to hand off tasks to claude.ai web sessions—provides built-in remote persistence. Sessions continue if your laptop closes and can be monitored from the iOS app, though session handoff back to CLI is one-way.

---

## Audio and TTS for ambient awareness

Audio feedback creates ambient awareness of agent fleet status without requiring constant visual attention—particularly valuable when managing many instances.

The simplest approach uses macOS's built-in `say` command or Linux's `espeak` in a Stop hook. A particularly clever pattern pipes the hook's JSON through Claude itself for summarization before speaking: `MESSAGE=$(claude -p "Summarize in 20 characters: \"$1\"") && say "$MESSAGE"`. Different system sounds (Glass for completion, Basso for errors, Funk for permission requests) create an audio vocabulary for agent states.

**cc-hooks** (husniadil/cc-hooks) is the most comprehensive audio plugin, supporting multiple TTS providers with smart fallback chains: prerecorded sounds (offline) → Google TTS (free) → ElevenLabs (premium). It provides multi-language support, contextual AI-generated messages ("I've successfully implemented the authentication system"), and per-session configuration so parallel terminals can use different audio profiles.

**code-notify** includes built-in voice mode (`cn voice on`) with cross-platform TTS support. **Claude-to-Speech** uses ElevenLabs with invisible HTML comment markers that a Stop hook extracts and speaks. **VoiceMode MCP** goes further with full voice conversation support—local STT via Whisper, local TTS via Kokoro, and hands-free mode with smart silence detection.

The **disler/claude-code-hooks-mastery** repository (3k stars) serves as the reference implementation, including TTS alerts with a 30% chance of including the agent name for variety, AI-generated completion messages, and an LLM priority chain (OpenAI → Anthropic → Ollama → random fallback) for generating spoken summaries.

---

## Real-time dashboards for fleet monitoring

Several community dashboards provide visual oversight of multiple concurrent sessions.

**claude-code-hooks-multi-agent-observability** (disler) is purpose-built for multi-agent monitoring. It uses hooks to trace every tool call across all agents, displays a live timeline with agent swim lanes, tracks task lifecycle events, and shows an activity density pulse chart across the agent fleet. Built with Bun TypeScript + Vue 3 + WebSocket + SQLite.

**claude-code-ui** (KyleAMathews) provides a web dashboard showing what each Claude session is working on, which sessions need approval, and PR/CI status. It integrates with hooks for permission notifications and generates AI summaries of session state (requires an Anthropic API key). Uses Durable Streams for real-time updates.

**claude-code-monitor** (onikan27) offers a combined CLI + mobile web UI with QR code access. It auto-sets up hooks on first run, supports terminal focus switching between iTerm2, Terminal.app, and Ghostty, and provides Tailscale-based remote access. Currently macOS only.

For usage analytics rather than live monitoring, **ccusage** (ryoppippi) analyzes local JSONL session files for daily/monthly/session reports with multi-instance support (`--instances` flag). **Claude-Code-Usage-Monitor** provides a Rich terminal UI with burn rate analytics, cost projections, and session forecasting across Pro, Max5, Max20, and custom plans. **claude-usage-dashboard** (Genius-Cai) is a full Next.js + FastAPI PWA with live WebSocket updates, session timers, and interactive charts.

For OpenTelemetry-based observability, **claude-code-otel** (ColeMurray) provides a complete Grafana stack with pre-built dashboards, and the **SigNoz Claude Code Dashboard** offers a pre-built template for OTel data.

---

## Conclusion

The Claude Code monitoring ecosystem in February 2026 is surprisingly mature, built on a well-designed hooks primitive. **The recommended stack for managing 5–50+ instances** is: the Claude Agent SDK for programmatic spawning and streaming, CCManager or Claude Squad for TUI-based visual oversight, hooks-driven ntfy.sh or Slack notifications for attention routing, and either the disler multi-agent observability dashboard or an OTel → Grafana pipeline for real-time fleet visibility.

The most significant gap remains the absence of an official Anthropic multi-session dashboard—everything beyond aggregate analytics requires community tooling. Agent Teams addresses multi-agent coordination natively but not monitoring. For remote workflows, the mosh + tmux + hooks + ntfy.sh combination is battle-tested. For audio awareness, cc-hooks with Google TTS provides the best balance of features and simplicity.

Three patterns stand out as particularly effective for scale: using the SDK's `stream-json` output to build custom aggregation pipelines, leveraging SubagentStop hooks for cascading notifications in hierarchical agent setups, and combining OSC escape sequences with SSH for zero-infrastructure remote notifications. The ecosystem is evolving rapidly—tools like CCManager and Claude Squad are adding features monthly, and Anthropic's own Agent Teams feature will likely gain monitoring capabilities as it exits experimental status.