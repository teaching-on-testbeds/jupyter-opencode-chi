#!/usr/bin/env bash
set -Eeuo pipefail

SSH_DIR="${1:-/etc/chameleon-opencode-ssh}"
PRIVATE_KEY="${SSH_DIR}/id_ed25519"
KNOWN_HOSTS="${SSH_DIR}/known_hosts"

if [[ "${EUID}" -ne 0 ]]; then
    echo "Run this script as root." >&2
    exit 1
fi

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y openssh-server sudo

if ! id opencode >/dev/null 2>&1; then
    useradd --create-home --shell /bin/bash opencode
else
    usermod --home /home/opencode --shell /bin/bash opencode
fi

install -d -m 0755 -o opencode -g opencode /home/opencode
install -d -m 0700 -o opencode -g opencode /home/opencode/.ssh
install -d -m 0755 "${SSH_DIR}"
if [[ ! -f "${PRIVATE_KEY}" ]]; then
    ssh-keygen -q -t ed25519 -N "" -C "chameleon-opencode-host-access" -f "${PRIVATE_KEY}"
fi

install -m 0600 -o opencode -g opencode \
    "${PRIVATE_KEY}.pub" /home/opencode/.ssh/authorized_keys

cat > /etc/sudoers.d/opencode <<'EOF'
opencode ALL=(ALL) NOPASSWD: ALL
EOF
chmod 0440 /etc/sudoers.d/opencode
visudo -cf /etc/sudoers.d/opencode

: > "${KNOWN_HOSTS}"
for host_key in /etc/ssh/ssh_host_*_key.pub; do
    read -r key_type key_value _ < "${host_key}"
    printf 'host.docker.internal %s %s\n' "${key_type}" "${key_value}" >> "${KNOWN_HOSTS}"
done
chmod 0644 "${KNOWN_HOSTS}"

# The Jupyter container runs as UID 1000 and needs read access to the key.
chown 1000:100 "${PRIVATE_KEY}"
chmod 0600 "${PRIVATE_KEY}"

systemctl enable --now ssh
