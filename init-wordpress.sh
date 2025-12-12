#!/usr/bin/env sh

# 0. Check for root privileges using id
if [ "$(id -u)" -ne 0 ]; then
  echo ""
  echo "-----------------------------------------------"
  echo "❌  This script must be run as root (use sudo)."
  echo "ℹ️  Please run: sudo ./init-wordpress.sh"
  echo "-----------------------------------------------"
  echo ""
  exit 1
fi

# 1. OS Detection & Conditional Setup ---
IS_RHEL_FAMILY=0
if [ -f /etc/os-release ]; then
  # Check for RHEL or its common clones (CentOS, Rocky, Alma)
  if grep -q -E 'ID="rhel"|ID="centos"|ID="rocky"|ID="almalinux"' /etc/os-release; then
    IS_RHEL_FAMILY=1
  fi
fi

# 2. Initialization Script for WordPress Docker Volume 
PROJECT_NAME=$(basename "$PWD") 
VOLUME_NAME="${PROJECT_NAME}_app_data"
VOLUME_PATH=$(docker volume inspect -f '{{ .Mountpoint }}' "$VOLUME_NAME" 2>/dev/null)

if [ -z "$VOLUME_PATH" ]; then
  echo "❌  Docker volume $VOLUME_NAME does not exist. Please run 'docker compose up -d' first to create the volume."
  exit 1
fi

echo "✅  Initializing WordPress for project: $PROJECT_NAME"
echo "✅  Target Volume: $VOLUME_PATH"

# 3. Conditional 'set -e' based on OS family
if [ "$IS_RHEL_FAMILY" -eq 1 ]; then
  echo "ℹ️  Red Hat family OS detected. Proceeding without 'set -e'."
  
  # Check if setsebool command exists before running it
  if command -v setsebool >/dev/null 2>&1; then
    echo "⏳  Applying SELinux policy 'httpd_can_network_connect'..."
    setsebool -P httpd_can_network_connect 1
    echo "✅  SELinux policy applied."
  else
    echo "⚠️  'setsebool' command not found."
    exit 1
  fi

else
  echo "ℹ️  Non-Red Hat OS (e.g., Debian/Ubuntu) detected. Setting 'set -e'."
  # Exit immediately if a command exits with a non-zero status.
  set -e
fi

# 4. Empty volume check
if [ -n "$(ls -A "$VOLUME_PATH" 2>/dev/null)" ]; then
    echo "ℹ️  Volume $VOLUME_NAME already has files. Skipping initialization."
    exit 0
fi

# 5. Download WordPress core files to a temporary folder
echo "🚀  Volume is empty. Downloading WordPress to temporary folder..."
TEMP_DIR="./wordpress_temp_init"
mkdir -p "$TEMP_DIR"
curl -fsSL https://wordpress.org/latest.tar.gz | tar -xzf - -C "$TEMP_DIR" --strip-components=1

echo "✅  Copying WordPress files to volume: $VOLUME_PATH"

# 6. Copy files to Docker volume (requires sudo)
cp -a "$TEMP_DIR/." "$VOLUME_PATH/"

# 7. Remove temporary folder
echo "ℹ️  Cleaning up temporary files..."
rm -rf "$TEMP_DIR"

echo "✅  WordPress core files are copied to the volume."
echo "⏳  Changing file permissions..."  
docker compose exec php sh -c "chown -R www-data:www-data /var/www/html"
echo "✅  File permissions updated."

# 8. wp-config.php wait loop
WP_CONFIG="$VOLUME_PATH/wp-config.php"
echo "🚀  Open your site in the browser to continue WordPress setup."
printf "⏳  Wait for finishing WordPress initialization "

while [ ! -f "$WP_CONFIG" ]; do
  printf "." 
  sleep 2 
done
echo "" 
echo "✅  wp-config.php found! File exists."

# 9. HTTPS reverse-proxy snippet injection
if ! grep -q "HTTP_X_FORWARDED_PROTO" "$WP_CONFIG"; then
  echo "⏳  Injecting HTTPS reverse-proxy snippet..."

  HTTPS_BLOCK=$(cat <<'PHP'
/**
 * Handle HTTPS (SSL) behind a reverse proxy.
 */
if ( ! empty( $_SERVER['HTTP_X_FORWARDED_PROTO'] ) && $_SERVER['HTTP_X_FORWARDED_PROTO'] === 'https' ) {
    $_SERVER['HTTPS'] = 'on';
    $_SERVER['SERVER_PORT'] = 443;
}

PHP
)

  awk -v repl="$HTTPS_BLOCK" '
  /\/\* That'\''s all, stop editing! Happy publishing\. \*\// && !done {
    print repl;
    done=1
  }
  { print }' "$WP_CONFIG" > /tmp/wp-config.tmp

  mv /tmp/wp-config.tmp "$WP_CONFIG"
  docker compose exec php sh -c "chown www-data:www-data /var/www/html/wp-config.php"

  echo "✅  Injected HTTPS reverse-proxy snippet."
else
  echo "ℹ️  HTTPS reverse-proxy snippet already exists. Skipping."
fi

# 10. Redis Object Cache config injection
REDIS_SALT="${PROJECT_NAME}_"

if ! grep -q "WP_REDIS_HOST" "$WP_CONFIG"; then
  echo "⏳  Injecting Redis Object Cache config..."

  REDIS_BLOCK=$(cat <<PHP
/**
 * Redis server settings (Docker)
 * Host is the Docker service name.
 */
define('WP_CACHE', true);
define('WP_REDIS_HOST', 'redis');
define('WP_REDIS_PORT', 6379);
define('WP_CACHE_KEY_SALT', '${REDIS_SALT}');
define('WP_REDIS_SELECTIVE_FLUSH', true);

PHP
)

  awk -v repl="$REDIS_BLOCK" '
    /\/\* That'\''s all, stop editing! Happy publishing\. \*\// && !done {
      print repl;
      done=1
    }
    { print }' "$WP_CONFIG" > /tmp/wp-config.redis.tmp

  mv /tmp/wp-config.redis.tmp "$WP_CONFIG"
  docker compose exec php sh -c "chown www-data:www-data /var/www/html/wp-config.php"

  echo "✅  Injected Redis Object Cache config."
else
  echo "ℹ️  Redis config already exists in wp-config.php. Skipping."
fi

echo "✅  All tasks complete."