#!/usr/bin/env bash
set -Eeuo pipefail

WORKSPACE=/home/jovyan/work
PROJECT_GIT_URL="${OPENCODE_PROJECT_GIT_URL:-}"
PROJECT_DIR="${WORKSPACE}/${OPENCODE_PROJECT_DIR:-project}"
export CODE_WORKINGDIR="${PROJECT_DIR}"
OPENCODE_CONFIG_DIR="${HOME}/.config/opencode"
OPENCODE_CONFIG_FILE="${OPENCODE_CONFIG_DIR}/opencode.json"
OPENCODE_CONFIG_JSONC="${OPENCODE_CONFIG_DIR}/opencode.jsonc"

mkdir -p "${OPENCODE_CONFIG_DIR}"
if [[ ! -f "${OPENCODE_CONFIG_FILE}" && ! -f "${OPENCODE_CONFIG_JSONC}" ]]; then
    install -m 0644 /opt/chameleon/opencode.json "${OPENCODE_CONFIG_FILE}"
else
    active_config="${OPENCODE_CONFIG_FILE}"
    if [[ -f "${OPENCODE_CONFIG_JSONC}" ]]; then
        active_config="${OPENCODE_CONFIG_JSONC}"
    fi

    python - "${active_config}" /opt/chameleon/opencode.json <<'PY'
import json
import os
import sys
import tempfile


def strip_jsonc(source):
    without_comments = []
    index = 0
    in_string = False
    escaped = False
    while index < len(source):
        char = source[index]
        if in_string:
            without_comments.append(char)
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == '"':
                in_string = False
            index += 1
        elif char == '"':
            in_string = True
            without_comments.append(char)
            index += 1
        elif source.startswith("//", index):
            index += 2
            while index < len(source) and source[index] not in "\r\n":
                index += 1
        elif source.startswith("/*", index):
            index += 2
            while index < len(source) and not source.startswith("*/", index):
                if source[index] in "\r\n":
                    without_comments.append(source[index])
                index += 1
            index += 2
        else:
            without_comments.append(char)
            index += 1

    source = "".join(without_comments)
    without_trailing_commas = []
    index = 0
    in_string = False
    escaped = False
    while index < len(source):
        char = source[index]
        if in_string:
            without_trailing_commas.append(char)
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == '"':
                in_string = False
        elif char == '"':
            in_string = True
            without_trailing_commas.append(char)
        elif char == ",":
            lookahead = index + 1
            while lookahead < len(source) and source[lookahead].isspace():
                lookahead += 1
            if lookahead >= len(source) or source[lookahead] not in "}]":
                without_trailing_commas.append(char)
        else:
            without_trailing_commas.append(char)
        index += 1
    return "".join(without_trailing_commas)


config_path, bundled_path = sys.argv[1:]
with open(config_path, encoding="utf-8") as handle:
    config_source = handle.read()
config = json.loads(strip_jsonc(config_source))
with open(bundled_path, encoding="utf-8") as handle:
    bundled = json.load(handle)

disabled = config.setdefault("disabled_providers", [])
if "amazon-bedrock" not in disabled:
    disabled.append("amazon-bedrock")
config.setdefault("provider", {}).setdefault(
    "kilo-anon", bundled["provider"]["kilo-anon"]
)

fd, temporary_path = tempfile.mkstemp(dir=os.path.dirname(config_path), text=True)
try:
    with os.fdopen(fd, "w", encoding="utf-8") as handle:
        json.dump(config, handle, indent=2)
        handle.write("\n")
    os.replace(temporary_path, config_path)
finally:
    if os.path.exists(temporary_path):
        os.unlink(temporary_path)
PY
fi

mkdir -p "${PROJECT_DIR}"
shopt -s dotglob nullglob
project_entries=("${PROJECT_DIR}"/*)
non_env_entries=()
for entry in "${project_entries[@]}"; do
    [[ "${entry}" == "${PROJECT_DIR}/.env" ]] || non_env_entries+=("${entry}")
done

if [[ -n "${PROJECT_GIT_URL}" && ${#non_env_entries[@]} -eq 0 ]]; then
    clone_dir="${PROJECT_DIR}.clone.$$"
    trap 'rm -rf "${clone_dir:-}"' EXIT
    git clone "${PROJECT_GIT_URL}" "${clone_dir}"
    rm -f "${clone_dir}/.env"
    cp -a "${clone_dir}/." "${PROJECT_DIR}/"
    git -C "${PROJECT_DIR}" rm --cached --ignore-unmatch .env
    rm -rf "${clone_dir}"
    trap - EXIT
elif [[ -n "${PROJECT_GIT_URL}" && ! -d "${PROJECT_DIR}/.git" ]]; then
    echo "Project directory is not empty and is not a Git repository: ${PROJECT_DIR}" >&2
    exit 1
elif [[ ! -d "${PROJECT_DIR}/.git" ]]; then
    git init --initial-branch=main "${PROJECT_DIR}"
fi

if [[ "${HOST_SSH_ENABLED:-0}" == "1" && ! -e "${PROJECT_DIR}/HOST.md" ]]; then
    cat > "${PROJECT_DIR}/HOST.md" <<'EOF'
# Chameleon Host Access

OpenCode runs inside a container. To run a command on the Chameleon host, use:

```bash
ssh -i /home/jovyan/.ssh/id_ed25519 -o BatchMode=yes -o IdentitiesOnly=yes -o UpdateHostKeys=no opencode@host.docker.internal '<command>'
```

The host user has passwordless sudo. For commands that require root access, use:

```bash
ssh -i /home/jovyan/.ssh/id_ed25519 -o BatchMode=yes -o IdentitiesOnly=yes -o UpdateHostKeys=no opencode@host.docker.internal 'sudo <command>'
```

The host key is pinned in `/home/jovyan/.ssh/known_hosts`. Do not disable host-key checking.
EOF
fi
if [[ -L "${PROJECT_DIR}/.gitignore" ]]; then
    echo "Refusing to modify a symlinked .gitignore: ${PROJECT_DIR}/.gitignore" >&2
    exit 1
fi
if ! grep -qxF '.env' "${PROJECT_DIR}/.gitignore" 2>/dev/null; then
    printf '\n.env\n' >> "${PROJECT_DIR}/.gitignore"
fi

cd "${PROJECT_DIR}"

opencode web \
    --hostname 0.0.0.0 \
    --port "${OPENCODE_PORT:-4096}" &
OPENCODE_PID=$!

start-notebook.py \
    --ServerApp.root_dir="${WORKSPACE}" &
JUPYTER_PID=$!

shutdown() {
    trap - SIGINT SIGTERM EXIT
    kill -TERM "${OPENCODE_PID}" "${JUPYTER_PID}" 2>/dev/null || true
    wait "${OPENCODE_PID}" "${JUPYTER_PID}" 2>/dev/null || true
}

trap shutdown SIGINT SIGTERM EXIT

set +e
wait -n "${OPENCODE_PID}" "${JUPYTER_PID}"
STATUS=$?
set -e

shutdown
exit "${STATUS}"
