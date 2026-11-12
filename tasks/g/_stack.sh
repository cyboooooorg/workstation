# Functions shared by the g:tools:up and g:tools:down tasks (sourced, not a task).
# A stack is a directory of stacks/ holding a compose.yml. Traefik runs once for the whole
# machine; every other stack runs behind it, on the host of its Traefik router rule.
# Written for bash 3.2 (macOS /bin/bash on a fresh machine).

source "$(dirname "${BASH_SOURCE[0]}")/_docker.sh"

stacks_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../stacks" && pwd -P)"

# stack_names: prints the available stacks, one per line
stack_names() {
  local file
  for file in "$stacks_dir"/*/compose.yml; do
    if [[ -f "$file" ]]; then basename "$(dirname "$file")"; fi
  done
}

# stack_check <stack>...: fails, listing the available stacks, when a name is missing or unknown
stack_check() {
  local name
  if [[ $# -eq 0 ]]; then
    echo "No stack given. Available stacks:" >&2
    stack_names | sed 's/^/  /' >&2
    return 1
  fi
  for name in "$@"; do
    if [[ ! -f "$stacks_dir/$name/compose.yml" ]]; then
      echo "Unknown stack \"$name\". Available stacks:" >&2
      stack_names | sed 's/^/  /' >&2
      return 1
    fi
  done
}

# stack_url <stack>: address of the stack, from the first Host(`…`) rule of its compose.yml
stack_url() {
  local host
  # shellcheck disable=SC2016 # the backticks are literal: Host(`…`) in the compose file
  host="$(sed -n 's/.*Host(`\([^`]*\)`).*/\1/p' "$stacks_dir/$1/compose.yml" | grep -v '[<>]' | head -n 1)"
  if [[ -n "$host" ]]; then echo "http://$host"; fi
}

# traefik_up: starts the machine-wide Traefik, and the Docker engine first if needed (Colima on
# macOS). Gives up after 20 s when the engine is stuck: it would block `mise bootstrap` forever.
traefik_up() {
  local status=0
  docker_responds 20 || status=$?
  if [[ $status -eq 2 ]]; then
    docker_hung_message
    return 1
  fi
  if [[ $status -ne 0 ]]; then
    if [[ "$(uname)" == "Darwin" ]] && command -v colima >/dev/null; then
      # Size saved by g:colima:resources (mise run vm)
      colima start
    else
      echo "Docker is not responding: start the engine (or add $USER to the docker group), then retry." >&2
      return 1
    fi
  fi
  docker compose --project-directory "$stacks_dir/traefik" up -d
  echo "traefik: http://traefik.localhost/dashboard/"
}

# stack_up <stack>: pulls the latest images, starts the stack and waits until its containers are
# healthy (Traefik skips a container that is still starting), then until Traefik routes it.
# Traefik must already be running: see traefik_up.
stack_up() {
  local url
  url="$(stack_url "$1")"
  docker compose --project-directory "$stacks_dir/$1" up -d --wait --pull always --remove-orphans
  if [[ -n "$url" ]]; then
    # Traefik adds the route a moment after the container turns healthy
    for _ in {1..10}; do
      [[ "$(curl -s -o /dev/null -w '%{http_code}' "$url")" != 404 ]] && break
      sleep 0.5
    done
  fi
  echo "$1: ${url:-started}"
}

# stack_down <stack>: stops the stack and removes its containers (named volumes are kept)
stack_down() {
  docker compose --project-directory "$stacks_dir/$1" down --remove-orphans
}
