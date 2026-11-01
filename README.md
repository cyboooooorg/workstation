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

Changing a tool or a dotfile means changing this repository, then commit and push.

## Contents

```text
config.toml          tools, packages (apt / brew), dotfiles, services: a single file,
                     OS-specific entries carry an `os` key
dotfiles/            files linked into ~ (zshrc) or rendered (kitty.desktop, Linux)
  agents/AGENTS.md   global instructions for coding agents (linked by g:agents:link)
tasks/
  bootstrap          last step of `mise bootstrap`: starts Traefik
  g/                 global `g:*` tasks (agents, bw, docker, herdr, ssh, traefik, update,
                     and one up / down pair per local service)
  g/_stack.sh        functions shared by the local service tasks
stacks/traefik/      local reverse proxy, one instance for the whole machine
stacks/<service>/    local services started on demand behind Traefik
                     (chartdb, excalidraw, it-tools, mailpit)
install.sh           new machine setup
```

| | Linux (Debian) | macOS |
| --- | --- | --- |
| Docker engine | `docker-ce` (official Docker apt repository) | Colima (Homebrew), started at login |
| docker CLI, compose, buildx | mise | mise |
| Python (also runs the `pipx:` tools) | mise | mise (no Homebrew `python@*`) |
| kitty | GitHub release (mise) + menu entry | Homebrew cask |
| bash 5 | system | Homebrew (`/bin/bash` stays 3.2) |

Tasks run with the first `bash` on the `PATH`. On macOS that is `/bin/bash` 3.2 until Homebrew is
on the `PATH` (first bootstrap, launchd), so tasks must stay compatible with bash 3.2: no
associative arrays, `mapfile` or `${var,,}`, and `${arr[@]+"${arr[@]}"}` for arrays that may be
empty under `set -u`.

## Coding agents

[`dotfiles/agents/AGENTS.md`](dotfiles/agents/AGENTS.md) holds the rules every coding agent
follows in every project: English documentation (French on request), documentation shipped with
each change, Conventional Commits without emoji.

`mise bootstrap` runs `mise run g:agents:link` once the tools are installed. The task links this
file to the global instruction file of every agent whose command is on the `PATH`:

| Agent | Command | Global file |
| --- | --- | --- |
| Claude Code | `claude` | `~/.claude/CLAUDE.md` |
| Gemini CLI | `gemini` | `~/.gemini/GEMINI.md` |
| GitHub Copilot CLI | `copilot` | `~/.copilot/copilot-instructions.md` |

- An existing regular file is moved to `<file>.bak-<date>` first; a link to somewhere else is
  replaced.
- When an agent is no longer installed, its link is removed (only if it points to this file).
- To support another agent, add a `command|file` line to `tasks/g/agents/link`, then run
  `mise run g:agents:link` (installing an agent later does not need a full `mise bootstrap`).

Instructions shipped by a project take precedence over these.

## Traefik: exposing a project on `*.localhost`

Traefik listens on `127.0.0.1:80` and `[::1]:80`.
Dashboard: [traefik.localhost/dashboard](http://traefik.localhost/dashboard/).
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

## Secrets

No secrets in this repository: it is public. SSH access and passwords live in Bitwarden
(`mise run bwu`, then `mise run g:ssh:help`). Machine-specific settings go in a `*.local.toml`
file, ignored by git, and machine-specific shell settings (PATH entries, aliases) in
`~/.zshrc.local`, sourced last by `~/.zshrc` when it exists.
