# Functions shared by the on-demand stacks of stacks/ (sourced, not a task).
# Each stack runs behind the machine-wide Traefik, on <name>.localhost.

stacks_dir="$(cd ~/.config/mise && pwd -P)/stacks"

# stack_up <stack> <url>: starts Traefik if needed, pulls the latest images, starts the stack
# and waits until its containers are healthy (Traefik skips a container that is still starting)
stack_up() {
  # The stacks are only reachable through Traefik (which also starts the Docker engine on macOS)
  mise run -q g:traefik:up
  docker compose --project-directory "$stacks_dir/$1" up -d --wait --pull always --remove-orphans
  # Traefik adds the route a moment after the container turns healthy
  for _ in {1..10}; do
    [[ "$(curl -s -o /dev/null -w '%{http_code}' "$2")" != 404 ]] && break
    sleep 0.5
  done
  echo "$1: $2"
}

# stack_down <stack>: stops the stack and removes its containers (named volumes are kept)
stack_down() {
  docker compose --project-directory "$stacks_dir/$1" down --remove-orphans
}
