# Global agent instructions

These rules apply to every project. When a project ships its own instructions
(`CLAUDE.md`, `AGENTS.md`, `CONTRIBUTING.md`…), they take precedence on any conflict.

## Language

- Reply to the user in the language they write in.
- Write everything that lands in a repository in English: documentation, code comments,
  commit messages, pull request descriptions, log and error messages. Keep the existing
  language of user-facing strings when a project already uses another one.
- Write documentation in English first. Add a French version only when the user asks for it,
  as a sibling file with a `.fr` suffix (`README.fr.md` next to `README.md`). The English
  file stays the source: update both in the same change.

## Documentation

- Every change that adds or modifies behavior, configuration, commands, environment
  variables or a public API ships with its documentation update in the same change:
  README, `docs/`, CLI help and usage text, docstrings of public functions, and the
  changelog when the project keeps one.
- A new project or module gets a README covering: purpose, prerequisites, installation,
  usage, configuration.
- Document why and how to use it, not what the code already says. Keep examples
  copy-pasteable and up to date.
- When reporting a finished task, list the documentation updated, or say why none was needed.
- Markdown follows the markdownlint default rules: ATX headings, blank lines around
  headings, lists and code blocks, a language on every fenced code block, no bare URLs,
  a single trailing newline.

## Commit messages

Follow [Conventional Commits 1.0.0](https://www.conventionalcommits.org/en/v1.0.0/):

```text
<type>(<optional scope>)<optional !>: <description>

<optional body>

<optional footers>
```

- Types: `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `build`, `ci`,
  `chore`, `revert`.
- Description: imperative mood, lowercase first letter, no trailing period, header of
  72 characters at most.
- Body: what changed and why, wrapped at 72 characters.
- Breaking changes: `!` after the type or scope, and a `BREAKING CHANGE: <details>` footer.
- Reference issues in footers: `Refs: #123`, `Closes: #123`.
- No emoji, anywhere in the message: no Unicode emoji, no gitmoji, no `:shortcode:`.
- One logical change per commit. Documentation for a change goes in the same commit;
  a commit touching only documentation uses `docs`.

Examples:

```text
feat(auth): add refresh token rotation
fix(api): return 404 when the order does not exist
docs: document the local Traefik setup
refactor(ssh)!: read server list from Bitwarden only

BREAKING CHANGE: ~/.ssh/servers.yml is no longer read.
```

## Session length

Every turn resends the whole conversation, so a long session costs more on
each turn that follows.

- When a topic is done (a pull request opened, a question answered, a bug
  fixed) and the user moves on to something unrelated, suggest a `/clear`
  in one line before starting, and say what to carry over if anything
  (a branch, a file, a pull request number).
- Past about 200k tokens of context, suggest a `/compact` that keeps the
  decisions, the branch and the open questions.
- Suggest it once per topic, never twice in a row, and never in the middle
  of a task.

## graphify

A repository may carry a local [graphify](https://github.com/Graphify-Labs/graphify) setup
(`.claude/graphify.md`, hooks nudging you towards `graphify query` before searching or
reading files). It is a tool, not a rule above the task: when the graph is missing, stale or
wrong, read the files directly.

When the graphify hooks degrade your work (nudges pulling you away from the files you need,
answers from the graph that turn out wrong, a graph clearly behind the code), stop, tell the
user what you saw, and suggest `mise run graphd`, which removes the setup from the
repository. Do not run it yourself: the user decides.
