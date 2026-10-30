# Fonctions partagées par les tâches ssh:* (sourcé, pas une tâche).
#
# Source de vérité : une fiche Bitwarden (type Identifiant) par serveur.
#   Nom           : ssh/<alias>
#   Identifiant   : utilisateur (vide = utilisateur local)
#   Mot de passe  : vide si connexion par clé
#   URI           : ssh://<hôte>:<port>  ou  sftp://<hôte>:<port>
#   Notes         : commandes à exécuter à la connexion, une par ligne
#   Champs perso  : legacy-rsa (booléen)  -> serveur n'offrant que des clés ssh-rsa (SHA-1)
#                   identity-file (texte) -> clé privée locale, ex. ~/.ssh/id_rsa

SSH_PREFIX="ssh/"
SSH_GENERATED_CONFIG="$HOME/.ssh/config.d/bitwarden-hosts"
BW_SESSION_FILE="${XDG_RUNTIME_DIR:-/tmp}/bw-session"

# Déverrouille Bitwarden si besoin et exporte BW_SESSION.
# Réutilise la session partagée par la tâche g:bw:unlock.
bw_ensure_unlocked() {
  local status
  if [[ -z "${BW_SESSION:-}" && -r "$BW_SESSION_FILE" ]]; then
    BW_SESSION="$(<"$BW_SESSION_FILE")"
    export BW_SESSION
  fi
  status="$(bw status </dev/null | jq -r .status)"
  case "$status" in
    unauthenticated)
      echo "Bitwarden : non connecté. Lancez d'abord : bw login" >&2
      return 1 ;;
    locked)
      # Mot de passe maître lu au clavier, jamais sur stdin (qui peut être un pipe)
      BW_SESSION="$(bw unlock --raw < /dev/tty)" || return 1
      export BW_SESSION
      (umask 077 && printf '%s' "$BW_SESSION" > "$BW_SESSION_FILE") ;;
  esac
  bw sync --quiet </dev/null >/dev/null 2>&1 || true
}

# Filtre jq : fiche Bitwarden -> objet plat {alias, id, scheme, host, port, user, password, commands, legacy, identity}
SSH_ITEM_JQ='
  def field($n): (.fields // []) | map(select(.name == $n)) | first | .value // "";
  { alias: (.name | ltrimstr("ssh/")),
    id: .id,
    user: (.login.username // ""),
    password: (.login.password // ""),
    commands: (.notes // ""),
    legacy: (field("legacy-rsa") == "true"),
    identity: field("identity-file") }
  + ((.login.uris // [])[0].uri // "" | capture("^(?<scheme>[a-z]+)://(?<host>[^:/]+)(:(?<port>[0-9]+))?") // {})
  | .scheme //= "ssh" | .host //= "" | .port //= "22"'

# Toutes les fiches ssh/*, normalisées (tableau JSON)
bw_ssh_items() {
  bw list items --search "$SSH_PREFIX" </dev/null \
    | jq --arg p "$SSH_PREFIX" "[.[] | select(.name | startswith(\$p)) | $SSH_ITEM_JQ] | sort_by(.alias)"
}

# Fiche brute d'un alias (JSON Bitwarden), vide si absente
bw_ssh_raw_item() {
  bw list items --search "$SSH_PREFIX$1" </dev/null \
    | jq --arg n "$SSH_PREFIX$1" 'map(select(.name == $n)) | first // empty'
}

# Crée ou met à jour une fiche.
# Usage : SSH_PASSWORD=... bw_ssh_upsert <alias> <uri> <user> <commands> <legacy:true|false> <identity>
# Le mot de passe passe par l'environnement (jamais en argument) ; vide = conserver l'existant.
bw_ssh_upsert() {
  local alias=$1 uri=$2 user=$3 commands=$4 legacy=$5 identity=$6 raw id new
  new="$(jq -n --arg n "$SSH_PREFIX$alias" --arg uri "$uri" --arg u "$user" \
               --arg c "$commands" --arg l "$legacy" --arg i "$identity" '
    { name: $n,
      notes: (if $c == "" then null else $c end),
      login: { username: (if $u == "" then null else $u end),
               password: (env.SSH_PASSWORD // "" | if . == "" then null else . end),
               totp: null,
               uris: [{match: null, uri: $uri}] },
      fields: ([{name: "legacy-rsa", value: $l, type: 2}]
               + (if $i == "" then [] else [{name: "identity-file", value: $i, type: 0}] end)) }')"
  raw="$(bw_ssh_raw_item "$alias")"
  if [[ -n "$raw" ]]; then
    id="$(jq -r .id <<<"$raw")"
    jq --argjson new "$new" \
       '.name = $new.name | .notes = $new.notes | .fields = $new.fields
        | .login.username = $new.login.username | .login.uris = $new.login.uris
        | .login.password = ($new.login.password // .login.password)' <<<"$raw" \
      | bw encode | bw edit item "$id" >/dev/null
    echo "Fiche mise à jour : $SSH_PREFIX$alias"
  else
    bw get template item </dev/null \
      | jq --argjson new "$new" '.type = 1 | .name = $new.name | .notes = $new.notes | .fields = $new.fields | .login = $new.login' \
      | bw encode | bw create item >/dev/null
    echo "Fiche créée : $SSH_PREFIX$alias"
  fi
}

# Vrai si le serveur n'offre que des clés d'hôte ssh-rsa/ssh-dss (négociation seule, sans authentification)
ssh_needs_legacy_rsa() {
  local host=$1 port=${2:-22} out
  # Sortie capturée d'abord : avec pipefail, l'échec attendu de ssh masquerait le résultat de grep
  out="$(timeout 10 ssh -p "$port" -o BatchMode=yes -o ConnectTimeout=5 -o PreferredAuthentications=none \
      -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$host" true 2>&1 </dev/null || true)"
  grep -q 'no matching host key type.*ssh-rsa' <<<"$out"
}
