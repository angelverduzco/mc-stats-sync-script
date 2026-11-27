#!/bin/bash
# Converts an already installed vanilla server (/opt/minecraft/server) to Fabric + mods.
# Usage:  sudo ./upgrade-mods.sh

# ============================ CONFIGURATION ============================
MC_VERSION="1.21.1"      # Must match your current world's version (or the one you want if you are going to wipe it)
SEED=""                  # Empty = leave the current seed untouched
WIPE_WORLD="no"          # "yes" = back up and delete the world (required for a new seed / Tectonic terrain)

MODS=(
  "Tectonic"
  "FallingTree"
  "Snow! Real Magic!"
  "Snowy Spirit"
  "Infinite Trading"
  "Just Enough Items"
  "Immersive Paintings"
  "Waystones"
)
# =======================================================================

set -u
SERVER_DIR=/opt/minecraft/server
MODS_DIR=$SERVER_DIR/mods
UA="minecraft-ec2-upgrade-script"

if [ "$(id -u)" -ne 0 ]; then echo "Run with sudo"; exit 1; fi

yum install -y jq wget curl

echo ">> Stopping the server"
systemctl stop minecraft

cd "$SERVER_DIR" || exit 1

# Back up the world and the vanilla jar
if [ "$WIPE_WORLD" = "yes" ]; then
  echo ">> Backing up and deleting the world"
  tar czf "/opt/minecraft/world_backup_$(date +%Y%m%d_%H%M%S).tar.gz" world* 2>/dev/null
  rm -rf world world_nether world_the_end
fi
mv -f server.jar server.vanilla.jar.bak

# Fabric server as server.jar (start and systemd stay unchanged)
LOADER_VERSION=$(curl -s https://meta.fabricmc.net/v2/versions/loader | jq -r 'map(select(.stable))[0].version')
INSTALLER_VERSION=$(curl -s https://meta.fabricmc.net/v2/versions/installer | jq -r 'map(select(.stable))[0].version')
wget -O server.jar "https://meta.fabricmc.net/v2/versions/loader/${MC_VERSION}/${LOADER_VERSION}/${INSTALLER_VERSION}/server/jar" \
  || { echo "Fabric download failed; restoring vanilla jar"; mv -f server.vanilla.jar.bak server.jar; systemctl start minecraft; exit 1; }

# Seed
if [ -n "$SEED" ]; then
  sed -i "s/^level-seed=.*/level-seed=${SEED}/" server.properties
fi

# Mods
mkdir -p "$MODS_DIR"
declare -A SEEN

download_project() {
  local id="$1" label="${2:-$1}"
  [ -n "${SEEN[$id]:-}" ] && return
  SEEN[$id]=1
  local ver
  ver=$(curl -s -A "$UA" -G "https://api.modrinth.com/v2/project/${id}/version" \
        --data-urlencode "game_versions=[\"${MC_VERSION}\"]" \
        --data-urlencode 'loaders=["fabric"]' \
        | jq 'map(select(.version_type=="release"))[0] // .[0]')
  if [ -z "$ver" ] || [ "$ver" = "null" ]; then
    echo "WARNING: '${label}' has no version for Fabric ${MC_VERSION}. Skipping."
    return
  fi
  local url
  url=$(echo "$ver" | jq -r '.files | (map(select(.primary))[0] // .[0]) | .url')
  echo "Downloading ${label}: ${url##*/}"
  wget -q -P "$MODS_DIR" "$url"
  local dep
  for dep in $(echo "$ver" | jq -r '.dependencies[] | select(.dependency_type=="required") | .project_id // empty'); do
    download_project "$dep"
  done
}

download_by_name() {
  local name="$1" pid
  pid=$(curl -s -A "$UA" -G "https://api.modrinth.com/v2/search" \
        --data-urlencode "query=${name}" \
        --data-urlencode 'facets=[["project_type:mod"],["categories:fabric"]]' \
        --data-urlencode 'limit=10' \
        | jq -r --arg n "$name" '([.hits[] | select(.title | ascii_downcase == ($n | ascii_downcase))][0]
                                  // [.hits[] | select(.title | ascii_downcase | startswith($n | ascii_downcase))][0]).project_id // empty')
  if [ -z "$pid" ]; then
    echo "WARNING: could not find '${name}' on Modrinth. Skipping."
    return
  fi
  download_project "$pid" "$name"
}

download_project "fabric-api" "Fabric API"
for m in "${MODS[@]}"; do
  download_by_name "$m"
done

chown -R minecraft:minecraft /opt/minecraft/

echo ">> Starting the server"
systemctl start minecraft
echo "Done. Check the startup with: sudo journalctl -u minecraft -f"
