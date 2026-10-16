#!/usr/bin/env bash
# Starts real SFTP (sshd), FTP and S3 servers on localhost for the integration tests and
# exports MACSH_IT_* variables to $GITHUB_ENV. Meant for macOS CI runners .
#   SFTP: asyncssh server on port 2222, password + key auth
#   FTP : pyftpdlib (pip, in a venv)
#   S3  : `rclone serve s3` (S3 protocol server backed by a directory)
set -euo pipefail

D=/tmp/macsh-it
SFTP_USER=macshit
PASS="$(openssl rand -hex 12)"
rm -rf "$D"; mkdir -p "$D"; chmod 755 "$D"
command -v rclone >/dev/null || brew install rclone

export_env() { echo "$1=$2" >> "${GITHUB_ENV:-/dev/null}"; }
echo "::add-mask::$PASS"

# ---- SFTP ---------------------------------------------------------------------------
# asyncssh server (password + public-key auth): macOS PAM rejects throwaway OS users.
SFTP_USER=macshit
mkdir -p "$D/sftp-data"
ssh-keygen -q -t ed25519 -N "" -f "$D/id_ed25519"
cp "$D/id_ed25519.pub" "$D/authorized_keys"
ssh-keygen -q -t ed25519 -N "" -f "$D/host_key"
python3 -m venv "$D/venv"
"$D/venv/bin/pip" install --quiet asyncssh pyftpdlib
nohup "$D/venv/bin/python" "$(dirname "$0")/sftp_server.py" 2222 "$SFTP_USER" "$PASS" \
  "$D/host_key" "$D/authorized_keys" > "$D/sshd.log" 2>&1 &
for _ in $(seq 1 20); do nc -z 127.0.0.1 2222 && break; sleep 0.5; done
# Prove both auth methods work before the tests blame macsh.
printf 'ls %s\n' "$D/sftp-data" > "$D/batch"
sftp -P 2222 -i "$D/id_ed25519" -b "$D/batch" -o BatchMode=yes -o StrictHostKeyChecking=no \
  -o UserKnownHostsFile=/dev/null "$SFTP_USER@127.0.0.1" || { cat "$D/sshd.log"; exit 1; }
export_env MACSH_IT_SFTP_PORT 2222
export_env MACSH_IT_SFTP_USER "$SFTP_USER"
export_env MACSH_IT_SFTP_PASS "$PASS"
export_env MACSH_IT_SFTP_KEY "$D/id_ed25519"
export_env MACSH_IT_SFTP_AUTHKEYS "$D/authorized_keys"
export_env MACSH_IT_SFTP_DIR "$D/sftp-data"

# ---- FTP ----------------------------------------------------------------------------
mkdir -p "$D/ftp-data"
nohup "$D/venv/bin/python" "$(dirname "$0")/ftp_server.py" 2121 macsh "$PASS" "$D/ftp-data" \
  > "$D/ftp.log" 2>&1 &
for _ in $(seq 1 20); do nc -z 127.0.0.1 2121 && break; sleep 0.5; done
export_env MACSH_IT_FTP_PORT 2121
export_env MACSH_IT_FTP_USER macsh
export_env MACSH_IT_FTP_PASS "$PASS"
export_env MACSH_IT_FTP_DIR "$D/ftp-data"

# ---- S3 -----------------------------------------------------------------------------
mkdir -p "$D/s3-data/bkt"
nohup rclone serve s3 "$D/s3-data" --addr 127.0.0.1:9000 --auth-key "macshak,$PASS" \
  > "$D/s3.log" 2>&1 &
for _ in $(seq 1 20); do nc -z 127.0.0.1 9000 && break; sleep 0.5; done
export_env MACSH_IT_S3_ENDPOINT http://127.0.0.1:9000
export_env MACSH_IT_S3_ACCESS macshak
export_env MACSH_IT_S3_SECRET "$PASS"
export_env MACSH_IT_S3_BUCKET bkt
export_env MACSH_IT_S3_DIR "$D/s3-data"
echo "backends up"
