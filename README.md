# workstation

Mon poste de dev, sur macOS ou Linux (Debian), décrit par une config [mise](https://mise.jdx.dev) :
outils, paquets système, dotfiles, tâches et services. Ce dépôt **est** la config globale de mise :
`~/.config/mise` est un lien vers lui.

## Machine neuve

```sh
curl -fsSL https://raw.githubusercontent.com/cyboooooorg/workstation/main/install.sh | sh
```

Le script installe les prérequis (git, curl ; Homebrew sur macOS), puis mise dans `~/.local/bin`, et lance :

```sh
mise bootstrap --from https://github.com/cyboooooorg/workstation.git \
  --from-dir ~/Developer/workstation --config-dir . --yes
```

Un `~/.config/mise` existant est d'abord déplacé dans `~/.config/mise.bak-<date>`.

Sur Linux, il reste ensuite à ajouter l'utilisateur au groupe docker
(`sudo usermod -aG docker $USER`, puis se reconnecter).

## Au quotidien

| Commande | Effet |
|---|---|
| `mise run up` | `git pull` du dépôt, `mise bootstrap`, puis mise à jour de tout le reste (outils, Homebrew, apt, snap) |
| `mise bootstrap` | Applique la config : ce qui est déjà en place n'est pas touché |
| `mise bootstrap status` | État de chaque partie (outils, paquets, dotfiles…) |
| `mise tasks -g` | Tâches globales (Bitwarden, SSH, herdr, Traefik…) |

Modifier un outil ou un dotfile = modifier ce dépôt, puis commit et push.

## Contenu

```
config.toml          outils, paquets (apt / brew), dotfiles, services : un seul fichier,
                     les entrées propres à un OS portent une clé `os`
dotfiles/            fichiers liés dans ~ (zshrc) ou générés (kitty.desktop, Linux)
tasks/
  bootstrap          dernière étape de `mise bootstrap` : démarre Traefik
  g/                 tâches globales `g:*` (bw, ssh, herdr, traefik, update)
stacks/traefik/      reverse proxy local, une instance pour toute la machine
install.sh           installation d'une machine neuve
```

| | Linux (Debian) | macOS |
|---|---|---|
| Moteur Docker | `docker-ce` (dépôt apt officiel Docker) | Colima (Homebrew), démarré à l'ouverture de session |
| CLI docker, compose, buildx | mise | mise |
| kitty | release GitHub (mise) + entrée de menu | cask Homebrew |

## Traefik : exposer un projet en `*.localhost`

Traefik écoute sur `127.0.0.1:80` et `[::1]:80`. Tableau de bord : <http://traefik.localhost/dashboard/>.
Dans le `compose.yaml` d'un projet :

```yaml
services:
  api:
    labels:
      - traefik.enable=true
      - traefik.http.routers.monprojet-api.rule=Host(`api.monprojet.localhost`)
      - traefik.http.services.monprojet-api.loadbalancer.server.port=8080  # port interne du conteneur
    networks: [proxy, default]

networks:
  proxy:
    external: true
```

Les noms de routeurs doivent être uniques sur la machine (d'où le préfixe du projet).
Pour une appli lancée hors Docker : copier `stacks/traefik/traefik/dynamic/host-apps.yml.example`
en `<nom>.yml` dans le même dossier.

## Secrets

Aucun secret dans ce dépôt : il est public. Les accès SSH et les mots de passe vivent dans Bitwarden
(`mise run bwu`, puis `mise run g:ssh:help`). Un réglage propre à une machine va dans un fichier
`*.local.toml`, ignoré par git.
