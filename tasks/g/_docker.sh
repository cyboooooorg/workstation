# Functions shared by the tasks that need the Docker engine (sourced, not a task).
# Written for bash 3.2 and without GNU `timeout`, which macOS lacks.

# docker_responds [seconds]: checks that the Docker engine answers within the delay (20 s).
# Returns 0 when it answers, 1 when it is not running (fails at once),
# 2 when it hangs: a stuck daemon accepts connections but never replies.
docker_responds() {
  local delay="${1:-20}" pid i
  docker info >/dev/null 2>&1 &
  pid=$!
  for ((i = 0; i < delay * 2; i++)); do
    if ! kill -0 "$pid" 2>/dev/null; then
      wait "$pid"
      return
    fi
    sleep 0.5
  done
  kill "$pid" 2>/dev/null
  wait "$pid" 2>/dev/null
  return 2
}

# Message for a hung engine, with the command that restarts it on this system
docker_hung_message() {
  local restart="sudo systemctl restart docker"
  [[ "$(uname)" == "Darwin" ]] && restart="colima restart"
  echo "Docker does not answer (engine stuck): restart it with \`$restart\`, then retry." >&2
}
