#!/usr/bin/env bash

set -euo pipefail

echo
echo "========================================"
echo "     Git Production Deploy Installer"
echo "========================================"
echo


# ------------------------------------------------------------
# Check Git
# ------------------------------------------------------------

if ! command -v git >/dev/null 2>&1; then

    echo "❌ Git is not installed."
    echo "Install Git first:"
    echo "https://git-scm.com/downloads"

    exit 1

fi

echo "✓ Git detected."


# ------------------------------------------------------------
# Check GitHub CLI
# ------------------------------------------------------------

if ! command -v gh >/dev/null 2>&1; then

    echo
    echo "❌ GitHub CLI (gh) is not installed."
    echo
    echo "Install it from:"
    echo "https://cli.github.com/"
    echo

    exit 1

fi

echo "✓ GitHub CLI detected."


# ------------------------------------------------------------
# Check GitHub authentication
# ------------------------------------------------------------

if ! gh auth status >/dev/null 2>&1; then

    echo
    echo "⚠️  GitHub CLI is not authenticated."
    echo
    echo "Run:"
    echo
    echo "    gh auth login"
    echo
    echo "Then run this installer again."

    exit 1

fi

echo "✓ GitHub CLI authenticated."


# ------------------------------------------------------------
# Determine script location
# ------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

SOURCE_SCRIPT="$SCRIPT_DIR/git-prod.sh"

if [ ! -f "$SOURCE_SCRIPT" ]; then

    echo
    echo "❌ git-prod.sh was not found."

    exit 1

fi


# ------------------------------------------------------------
# Install location
# ------------------------------------------------------------

INSTALL_DIR="$HOME/.git-production-deploy"

mkdir -p "$INSTALL_DIR"

cp "$SOURCE_SCRIPT" "$INSTALL_DIR/git-prod.sh"

chmod +x "$INSTALL_DIR/git-prod.sh"

echo "✓ git-prod.sh installed."


# ------------------------------------------------------------
# Configure Git alias
# ------------------------------------------------------------

git config --global alias.prod '!bash "$HOME/.git-production-deploy/git-prod.sh"'

echo "✓ Git alias configured."


# ------------------------------------------------------------
# Finished
# ------------------------------------------------------------

echo
echo "========================================"
echo "          Installation Complete"
echo "========================================"
echo

echo "You can now use:"
echo

echo "    git prod"
echo

echo "Dry run:"
echo

echo "    git prod --dry-run"
echo

echo "Production branch:"
echo

echo "    git prod --production-branch production"
echo

echo "✓ Installation completed successfully."
echo
