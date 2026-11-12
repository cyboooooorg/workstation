# workstation

My development machine, on macOS or Linux (Debian), described by a [mise](https://mise.jdx.dev)
configuration: tools, system packages, dotfiles, tasks and services. This repository **is** the
global mise configuration: `~/.config/mise` is a link to it.

## New machine

```sh
curl -fsSL https://raw.githubusercontent.com/cyboooooorg/workstation/main/install.sh | sh
```

The script installs the prerequisites (git, curl; Homebrew on macOS), then mise into
`~/.local/bin` (an mise already installed is updated instead: `mise bootstrap --from` needs
2026.10.21 or later), and runs:

```sh
mise bootstrap --from https://github.com/cyboooooorg/workstation.git \
  --from-dir ~/Developer/workstation --config-dir . --yes
```

An existing `~/.config/mise` is first moved to `~/.config/mise.bak-<date>`, and an existing
`~/.zshrc` (not a link) to `~/.zshrc.bak-<date>`: copy the machine-specific lines you still need
from the backup into `~/.zshrc.local`.

On Linux, add the user to the docker group afterwards
(`sudo usermod -aG docker $USER`, then log in again).

## Day to day

| Command | Effect |
| --- | --- |
| `mise run up` | `git pull` of this repository, `mise bootstrap`, then updates everything else (tools, Homebrew, apt, snap) |
| `mise bootstrap` | Applies the configuration: what is already in place is left alone |
| `mise bootstrap status` | State of every part (tools, packages, dotfiles…) |
| `mise tasks -g` | Global tasks (Bitwarden, SSH, herdr, Traefik, local services…) |
| `mise run mail`, `cdb`, `tools`, `draw` | Starts a [local service](#local-services-on-demand); add `d` to stop it (`maild`…) |
| `mise run dclean` | [Frees Docker disk space](#docker-cleanup) |
| `mise run vm` | Resizes the [Docker VM](#docker-vm-size-macos) (macOS) |
| `mise run graph` / `graphd` | Sets up / removes [graphify](#graphify-a-code-graph-for-the-agent) in the current repository |
| `mise run g:docker:plugins` | Links the mise `docker-compose` and `docker-buildx` into `~/.docker/cli-plugins` (run by `mise bootstrap`) |
| `mise run g:zsh:completions` | Regenerates the [zsh completions](#zsh-completions) of the tools (run by `mise bootstrap`) |

Changing a tool or a dotfile means changing this repository, in a branch and a pull request:
see [Working on this repository](#working-on-this-repository).

## Contents

```text
config.toml          tools, packages (apt / brew), dotfiles, services: a single file,
                     OS-specific entries carry an `os` key
dotfiles/            files linked into ~ (zshrc) or rendered (kitty.desktop, Linux)
  agents/AGENTS.md   global instructions for coding agents (linked by g:agents:link)
tasks/
  bootstrap          last step of `mise bootstrap`: starts Traefik
  g/                 global `g:*` tasks (agents, bw, claude, docker, graphify, herdr, ssh,
                     traefik, update, and one up / down pair per local service)
  g/_stack.sh        functions shared by the local service tasks
  g/_docker.sh       Docker engine check shared by the traefik and docker tasks
stacks/traefik/      local reverse proxy, one instance for the whole machine
stacks/<service>/    local services started on demand behind Traefik
                     (chartdb, excalidraw, it-tools, mailpit)
install.sh           new machine setup
claude/hooks/        Claude Code hooks (git guard), added by g:claude:settings
tests/               bats tests of the hook and the settings task
.config/mise.toml    tools and lint tasks for working on this repository (not the machine)
.github/workflows/   CI: lint, commit messages, bootstrap dry run
```

| | Linux (Debian) | macOS |
| --- | --- | --- |
| Docker engine | `docker-ce` (official Docker apt repository) | Colima (Homebrew), started at login, [sized on the first bootstrap](#docker-vm-size-macos) |
| docker CLI, compose, buildx | mise (compose and buildx linked into `~/.docker/cli-plugins`) | mise (same) |
| Python (also runs the `pipx:` tools) | mise | mise (no Homebrew `python@*`) |
| kitty | GitHub release (mise) + menu entry | Homebrew cask |
| DBeaver | `dbeaver-ce` (official DBeaver apt repository, amd64 only) | Homebrew cask |
| bash 5 | system | Homebrew (`/bin/bash` stays 3.2) |

Tasks run with the first `bash` on the `PATH`. On macOS that is `/bin/bash` 3.2 until Homebrew is
on the `PATH` (first bootstrap, launchd), so tasks must stay compatible with bash 3.2: no
associative arrays, `mapfile` or `${var,,}`, and `${arr[@]+"${arr[@]}"}` for arrays that may be
empty under `set -u`.

## Coding agents

[`dotfiles/agents/AGENTS.md`](dotfiles/agents/AGENTS.md) holds the rules every coding agent
follows in every project: English documentation (French on request), documentation shipped with
each change, Conventional Commits without emoji, and when to back off from
[graphify](#graphify-a-code-graph-for-the-agent).

`mise bootstrap` runs `mise run g:agents:link` once the tools are installed. The task links this
file to the global instruction file of every agent whose command is on the `PATH`:

| Agent | Command | Global file |
| --- | --- | --- |
| Claude Code | `claude` | `~/.claude/CLAUDE.md` |
| Gemini CLI | `gemini` | `~/.gemini/GEMINI.md` |

- An existing regular file is moved to `<file>.bak-<date>` first; a link to somewhere else is
  replaced.
- When an agent is no longer installed, its link is removed (only if it points to this file).
- To support another agent, add a `command|file` line to `tasks/g/agents/link`, then run
  `mise run g:agents:link` (installing an agent later does not need a full `mise bootstrap`).

Instructions shipped by a project take precedence over these.

`mise bootstrap` also runs `mise run g:claude:plugins`, which installs the missing Claude Code
plugins and updates the installed ones (so `mise run up` keeps them current):

| Plugin | Marketplace |
| --- | --- |
| [Superpowers](https://github.com/obra/superpowers) | `claude-plugins-official` (built in) |

To add one, add a `plugin@marketplace` line to `tasks/g/claude/plugins`. An update applies when
Claude Code restarts.

It then runs three more tasks, all safe to run again:

- `mise run g:claude:settings` merges the wanted user settings into `~/.claude/settings.json`;
  those keys win, every other setting is kept. Today: subagents run on Sonnet
  (`CLAUDE_CODE_SUBAGENT_MODEL=claude-sonnet-5-5`) and forked subagents are off
  (`CLAUDE_CODE_FORK_SUBAGENT=0`). To save tokens, the context is compacted automatically
  at 400k tokens (`CLAUDE_CODE_AUTO_COMPACT_WINDOW=400000`) instead of near the edge of the
  1M window: a safety net, after the `/compact` the agent suggests around 200k
  ([`AGENTS.md`](dotfiles/agents/AGENTS.md)). Claude Code also sends no background request for
  the terminal title or for prompt suggestions (`CLAUDE_CODE_DISABLE_TERMINAL_TITLE=1`,
  `CLAUDE_CODE_ENABLE_PROMPT_SUGGESTION=false`). It also adds the [git guard](#git-guard-for-claude-code)
  hook next to the hooks already there (rtk, herdr). To change them, edit the JSON in
  `tasks/g/claude/settings`; a setting or hook removed from it is not removed from
  `~/.claude/settings.json`. Settings apply when Claude Code restarts.
- `mise run g:claude:skills` installs the global skills (in `~/.claude/skills`, loaded in every
  project) with `npx skills add --global`, which also fetches their latest version:
  [curl.md](https://curl.md/docs/skills), which fetches web pages as markdown that costs fewer
  tokens. To add one, add its source to `tasks/g/claude/skills`.
- `mise run g:claude:rtk` hooks [rtk](https://github.com/rtk-ai/rtk) (installed by mise) into
  Claude Code: a `PreToolUse` hook in `~/.claude/settings.json` condenses the output of Bash
  commands. Only the hook is installed (`rtk init -g --hook-only`): the full setup would add
  `@RTK.md` to `~/.claude/CLAUDE.md`, which links to this repository. `rtk gain` shows the
  tokens saved; `rtk bypass <command>` runs a command without filtering. rtk telemetry stays
  off unless `rtk telemetry enable` is run.

### Git guard for Claude Code

[`claude/hooks/git-guard.sh`](claude/hooks/git-guard.sh) is a `PreToolUse` hook on the Bash
commands of Claude Code (subagents included). It refuses:

- a push to the default branch (`git push origin main`, `HEAD:main`, or `git push` while on it);
- a force push without lease (`--force`, `-f`, `+branch`): `--force-with-lease` is allowed;
- a `git merge` while the default branch is checked out.

Everything else goes through, including merging a pull request on the forge (`gh pr merge`,
`glab mr merge`): when to merge is the user's call, written in each project's instructions. A
workflow that rebuilds an integration branch from `main` (`git checkout -B develop origin/main &&
git merge …`, then `git push --force-with-lease origin origin/main:develop`) is allowed. The
default branch is `origin/HEAD`, else `main` or `master`.

The hook reads the command, not what it will do: a push hidden in a script it runs is not seen.
It is a guard rail, not a security boundary. Its tests are in `tests/git-guard.bats`.

### graphify: a code graph for the agent

[graphify](https://github.com/Graphify-Labs/graphify) (installed by mise as `pipx:graphifyy`)
maps a repository into a knowledge graph that Claude Code queries (`graphify query`, `path`,
`explain`) instead of grepping and reading files one by one. Useful on a large or unfamiliar
codebase; pointless on a small one.

From anywhere inside a git repository:

```sh
mise run graph    # set up, or refresh the skill, hooks and graph
mise run graphd   # remove everything it added
```

`mise run graph` sets graphify up for you only:

| What | Where | Committed |
| --- | --- | --- |
| `/graphify` skill | `.claude/skills/graphify/` | no |
| Instructions for the agent (query the graph first) | `.claude/graphify.md` | no |
| Hooks nudging the agent towards the graph before Bash/Grep/Read/Glob (advisory, never blocking) | `.claude/settings.local.json`, merged with what is there | no |
| Code graph, report, `graph.html` | `graphify-out/` | no |
| `CLAUDE.md` | an existing one gets one line: `Local graphify setup (ignore if the file is missing): @.claude/graphify.md`; a missing one is created with that line | only the line added to an existing file, if you want it |

- "Not committed" means listed in a marked block of `.git/info/exclude`, which git never shares.
  Tracked files such as `.claude/settings.json` are never touched. A teammate without the setup
  sees at most the import line, and Claude Code skips an import whose file is missing.
- The graph is built from the code only, locally with tree-sitter: no LLM call, nothing sent
  anywhere (`GRAPHIFY_BACKEND=none`). The agent keeps it current with `graphify update .` after
  editing code; running `mise run graph` again rebuilds it too.
- Restart Claude Code in the repository after either command, so it loads or drops the hooks.
- When the hooks get in the way, the agents are told (in
  [`AGENTS.md`](dotfiles/agents/AGENTS.md)) to stop and suggest `mise run graphd`.
- graphify logs every query to `~/.cache/graphify-queries.log`; set
  `GRAPHIFY_QUERY_LOG_DISABLE=1` to turn that off.

## zsh completions

`mise bootstrap` runs `mise run g:zsh:completions`, which writes the zsh completion of each
installed tool that ships one (`bw`, `docker`, `gh`, `glab`, `herdr`, `mise`, `rg`) to
`~/.local/share/zsh/completions`. `~/.zshrc` adds that directory to `fpath` before oh-my-zsh
runs `compinit`, so they load in the next shell. They are regenerated on every bootstrap, so
`mise run up` keeps them in step with the tool versions; the completion of a tool no longer
installed is removed. To add a tool, add a `command arguments` line to
`tasks/g/zsh/completions`.

## Traefik: exposing a project on `*.localhost`

Traefik listens on `127.0.0.1:80` and `[::1]:80`.
Dashboard: [traefik.localhost/dashboard](http://traefik.localhost/dashboard/).
`mise run g:traefik:up` (also the last step of `mise bootstrap`) gives up after 20 s when the
Docker engine is stuck, and prints the command that restarts it, instead of waiting forever.
In a project's `compose.yaml`:

```yaml
services:
  api:
    labels:
      - traefik.enable=true
      - traefik.http.routers.myproject-api.rule=Host(`api.myproject.localhost`)
      - traefik.http.services.myproject-api.loadbalancer.server.port=8080  # container port
    networks: [proxy, default]

networks:
  proxy:
    external: true
```

Router names must be unique on the machine (hence the project prefix).
For an app running outside Docker, copy `stacks/traefik/traefik/dynamic/host-apps.yml.example`
to `<name>.yml` in the same directory.

## Local services on demand

Small web apps started only when needed, behind Traefik (no port of their own, except the Mailpit
SMTP server). Each one has a `g:<service>:up` / `g:<service>:down` task and two aliases:

| Service | Start / stop | Address | Use |
| --- | --- | --- | --- |
| [Mailpit](https://mailpit.axllent.org) | `mise run mail` / `maild` | [mail.localhost](http://mail.localhost) | Catches every mail sent by local projects |
| [ChartDB](https://github.com/chartdb/chartdb) | `mise run cdb` / `cdbd` | [chartdb.localhost](http://chartdb.localhost) | Database diagrams |
| [IT-Tools](https://github.com/CorentinTh/it-tools) | `mise run tools` / `toolsd` | [tools.localhost](http://tools.localhost) | JWT, base64, hashes, UUID, cron… offline |
| [Excalidraw](https://github.com/excalidraw/excalidraw) | `mise run draw` / `drawd` | [draw.localhost](http://draw.localhost) | Hand-drawn diagrams |

Starting a service also starts Traefik if needed, pulls the latest image and waits until the
service answers. Stopping it removes its container.

**Mailpit** never delivers a mail: everything lands in the inbox. Point a project's SMTP settings
to `localhost:1025` from the host, or to `mailpit:1025` from a container on the `proxy` network.
Any user name and password is accepted, without TLS. Caught mails are kept in the `mailpit_data`
volume. Port 1025 is also used by the MailDev or Mailpit a project may ship: run one at a time.

**ChartDB and Excalidraw** are static web apps: diagrams are stored in the browser, not in the
container. Stopping the service keeps them; clearing the site data of `chartdb.localhost` or
`draw.localhost` in the browser deletes them, so export the important ones. ChartDB usage
analytics are disabled in `stacks/chartdb/compose.yml`.

To add a service, copy one of `stacks/<service>/compose.yml` and `tasks/g/<service>/{up,down}`.

## Docker cleanup

`mise run dclean` (`g:docker:clean`) shows the disk usage, asks for confirmation, then removes
stopped containers, unused networks, dangling images and the build cache no image uses. Running
containers, the images they use and named volumes (databases) are always kept.

```sh
mise run dclean                 # the safe cleanup above
mise run dclean --old-images    # also older versions of each image, keeping the newest one
mise run dclean --all-images    # also every image no container uses (pulled again when needed)
mise run dclean --volumes       # also unused anonymous volumes
mise run dclean --dry-run       # disk usage, and the images --old-images would remove
```

`--old-images` only looks at version tags (`12`, `1.1.72`, `v2.3`): other tags name variants,
such as `php:8.2-cli` and `php:5.6-cli`, and are left alone. Add `--yes` to skip the confirmation.

## Docker VM size (macOS)

On macOS, Docker runs in the Colima VM. The first `mise bootstrap` asks for its size right after
installing Colima, before the login agent starts it. Each question shows the minimum, the maximum
and, in brackets, the value recommended for this Mac: press Enter to keep it.

| Resource | Minimum | Recommended | Maximum |
| --- | --- | --- | --- |
| CPUs | 2 | half of the Mac's CPUs | all of them |
| Memory | 4 GiB (memory-hungry local apps) | half of the Mac's memory | all but 2 GiB |
| Disk | 30 GiB | 100 GiB, or half the free space if less | the free space |

Without a terminal, the recommended values are used. Colima saves the size in
`~/.colima/default/colima.yaml`; later bootstraps keep it, and the login agent and
`g:traefik:up` start the VM with it.

```sh
mise run vm         # g:colima:resources: asks again (current values shown), restarts the VM
mise run vm --yes   # applies the recommended values without asking
```

Restarting the VM stops its containers; those with a restart policy, such as Traefik, come back.
The disk can only grow. On Linux, Docker runs natively: there is no VM to size.

## Working on this repository

`.config/mise.toml` holds the tools and tasks used to work on this repository. mise loads it only
inside the repository, so it never changes the machine configuration (`config.toml`). Its tool
versions are pinned, and [Renovate](https://docs.renovatebot.com) proposes the updates once its
GitHub app is enabled for the repository.

```sh
mise run setup    # once per clone: installs the git hooks (prek)
mise run check    # every check below, then the tests
```

| Task | Checks |
| --- | --- |
| `lint:secrets` | no secret in the git history (gitleaks): the repository is public |
| `lint:shell` | `install.sh` and the tasks (shellcheck, settings in `.shellcheckrc`) |
| `lint:typos` | spelling (typos, exceptions in `_typos.toml`) |
| `lint:editorconfig` | `.editorconfig` rules, except the indent size (aligned continuation lines) |
| `lint:ci` | GitHub Actions workflows (actionlint, zizmor) |
| `lint:renovate` | `renovate.json` |
| `test` | bats tests in `tests/` (also run by the pre-push hook) |

The git hooks run these checks on each commit, check the message against
[Conventional Commits](https://www.conventionalcommits.org) (cocogitto), and refuse commits on
`main`: work in a branch, ideally a worktree, since `~/.config/mise` points to this checkout:

```sh
git worktree add ../workstation-<topic> -b <type>/<topic>
```

CI runs the same checks on every pull request, checks the commit messages, and runs
`mise bootstrap --dry-run` on a fresh Ubuntu machine with this repository as the global
configuration.

## Secrets

No secrets in this repository: it is public. SSH access and passwords live in Bitwarden
(`mise run bwu`, then `mise run g:ssh:help`). Machine-specific settings go in a `*.local.toml`
file, ignored by git, and machine-specific shell settings (PATH entries, aliases) in
`~/.zshrc.local`, sourced last by `~/.zshrc` when it exists.
