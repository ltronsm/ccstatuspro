# ccstatuspro

A focused, opinionated Claude Code status line. Two lines, no TUI, no widget zoo — just the four numbers I actually look at while coding: **session context, 5-hour quota, time until reset, git state**. Updates every second so you always know how close you are to the wall.

```
[opus-4.6·1M] │ agent-roc (main*) │ ⏱ 4m │ ████ ▌ 281k / 1M ▐ ░░░░░ 28%

Usage: ███ ▌ 2.6M / 15.3M ▐ ░░░  17%  ⏱ 4h04m  ⟳ 6:00pm
```

---

## Why this exists

The Claude Code statusline ecosystem has good general-purpose tools (notably [`ccstatusline`](https://github.com/sirmalloc/ccstatusline) at 7k+ stars). They're highly configurable, have TUIs, themes, dozens of widgets. They also have a JSON config you maintain and a learning curve.

I wanted the opposite: a single shell script with **no configuration**, that shows exactly the four things I check most often, in a layout I never have to think about. If a number on the screen surprises you, the statusline failed.

The thing that doesn't exist anywhere else, as far as I've found:

- **A 5-hour usage bar with the running token count overlaid on the bar itself**, not next to it. So `▌ 2.6M / 15.3M ▐` reads as one unit — the colored fill behind the digits *is* the percentage.
- **A pseudo-blink at ≥95%** that works in Apple Terminal (which ignores real ANSI blink). Driven by `refreshInterval: 1` toggling the bar shade between `red` and `bright-red` each second.
- **Reset countdown computed locally** from JSONL session logs, not from the API. The `oauth/usage` endpoint rate-limits aggressively at 1 req/sec; computing `block_start + 5h` from the earliest user message in the last 5 hours gives the same answer with zero API dependency.

---

## What you see, segment by segment

### Line 1 — session

```
[opus-4.6·1M] │ agent-roc (main*) │ ⏱ 4m │ ████ ▌ 281k / 1M ▐ ░░░░░ 28%
└──────┬─────┘   └────┬────┘ └─┬┘    └┬┘   └─────────────┬───────────┘
   model name         git    dirty   uptime         context bar
```

| Segment | What it tells you |
|---|---|
| `[opus-4.6·1M]` | Active model, shortened. `·1M` suffix when the 1M-context variant is in use. |
| `agent-roc` | Current working directory (basename). |
| `(main*)` | Git branch with `*` if there are uncommitted changes. Hidden if not in a repo. |
| `⏱ 4m` | How long this session has been alive (`cost.total_duration_ms`). |
| `▌ 281k / 1M ▐` | **Context bar**: tokens used in the current conversation versus the model's window. Read directly from the latest `message.usage` block in the session transcript. |
| `28%` | Same context usage as a percentage — color-coded same as the bar (orange / red / flashing-red). |

### Line 2 — 5-hour rate-limit block

```
Usage: ███ ▌ 2.6M / 15.3M ▐ ░░░  17%  ⏱ 4h04m  ⟳ 6:00pm
       └──────────┬──────────┘  └┬┘  └──┬──┘  └──┬───┘
                  │              │      │        │
            usage bar      percentage  countdown  wall-clock
```

| Segment | What it tells you |
|---|---|
| `▌ 2.6M / 15.3M ▐` | **Used / quota**. Used = billable token sum (input + output + cache-creation) across every session in the last 5 hours, scanned from `~/.claude/projects/**/*.jsonl`. Quota = back-calculated from `used / pct` since Anthropic doesn't publish it directly. |
| `17%` | The authoritative 5-hour utilization from Claude Code (passed via stdin) or the `oauth/usage` API (cached 5 min, fallback). |
| `⏱ 4h04m` | **Countdown** until the 5-hour block resets. Computed from the earliest user message in the last 5 hours + 5h. |
| `⟳ 6:00pm` | **Wall-clock time** the block resets, in your local timezone. |

### Color thresholds (both bars)

| Usage | Color |
|---|---|
| 0 – 84% | orange |
| 85 – 94% | red (bold) |
| 95 – 100% | red ↔ bright-red, **toggling each second** (pseudo-blink) |

---

## How it works

### Refresh model

`refreshInterval: 1` in `~/.claude/settings.json` re-runs the script every second, even when the window is idle. This serves two purposes:

1. **Cross-terminal awareness.** If you're burning tokens in another Claude Code window, this terminal sees it within ~1 second because the JSONL scan picks up writes from every session file.
2. **Pseudo-blink.** ANSI blink (`\e[5m`) is silently dropped by Apple Terminal. So at ≥95%, the script picks the red shade based on `$(date +%s) % 2`. Combined with the 1-second refresh, you get a visible pulse without needing real blink support.

### Where each number comes from

| Field | Source | Why |
|---|---|---|
| Model name, cwd, session duration | stdin JSON from Claude Code | always available, cheap |
| Git branch + dirty | `git -C "$cwd" symbolic-ref` + `status --porcelain` | local, fast |
| Context tokens used | last `message.usage` row in `transcript_path` | the only place with current-session token totals |
| 5h percentage | `rate_limits.five_hour.used_percentage` from stdin (newer Claude Code) → falls back to `oauth/usage` API (cached 5 min) | stdin is fast and free; API is the fallback |
| 5h reset time | `rate_limits.five_hour.resets_at` from stdin → API → **local computation** from JSONL | local computation is the most reliable: not subject to API rate limits |
| 5h tokens used (overlay) | `jq -s` over all `~/.claude/projects/**/*.jsonl` files, summing `input + output + cache_creation` for assistant messages in the last 5h | only source of an actual token count; also gives us the block start timestamp for the reset calculation |

### The bar overlay

The bar is 24 cells wide. The token-count text is centered. For each cell position:

- **Inside the filled region, no overlay** → colored block (`█`) on colored background
- **Inside the filled region, overlay character** → bold white digit on the same colored background (digit shows as white-on-color, blends into the bar)
- **Inside the empty region, no overlay** → dim block (`░`) on dim background
- **Inside the empty region, overlay character** → bold white digit on dim background (digit shows as white-on-dark)

Because the *background* matches its surrounding cells, the digits appear to sit *on top of* the bar rather than next to it. The transition between filled and empty walks straight through the digits — at 50% you see the front half of the number lit and the back half dim.

### Why no API for the reset time

Earlier versions called `oauth/usage` every second to fetch `resets_at`. At 1 req/sec, Anthropic returns:

```json
{ "error": { "type": "rate_limit_error", "message": "Rate limited. Please try again later." } }
```

…and the reset time goes blank, which silently truncates line 2.

The fix: scan JSONL session logs for the earliest user-message timestamp in the last 5 hours, add 5 hours, that's the reset. Anthropic's 5-hour rolling window starts on your first message after a quiet period, so this matches the official number to within seconds. No API dependency, no rate limit risk.

---

## Install

### Requirements

- macOS or Linux
- `bash`, `jq`, `curl`, `git`
- Claude Code with statusline support (`refreshInterval` field in `settings.json`)
- A terminal that supports 24-bit color (Apple Terminal, iTerm2, Ghostty, Alacritty, Kitty, etc.)

### Quick install

```bash
git clone https://github.com/ltronsm/ccstatuspro.git ~/ccstatuspro
bash ~/ccstatuspro/install.sh
```

That's it. The installer:

1. Confirms `bin/ccstatuspro` is executable.
2. Merges (not replaces) a `statusLine` block into `~/.claude/settings.json`.
3. Leaves all your other Claude Code settings alone.

Open Claude Code (or restart) and the new statusline appears.

### Manual install

If you'd rather not run the installer, copy the block from `settings.example.json` into `~/.claude/settings.json` yourself:

```json
{
  "statusLine": {
    "type": "command",
    "command": "bash ~/ccstatuspro/bin/ccstatuspro",
    "refreshInterval": 1,
    "padding": 0
  }
}
```

### Preview the config without installing

```bash
bash ~/ccstatuspro/install.sh --print
```

### Terminal setup (macOS Terminal.app users)

The statusline refreshes every second. Apple Terminal's "Active process name" feature will then flicker the title bar between subprocess names (`jq`, `tr`, `caffeinate`, etc.) as the script runs. One-time fix:

**Terminal → Settings → Profiles → [your profile] → Window tab → Title** — uncheck **"Active process name"**.

Close and reopen the Terminal window to apply. iTerm2, Ghostty, Alacritty, and Kitty don't have this behaviour by default.

---

## Caveats

- **Back-calculated quota wobbles ±10%.** The `15.3M` denominator comes from `tokens_used / percentage × 100`. My token sum (from JSONL) and Anthropic's percentage (cache-discount-aware) use different accounting, so the back-calculated cap drifts as the ratio shifts. The percentage itself is always authoritative — only the implied cap is a soft estimate.
- **Apple Terminal ignores `\e[5m` (real blink).** This is why the 95% warning uses a 1-second color toggle instead. iTerm2 and Ghostty users get the same behavior — pseudo-blink works everywhere.
- **The script runs every second.** It scans JSONL files every tick. With ≤10 session files this stays under 100ms; if you have hundreds of historic sessions, render time will climb. Trim `~/.claude/projects/` periodically if you notice lag.
- **Personal-use defaults baked in.** No theming, no widget toggles, no config file. To customize colors or widths, edit `bin/ccstatuspro` directly — it's ~390 lines of bash and well-commented.

---

## Comparison with `ccstatusline`

[`ccstatusline`](https://github.com/sirmalloc/ccstatusline) is the right choice if you want themes, 40+ widgets, an interactive TUI configurator, and powerline rendering. It's mature, popular, and genuinely impressive.

`ccstatuspro` is the right choice if you want:

- A single 400-line bash script you can read end-to-end and modify
- Zero configuration steps
- A 5-hour usage bar with token count *overlaid on* the bar (not next to it)
- A genuinely live cross-terminal view (1-second refresh, no caching)
- A reset countdown that doesn't depend on the rate-limited API

Both can co-exist on disk; only one can be the active `statusLine`.

---

## License

MIT — see [`LICENSE`](LICENSE).
