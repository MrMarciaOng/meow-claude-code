# 🐾 meow-claude-code

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

Claude's usage limit runs on a rolling ~5h window that starts at your **first**
prompt. `meow` sends a tiny `MEOW` (cheap **haiku** model) **every 5 hours** from
a time you choose (default **07:00**) to keep a fresh window open all day.

## Install (macOS / Linux)

Run it straight from npm — no clone:

```bash
npx meow-claude-code --start     # schedule every 5h from 07:00
npx meow-claude-code --status
```

Or install the `meow` command globally:

```bash
npm i -g meow-claude-code
meow --start 07:00
```

Or from source (interactive setup, also links a `meow` command):

```bash
git clone <this-repo> && cd meow-claude-code && ./install.sh   # --yes for defaults
```

Needs the [`claude`](https://claude.com/claude-code) CLI, signed in (run `claude`
once). Uninstall: `meow --stop` pauses; `./install.sh --uninstall` removes everything.

## Commands

| Command | What it does |
| --- | --- |
| `meow` | Send a MEOW now (haiku) + print the art |
| `meow --status` | Show install, schedule, and last run |
| `meow --start [HH:MM]` | MEOW every 5h from HH:MM (default 07:00) |
| `meow --stop` | Stop the schedule |
| `meow --install-cron [HH:MM]` / `--uninstall-cron` | Linux: same, via cron |
| `meow --help` | Usage |

`meow --start 07:00` fires at **07:00, 12:00, 17:00, 22:00, 03:00** (5×/day, ~5h
apart). Bare `meow start` / `meow stop` work too. No global install? Use
`npx meow-claude-code <cmd>` (or `./meow.sh <cmd>` from the repo). Each run logs
one line to `~/.meow-claude.log`.

## Notes

- **macOS uses launchd**, which runs in your login session so it can read the
  keychain — plain cron usually can't and fails with `Not logged in`.
- The script installs outside `~/Documents` so the scheduler can execute it
  (protected folders give `Operation not permitted`).
- Not firing? Check `~/.meow-claude.log`; a `MEOW FAILED` line shows why.
