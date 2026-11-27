#!/bin/bash
# Resets the Minecraft server world (backs up the current one and generates a new one).
# Usage:
#   sudo bash minecraft-reset-world.sh            -> new world with a random seed
#   sudo bash minecraft-reset-world.sh 123456789  -> new world with that seed
#   sudo bash minecraft-reset-world.sh "-4172144997902289642"  (quote negative seeds)

set -u
SERVER_DIR=/opt/minecraft/server
BACKUP_DIR=/opt/minecraft/backups
SEED="${1:-}"

if [ "$(id -u)" -ne 0 ]; then echo "Run with sudo"; exit 1; fi
cd "$SERVER_DIR" || exit 1

# World folder name (defaults to "world")
LEVEL_NAME=$(grep -m1 '^level-name=' server.properties | cut -d= -f2-)
LEVEL_NAME=${LEVEL_NAME:-world}

# Sanitize the seed: only letters, digits, spaces, hyphen and underscore
SEED=$(printf '%s' "$SEED" | tr -cd 'A-Za-z0-9 _-')

echo ">> Stopping the server"
systemctl stop minecraft

echo ">> Backing up the current world"
mkdir -p "$BACKUP_DIR"
BACKUP_FILE="$BACKUP_DIR/${LEVEL_NAME}_$(date +%Y%m%d_%H%M%S).tar.gz"
tar czf "$BACKUP_FILE" "$LEVEL_NAME"* 2>/dev/null && echo "   Backup: $BACKUP_FILE"

echo ">> Deleting the world"
rm -rf "$LEVEL_NAME" "${LEVEL_NAME}_nether" "${LEVEL_NAME}_the_end"

# Seed: if none is given, leave it empty so Minecraft picks a random one
if grep -q '^level-seed=' server.properties; then
  sed -i "s/^level-seed=.*/level-seed=${SEED}/" server.properties
else
  echo "level-seed=${SEED}" >> server.properties
fi

if [ -n "$SEED" ]; then
  echo ">> Seed set to: $SEED"
else
  echo ">> No seed given: a random one will be generated"
fi

chown -R minecraft:minecraft /opt/minecraft/

echo ">> Starting the server"
systemctl start minecraft
echo "Done. Check startup with: sudo journalctl -u minecraft -f"
echo "Once in game, view the seed with: /seed"