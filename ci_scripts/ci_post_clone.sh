#!/bin/sh
set -e

# 1. Enter the root directory of the repository
cd "$CI_PRIMARY_REPOSITORY_PATH"

# 2. Use the official script to install the latest stable version of Tuist (or a specific version, e.g., export TUIST_VERSION=4.34.0)
curl -Ls https://tuist.io | bash

# 3. Ensure the installation directory is in PATH and manually grant execute permissions to prevent Permission denied
export PATH="$HOME/.local/bin:$PATH"
chmod +x "$HOME/.local/bin/tuist" || true

# 4. Install external dependencies and generate the project
tuist install
tuist generate --no-open