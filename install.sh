#!/usr/bin/env bash

# Crescent Framework - Global CLI Installation Script
# This script installs the `crescent` command globally

set -e

echo "🌙 Installing Crescent CLI globally..."

# Get the directory where this script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
CLI_PATH="$SCRIPT_DIR/crescent-cli.lua"

# Check if crescent-cli.lua exists
if [ ! -f "$CLI_PATH" ]; then
    echo "❌ Error: crescent-cli.lua not found at $CLI_PATH"
    exit 1
fi

# Create the wrapper script
WRAPPER_CONTENT="#!/usr/bin/env bash
# Crescent CLI - Auto-generated wrapper
exec luvit \"$CLI_PATH\" \"\$@\"
"

# Determine installation directory
if [ -w "/usr/local/bin" ]; then
    INSTALL_DIR="/usr/local/bin"
    echo "$WRAPPER_CONTENT" > "$INSTALL_DIR/crescent"
    chmod +x "$INSTALL_DIR/crescent"
else
    echo "📝 /usr/local/bin is not writable. Using sudo..."
    echo "$WRAPPER_CONTENT" | sudo tee "$INSTALL_DIR/crescent" > /dev/null
    sudo chmod +x "$INSTALL_DIR/crescent"
fi

# Verify installation
if command -v crescent &> /dev/null; then
    echo "✅ Crescent CLI installed successfully!"
    echo "📍 Location: $INSTALL_DIR/crescent"
    echo "🚀 Try: crescent --help"
else
    echo "⚠️  Installation completed but 'crescent' command not found in PATH"
    echo "   Make sure $INSTALL_DIR is in your PATH"
fi
