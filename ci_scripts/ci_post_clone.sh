#!/bin/sh

# Exit immediately if an error occurs.
set -e

# 1. Navigate to the root directory of the repository (the directory one level above ci_scripts).
cd ..

# 2. Install Tuist (installation via Mise is recommended as it is the fastest and supports specific versions).
curl https://mise.run | sh
export PATH="$HOME/.local/bin:$PATH"

# If your repository root directory contains a .mise.toml or .tool-versions file, the promise will automatically read the corresponding version.
# If not, uncomment the following line and specify your Tuist version:
# mise use -g tuist@4.34.0
mise install

# 3. If the project uses Tuist cache or external dependencies (SPM/Dependencies), fetch the dependencies first
mise exec -- tuist install

# 4. Generate Xcode Workspace and Project
mise exec -- tuist generate --no-open