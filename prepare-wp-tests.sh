#!/bin/bash -e

# Convenient functions for printing colored text
function green {
  # green text to stdout
	echo "$@" | sed $'s,.*,\e[32m&\e[m,' | xargs -0 printf
}

function yellow {
	# yellow text to stderr
	echo "$@" | sed $'s,.*,\e[33m&\e[m,' | >&2 xargs -0 printf
}

function red {
	# red text to stderr
	echo "$@" | sed $'s,.*,\e[31m&\e[m,' | >&2 xargs -0 printf
}

# Check Bash version
if [[ "${BASH_VERSINFO[0]}" -lt 4 ]]; then
    red "Error: Bash version 4 or later is required for this script."
    exit 1
fi

# Define defaults
declare -A defaults
defaults=(
    ["WP_VERSION"]="latest"
    ["WP_CORE_DIR"]="/tmp/wordpress"
    ["TMPDIR"]="/tmp"
    ["WP_TESTS_DIR"]="/tmp/wordpress-tests-lib"
    ["WP_MULTISITE"]="0"
    ["DB_NAME"]="wordpress_unit_tests"
    ["DB_USER"]="root"
    ["DB_PASS"]=""
    ["DB_HOST"]="localhost"
    ["SKIP_DB_CREATE"]="true"
    ["CLONE_VIP_MU_PLUGINS"]="true"
    ["CLONE_VIP_MU_PLUGINS"]="true"
)

check_env_vars() {
    for var in "${!defaults[@]}"; do
        if [ -z "${!var}" ]; then
            yellow "Warning: environment variable $var is unset. Falling back to default: ${defaults[$var]}"
        fi
        export "${var}"="${!var:-${defaults[$var]}}"
    done
}

# Check if environment variables are set
check_env_vars

# Install WordPress to WP_CORE_DIR
curl -s https://raw.githubusercontent.com/wp-cli/sample-plugin/master/bin/install-wp-tests.sh | bash -s "$DB_NAME" "$DB_USER" "$DB_PASS" "$DB_HOST" "$WP_VERSION" "$SKIP_DB_CREATE"
green "WordPress installed to ${WP_CORE_DIR} with test suite at ${WP_TESTS_DIR}."

# Reset wp-content folder
rm -rf "${WP_CORE_DIR}/wp-content/"
mkdir "${WP_CORE_DIR}/wp-content/"
green "Local codebase copied to ${WP_CORE_DIR}/wp-content/."

# Rsync . into WP_CORE_DIR/wp-content/
rsync -aWq \
    --no-compress \
    --delete \
    --exclude '.git' \
    --exclude '.npm' \
    --exclude 'node_modules' \
    . "${WP_CORE_DIR}/wp-content/"

if [ "$CLONE_VIP_MU_PLUGINS" = "true" ]; then
    green "Cloning VIP Go mu-plugins..."
    cd "${WP_CORE_DIR}/wp-content/"

    # Checkout VIP Go mu-plugins to mu-plugins
    if [ ! -d "mu-plugins" ]; then
        git clone \
            --recursive \
            --depth=1 \
            https://github.com/Automattic/vip-go-mu-plugins-built.git mu-plugins
    else
        yellow "VIP Go mu-plugins already exists, attempting to update..."
        cd mu-plugins
        git pull
        cd ..
    fi

    # Copy object-cache.php to wp-content
    green "Copying ${WP_CORE_DIR}/wp-content/object-cache.php to ${WP_CORE_DIR}/wp-content/object/cache..."
    cp -f "${WP_CORE_DIR}/wp-content/mu-plugins/object-cache.php" "${WP_CORE_DIR}/wp-content/object-cache.php"

    # Remove plugins which are not very nice to phpunit
    green "Removing plugins which are not very nice to phpunit..."
    rm -f mu-plugins/vaultpress.php \
        mu-plugins/wordpress-importer.php \
        mu-plugins/rewrite-rules-inspector.php \
        .phpunit.result.cache
fi

# Plug Mantle (handled within composer script)
yellow "Consider using the Mantle framework to wire tests up for you automatically! (https://mantle.alley.com/)"

# Announce success
green "Ready to test ${WP_CORE_DIR}/wp-content/..."
