# workstation

My development machine, on macOS or Linux (Debian), described by a [mise](https://mise.jdx.dev)
configuration: tools, system packages, dotfiles, tasks and services. This repository **is** the
global mise configuration: `~/.config/mise` is a link to it.

## New machine

```sh
curl -fsSL https://raw.githubusercontent.com/cyboooooorg/workstation/main/install.sh | sh
```

The script installs the prerequisites (git, curl; Homebrew on macOS), then mise into
`~/.local/bin`, and runs:

```sh
mise bootstrap --from https://github.com/cyboooooorg/workstation.git \
  --from-dir ~/Developer/workstation --config-dir . --yes
```

An existing `~/.config/mise` is first moved to `~/.config/mise.bak-<date>`.

On Linux, add the user to the docker group afterwards
(`sudo usermod -aG docker $USER`, then log in again).

## Day to day

| Command | Effect |
| --- | --- |
| `mise run up` | `git pull` of this repository, `mise bootstrap`, then updates everything else (tools, Homebrew, apt, snap) |
| `mise bootstrap` | Applies the configuration: what is already in place is left alone |
| `mise bootstrap status` | State of every part (tools, packages, dotfiles…) |
| `mise tasks -g` | Global tasks (Bitwarden, SSH, herdr, Traefik…) |

Changing a tool or a dotfile means changing this repository, then commit and push.

## Contents

```text
config.toml          tools, packages (apt / brew), dotfiles, services: a single file,
                     OS-specific entries carry an `os` key
dotfiles/            files linked into ~ (zshrc, agent instructions) or rendered (kitty.desktop, Linux)
  agents/AGENTS.md   global instructions for coding agents
tasks/
  bootstrap          last step of `mise bootstrap`: starts Traefik
  g/                 global `g:*` tasks (bw, ssh, herdr, traefik, update)
stacks/traefik/      local reverse proxy, one instance for the whole machine
install.sh           new machine setup
```

| | Linux (Debian) | macOS |
| --- | --- | --- |
| Docker engine | `docker-ce` (official Docker apt repository) | Colima (Homebrew), started at login |
| docker CLI, compose, buildx | mise | mise |
| kitty | GitHub release (mise) + menu entry | Homebrew cask |

## Coding agents

[`dotfiles/agents/AGENTS.md`](dotfiles/agents/AGENTS.md) holds the rules every coding agent
follows in every project: English documentation (French on request), documentation shipped with
each change, Conventional Commits without emoji. It is linked to the global instruction file of
each agent:

| Agent | Global file |
| --- | --- |
| Claude Code | `~/.claude/CLAUDE.md` |
| Gemini CLI | `~/.gemini/GEMINI.md` |

GitHub Copilot keeps its own global instructions (`~/.copilot/copilot-instructions.md`), managed
outside this repository. Instructions shipped by a project take precedence over these.

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

## Secrets

No secrets in this repository: it is public. SSH access and passwords live in Bitwarden
(`mise run bwu`, then `mise run g:ssh:help`). Machine-specific settings go in a `*.local.toml`
file, ignored by git.
