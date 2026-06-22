# 🐾 meow-claude-code

A one-line **MEOW** wake-up for Claude Code.

Claude Pro/Max usage limits run on a rolling ~5-hour window that begins at your
**first** prompt. `meow.sh` sends a tiny `MEOW` to the cheap **haiku** model so
you can anchor that window to a fixed time each morning (default **07:00**)
instead of whenever you happen to start working.

```
███╗   ███╗███████╗ ██████╗ ██╗    ██╗
████╗ ████║██╔════╝██╔═══██╗██║    ██║
██╔████╔██║█████╗  ██║   ██║██║ █╗ ██║
██║╚██╔╝██║██╔══╝  ██║   ██║██║███╗██║
██║ ╚═╝ ██║███████╗╚██████╔╝╚███╔███╔╝
╚═╝     ╚═╝╚══════╝ ╚═════╝  ╚══╝╚══╝

   /\_/\   < meow! >  poking Claude Code awake...
  ( o.o )
   > ^ <
  (")_(")
```

## Install (recommended)

```bash
git clone <this-repo> && cd meow-claude-code
chmod +x install.sh
./install.sh            # interactive: asks before each step
```

`install.sh` walks you through it and **asks permission before each step**:

1. Copy `meow.sh` into `~/Library/Application Support/meow-claude-code/`
2. Add a `meow` command to `~/.local/bin` (so you can run `meow` from anywhere)
3. Schedule the daily MEOW via launchd (prompts for a time, default `07:00`)

Use `./install.sh --yes` to accept all defaults non-interactively. After
installing, run it any time with just `meow`.

Requires the [`claude`](https://claude.com/claude-code) CLI, installed and
logged in (run `claude` once interactively to sign in).

## Just try it once (no install)

```bash
./meow.sh               # cat art + sends MEOW now, prints Claude's reply
```

Every run appends a timestamped line to `~/.meow-claude.log`.

## Schedule a daily MEOW

> If you used `install.sh`, the schedule is already set — use `meow` in place of
> `./meow.sh` below to change it.

### macOS — use launchd (recommended)

```bash
./meow.sh --start          # daily @ 07:00 (default)
./meow.sh --start 09:30    # daily @ 09:30 (any HH:MM, 24-hour)
./meow.sh --stop           # stop it
```

`--start` schedules a launchd LaunchAgent (you can also write `meow start` /
`meow stop`).

A launchd LaunchAgent runs inside your logged-in session, so it can read your
credentials from the login keychain. The installer also copies the script to
`~/Library/Application Support/meow-claude-code/` and points the job there —
schedulers can't execute files in protected folders like `~/Documents`, so this
keeps the daily run working. (Tested end-to-end: a triggered run authenticates
and logs `MEOW sent`.)

**Verify it fires** (runs the job on demand in its real scheduled context):

```bash
launchctl kickstart -p "gui/$(id -u)/com.meow-claude-code"
sleep 30 && tail -n1 ~/.meow-claude.log    # expect: ... MEOW sent (haiku) -> ...
```

### Linux (or cron)

```bash
./meow.sh --install-cron [HH:MM]     # default 07:00
./meow.sh --uninstall-cron
```

The installer manages a single marked crontab line; the equivalent manual entry is:

```cron
0 7 * * * "/path/to/meow.sh" >/dev/null 2>>"$HOME/.meow-claude.log" # meow-claude-code
```

> On **macOS**, cron is not recommended: the cron daemon often can't reach the
> login keychain (runs fail with `Not logged in`) and the `crontab` command
> itself may need **Full Disk Access** (`System Settings → Privacy & Security →
> Full Disk Access`). Use launchd instead.

## Commands

| Command | What it does |
| --- | --- |
| `./install.sh` | Interactive install (copy + `meow` command + schedule), asks before each step |
| `./install.sh --yes` | Install accepting all defaults (time 07:00) |
| `./install.sh --uninstall` | Interactive removal (schedule, command, files), asks before each step |
| `meow` *(or `./meow.sh`)* | Print the art, send `MEOW` (haiku) now, log the result |
| `meow --status` | Show status: CLI, install, `meow` command, schedule, last run |
| `meow --start [HH:MM]` | macOS: start the daily MEOW (default 07:00) |
| `meow --stop` | macOS: stop the daily MEOW |
| `meow --install-cron [HH:MM]` | Schedule a daily MEOW via cron instead (Linux) |
| `meow --uninstall-cron` | Remove the cron job |
| `meow --help` | Show usage |

Once installed, use `meow` from anywhere; otherwise run `./meow.sh` from the repo.

## Where things live

| Path | Purpose |
| --- | --- |
| `~/.meow-claude.log` | One timestamped line per run (`MEOW sent` / `MEOW FAILED`) |
| `~/Library/Application Support/meow-claude-code/meow.sh` | The installed script the scheduler runs (macOS) |
| `~/.local/bin/meow` | Symlink to the installed script (the `meow` command) |
| `~/Library/LaunchAgents/com.meow-claude-code.plist` | The launchd schedule (macOS) |

> Edited `meow.sh` in the repo? Re-run `./install.sh` (or `meow --start`) to
> refresh the installed copy. `meow --stop` only stops the schedule; use
> `./install.sh --uninstall` to remove the installed files too.

## Troubleshooting

- **Nothing happened at 7am** — check `~/.meow-claude.log`. No line means the job
  didn't run; a `MEOW FAILED` line shows why.
- **`Not logged in · Please run /login`** — run `claude` interactively once to sign
  in, then trigger the job again with the `launchctl kickstart` command above.
- **`Operation not permitted`** — a scheduler tried to run the script from a
  protected folder. On macOS the launchd installer avoids this automatically; if
  you see it with cron, move the repo out of `~/Documents`/`~/Desktop`/`~/Downloads`
  or grant Full Disk Access.
