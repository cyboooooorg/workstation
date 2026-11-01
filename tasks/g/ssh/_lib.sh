# Functions shared by the ssh:* tasks (sourced, not a task).
#
# Source of truth: one Bitwarden item (Login type) per server.
#   Name          : ssh/<alias>
#   Username      : user (empty = local user)
#   Password      : empty for key-based login
#   URI           : ssh://<host>:<port>  or  sftp://<host>:<port>
#   Notes         : commands to run on connect, one per line
#   Custom fields : legacy-rsa (boolean)   -> server offering only ssh-rsa keys (SHA-1)
#                   identity-file (text)   -> local private key, e.g. ~/.ssh/id_rsa

SSH_PREFIX="ssh/"
SSH_GENERATED_CONFIG="$HOME/.ssh/config.d/bitwarden-hosts"
BW_SESSION_FILE="${XDG_RUNTIME_DIR:-/tmp}/bw-session"

# Unlocks Bitwarden if needed and exports BW_SESSION.
# Reuses the session shared by the g:bw:unlock task.
bw_ensure_unlocked() {
  local status
  if [[ -z "${BW_SESSION:-}" && -r "$BW_SESSION_FILE" ]]; then
    BW_SESSION="$(<"$BW_SESSION_FILE")"
    export BW_SESSION
  fi
  status="$(bw status </dev/null | jq -r .status)"
  case "$status" in
    unauthenticated)
      echo "Bitwarden: not logged in. Run first: bw login" >&2
      return 1 ;;
    locked)
      # Master password read from the keyboard, never from stdin (which may be a pipe)
      BW_SESSION="$(bw unlock --raw < /dev/tty)" || return 1
      export BW_SESSION
      (umask 077 && printf '%s' "$BW_SESSION" > "$BW_SESSION_FILE") ;;
  esac
  bw sync --quiet </dev/null >/dev/null 2>&1 || true
}

# jq filter: Bitwarden item -> flat object {alias, id, scheme, host, port, user, password, commands, legacy, identity}
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

# All ssh/* items, normalized (JSON array)
bw_ssh_items() {
  bw list items --search "$SSH_PREFIX" </dev/null \
    | jq --arg p "$SSH_PREFIX" "[.[] | select(.name | startswith(\$p)) | $SSH_ITEM_JQ] | sort_by(.alias)"
}

# Raw item of an alias (Bitwarden JSON), empty if missing
bw_ssh_raw_item() {
  bw list items --search "$SSH_PREFIX$1" </dev/null \
    | jq --arg n "$SSH_PREFIX$1" 'map(select(.name == $n)) | first // empty'
}

# Creates or updates an item.
# Usage : SSH_PASSWORD=... bw_ssh_upsert <alias> <uri> <user> <commands> <legacy:true|false> <identity>
# The password goes through the environment (never as an argument); empty = keep the existing one.
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
    echo "Item updated: $SSH_PREFIX$alias"
  else
    bw get template item </dev/null \
      | jq --argjson new "$new" '.type = 1 | .name = $new.name | .notes = $new.notes | .fields = $new.fields | .login = $new.login' \
      | bw encode | bw create item >/dev/null
    echo "Item created: $SSH_PREFIX$alias"
  fi
}

# True if the server only offers ssh-rsa/ssh-dss host keys (negotiation only, no authentication)
ssh_needs_legacy_rsa() {
  local host=$1 port=${2:-22} out
  # Output captured first: with pipefail, the expected ssh failure would hide the grep result
  # timeout is GNU coreutils: missing on macOS (gtimeout with Homebrew coreutils)
  local to=()
  if command -v timeout >/dev/null; then to=(timeout 10)
  elif command -v gtimeout >/dev/null; then to=(gtimeout 10)
  fi
  out="$(${to[@]+"${to[@]}"} ssh -p "$port" -o BatchMode=yes -o ConnectTimeout=5 -o PreferredAuthentications=none \
      -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$host" true 2>&1 </dev/null || true)"
  grep -q 'no matching host key type.*ssh-rsa' <<<"$out"
}
