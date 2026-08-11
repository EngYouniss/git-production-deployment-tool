#!/usr/bin/env bash

set -euo pipefail

# ============================================================
# git-production-deploy
#
# Safely deploy the current main/master branch to production
# through a GitHub Pull Request.
#
# Usage:
#
#   git prod
#   git prod --dry-run
#   git prod --production-branch production
#
# Requirements:
#
#   Git
#   GitHub CLI (gh)
# ============================================================


# ============================================================
# Configuration
# ============================================================

PRODUCTION_BRANCH="prod"
DRY_RUN=false


# ============================================================
# Parse arguments
# ============================================================

while [ $# -gt 0 ]; do

    case "$1" in

        --dry-run)
            DRY_RUN=true
            shift
            ;;

        --production-branch)
            if [ -z "${2:-}" ]; then
                echo "❌ Missing production branch name."
                exit 1
            fi

            PRODUCTION_BRANCH="$2"
            shift 2
            ;;

        --production-branch=*)
            PRODUCTION_BRANCH="${1#*=}"
            shift
            ;;

        --help|-h)

            cat <<EOF

git-production-deploy

Safely deploy the current main/master branch to production
through a GitHub Pull Request.

Usage:

    git prod
    git prod --dry-run
    git prod --production-branch production

Options:

    --dry-run
        Show what would happen without creating or merging
        a Pull Request.

    --production-branch <branch>
        Set the production branch.

        Default:
            prod

Examples:

    git prod

    git prod --dry-run

    git prod --production-branch production

EOF

            exit 0
            ;;

        *)
            echo "❌ Unknown option: $1"
            echo "Run 'git prod --help' for usage."
            exit 1
            ;;

    esac

done


# ============================================================
# Helper functions
# ============================================================

error() {

    echo
    echo "❌ $1"
    echo

    exit 1
}


success() {

    echo "✓ $1"

}


info() {

    echo "ℹ️  $1"

}


# ============================================================
# 1. Verify Git repository
# ============================================================

git rev-parse --is-inside-work-tree >/dev/null 2>&1 \
    || error "This is not a Git repository."


# ============================================================
# 2. Verify GitHub CLI
# ============================================================

command -v gh >/dev/null 2>&1 \
    || error "GitHub CLI (gh) is not installed.

Install:
https://cli.github.com/

Then authenticate:
gh auth login"


# ============================================================
# 3. Verify GitHub authentication
# ============================================================

gh auth status >/dev/null 2>&1 \
    || error "GitHub CLI is not authenticated.

Run:
gh auth login"


# ============================================================
# 4. Detect current branch
# ============================================================

CURRENT_BRANCH=$(git branch --show-current)

if [ -z "$CURRENT_BRANCH" ]; then

    error "Could not determine the current Git branch."

fi


# ============================================================
# 5. Only allow main/master as deployment source
# ============================================================

if [ "$CURRENT_BRANCH" != "main" ] && \
   [ "$CURRENT_BRANCH" != "master" ]; then

    error "Production deployment must start from main or master.

Current branch:
$CURRENT_BRANCH"

fi


SOURCE_BRANCH="$CURRENT_BRANCH"


# ============================================================
# 6. Verify working tree
# ============================================================

if [ -n "$(git status --porcelain)" ]; then

    echo
    echo "❌ Your working tree is not clean."
    echo
    echo "Commit or stash your changes first."
    echo
    git status --short

    exit 1

fi


# ============================================================
# 7. Detect repository
# ============================================================

REPOSITORY=$(gh repo view \
    --json nameWithOwner \
    --jq '.nameWithOwner')


[ -n "$REPOSITORY" ] \
    || error "Could not determine the GitHub repository."


# ============================================================
# 8. Header
# ============================================================

echo
echo "========================================"
echo "       Production Deployment"
echo "========================================"
echo

echo "Repository: $REPOSITORY"
echo "Branch:     $SOURCE_BRANCH → $PRODUCTION_BRANCH"

if [ "$DRY_RUN" = true ]; then

    echo "Mode:       DRY RUN (no changes will be made)"

fi

echo


# ============================================================
# 9. Fetch latest branches
# ============================================================

echo "🔄 Fetching latest $SOURCE_BRANCH and $PRODUCTION_BRANCH..."

git fetch origin \
    "$SOURCE_BRANCH" \
    "$PRODUCTION_BRANCH"

success "Remote branches updated."


# ============================================================
# 10. Verify local source branch
# ============================================================

LOCAL_SHA=$(git rev-parse HEAD)

REMOTE_SOURCE_SHA=$(git rev-parse \
    "origin/$SOURCE_BRANCH")


if [ "$LOCAL_SHA" != "$REMOTE_SOURCE_SHA" ]; then

    error "Local $SOURCE_BRANCH does not match origin/$SOURCE_BRANCH.

Local:
$LOCAL_SHA

Remote:
$REMOTE_SOURCE_SHA

Push or pull the latest changes first."

fi


success "Local $SOURCE_BRANCH matches origin/$SOURCE_BRANCH."


# ============================================================
# 11. Check differences
# ============================================================

if git diff --quiet \
    "origin/$PRODUCTION_BRANCH..origin/$SOURCE_BRANCH"; then

    echo
    info "No file differences between $SOURCE_BRANCH and $PRODUCTION_BRANCH."
    echo "Nothing to deploy."

    exit 0

fi


success "Changes detected between $SOURCE_BRANCH and $PRODUCTION_BRANCH."


# ============================================================
# 12. Dry run
# ============================================================

if [ "$DRY_RUN" = true ]; then

    echo
    echo "========================================"
    echo "           DRY RUN RESULT"
    echo "========================================"
    echo

    echo "Deployment:"
    echo "$SOURCE_BRANCH → $PRODUCTION_BRANCH"
    echo

    echo "The following WOULD happen:"
    echo

    echo "  1. Create/find Pull Request"
    echo "     $SOURCE_BRANCH → $PRODUCTION_BRANCH"
    echo

    echo "  2. Wait for GitHub Actions / Checks"
    echo

    echo "  3. Verify all checks succeeded"
    echo

    echo "  4. Re-check production branch"
    echo

    echo "  5. Verify Pull Request integrity"
    echo

    echo "  6. Ask for final merge confirmation"
    echo

    echo "  7. Merge Pull Request"
    echo

    echo "  8. Existing DevOps/CD handles production"
    echo

    echo "✓ No Pull Request was created."
    echo "✓ No merge was performed."
    echo "✓ Production was NOT changed."
    echo

    exit 0

fi


# ============================================================
# 13. First confirmation
# ============================================================

echo
echo "⚠️  You are about to deploy ${SOURCE_BRANCH^^} to PRODUCTION."
echo

printf "Continue? [y/N]: "

read -r ANSWER


case "$ANSWER" in

    y|Y|yes|YES)
        ;;

    *)
        echo
        echo "✗ Deployment cancelled."
        exit 0
        ;;

esac


# ============================================================
# 14. Re-fetch after confirmation
# ============================================================

echo
echo "🔄 Re-checking remote state before deployment..."

git fetch origin \
    "$SOURCE_BRANCH" \
    "$PRODUCTION_BRANCH"


LATEST_SOURCE_SHA=$(git rev-parse \
    "origin/$SOURCE_BRANCH")


if [ "$LATEST_SOURCE_SHA" != "$REMOTE_SOURCE_SHA" ]; then

    error "The $SOURCE_BRANCH branch changed after confirmation.

Please run:
git prod

again."

fi


success "Remote $SOURCE_BRANCH has not changed."


# ============================================================
# 15. Save production SHA
# ============================================================

PRODUCTION_SHA_BEFORE=$(git rev-parse \
    "origin/$PRODUCTION_BRANCH")


# ============================================================
# 16. Find existing PR
# ============================================================

echo
echo "🔍 Checking for existing Pull Request..."


PR_NUMBER=$(gh pr list \
    --repo "$REPOSITORY" \
    --base "$PRODUCTION_BRANCH" \
    --head "$SOURCE_BRANCH" \
    --state open \
    --json number \
    --jq '.[0].number')


# ============================================================
# 17. Create PR if necessary
# ============================================================

if [ -z "$PR_NUMBER" ]; then

    echo
    echo "➕ Creating Pull Request..."
    echo "$SOURCE_BRANCH → $PRODUCTION_BRANCH"

    PR_URL=$(gh pr create \
        --repo "$REPOSITORY" \
        --base "$PRODUCTION_BRANCH" \
        --head "$SOURCE_BRANCH" \
        --title "Deploy $SOURCE_BRANCH to $PRODUCTION_BRANCH" \
        --body "Automated production deployment from $SOURCE_BRANCH to $PRODUCTION_BRANCH.")

    PR_NUMBER=$(gh pr view "$PR_URL" \
        --repo "$REPOSITORY" \
        --json number \
        --jq '.number')


    success "Pull Request #$PR_NUMBER created."

else

    success "Existing Pull Request found: #$PR_NUMBER"

fi


echo
echo "Pull Request: #$PR_NUMBER"


# ============================================================
# 18. Save PR HEAD SHA
# ============================================================

PR_HEAD_SHA=$(gh pr view "$PR_NUMBER" \
    --repo "$REPOSITORY" \
    --json headRefOid \
    --jq '.headRefOid')


[ -n "$PR_HEAD_SHA" ] \
    || error "Could not determine Pull Request HEAD."


# ============================================================
# 19. Wait for checks to appear
# ============================================================

echo
echo "========================================"
echo "       Waiting for GitHub Checks"
echo "========================================"
echo

echo "Pull Request: #$PR_NUMBER"
echo
echo "⏳ Waiting for GitHub Actions to start..."
echo


CHECKS_FOUND=false

CHECK_ATTEMPTS=0

MAX_CHECK_ATTEMPTS=60


while [ "$CHECKS_FOUND" = false ]; do

    CHECK_ATTEMPTS=$((CHECK_ATTEMPTS + 1))


    CHECK_OUTPUT=$(gh pr checks "$PR_NUMBER" \
        --repo "$REPOSITORY" 2>&1 || true)


    if ! echo "$CHECK_OUTPUT" \
        | grep -qi "no checks reported"; then

        CHECKS_FOUND=true
        break

    fi


    if [ "$CHECK_ATTEMPTS" -ge "$MAX_CHECK_ATTEMPTS" ]; then

        error "No GitHub checks appeared within 10 minutes.

Please check Pull Request #$PR_NUMBER on GitHub."

    fi


    printf "Checks not available yet... waiting 10s (%s/%s)\r" \
        "$CHECK_ATTEMPTS" \
        "$MAX_CHECK_ATTEMPTS"


    sleep 10

done


echo
success "GitHub checks detected."


# ============================================================
# 20. Wait for all checks
# ============================================================

echo
echo "⏳ Waiting for all checks to complete..."
echo


if ! gh pr checks "$PR_NUMBER" \
    --repo "$REPOSITORY" \
    --watch \
    --interval 10; then

    echo
    echo "========================================"
    echo "       Production Deployment STOPPED"
    echo "========================================"
    echo

    echo "❌ One or more GitHub checks failed."
    echo

    echo "Pull Request: #$PR_NUMBER"
    echo

    echo "Review the checks on GitHub, fix the problem,"
    echo "then run:"
    echo
    echo "    git prod"
    echo

    exit 1

fi


echo
success "All GitHub checks completed successfully."


# ============================================================
# 21. Re-fetch production
# ============================================================

echo
echo "🔄 Re-checking production branch..."

git fetch origin "$PRODUCTION_BRANCH"


PRODUCTION_SHA_AFTER=$(git rev-parse \
    "origin/$PRODUCTION_BRANCH")


if [ "$PRODUCTION_SHA_AFTER" != "$PRODUCTION_SHA_BEFORE" ]; then

    error "Another Pull Request was merged into $PRODUCTION_BRANCH
while your CI was running.

Production changed.

Run:
git prod

again so the deployment can be revalidated."

fi


success "Production branch has not changed."


# ============================================================
# 22. Re-check PR state
# ============================================================

echo
echo "🔍 Re-checking Pull Request..."


PR_STATE=$(gh pr view "$PR_NUMBER" \
    --repo "$REPOSITORY" \
    --json state \
    --jq '.state')


if [ "$PR_STATE" != "OPEN" ]; then

    error "Pull Request #$PR_NUMBER is no longer open.

Current state:
$PR_STATE"

fi


# ============================================================
# 23. Verify PR HEAD
# ============================================================

CURRENT_PR_HEAD_SHA=$(gh pr view "$PR_NUMBER" \
    --repo "$REPOSITORY" \
    --json headRefOid \
    --jq '.headRefOid')


if [ "$CURRENT_PR_HEAD_SHA" != "$PR_HEAD_SHA" ]; then

    error "Pull Request HEAD changed while CI was running.

The Pull Request must be revalidated."

fi


success "Pull Request HEAD is unchanged."


# ============================================================
# 24. Check mergeability
# ============================================================

MERGEABLE=$(gh pr view "$PR_NUMBER" \
    --repo "$REPOSITORY" \
    --json mergeable \
    --jq '.mergeable')


MERGE_STATE=$(gh pr view "$PR_NUMBER" \
    --repo "$REPOSITORY" \
    --json mergeStateStatus \
    --jq '.mergeStateStatus')


echo
echo "Mergeable:   $MERGEABLE"
echo "Merge state: $MERGE_STATE"


if [ "$MERGEABLE" = "CONFLICTING" ]; then

    error "Pull Request has merge conflicts.

Resolve them manually before deploying."

fi


if [ "$MERGEABLE" = "UNKNOWN" ]; then

    error "GitHub could not determine whether the Pull Request is mergeable.

Check Pull Request #$PR_NUMBER on GitHub."

fi


if [ "$MERGE_STATE" = "BEHIND" ]; then

    error "Pull Request is behind $PRODUCTION_BRANCH.

Please update and revalidate the Pull Request."

fi


success "Pull Request is ready to merge."


# ============================================================
# 25. Final confirmation
# ============================================================

echo
echo "========================================"
echo "       Ready for Production"
echo "========================================"
echo

echo "Pull Request: #$PR_NUMBER"
echo "Deployment:   $SOURCE_BRANCH → $PRODUCTION_BRANCH"
echo

echo "✓ GitHub checks passed"
echo "✓ Production branch unchanged"
echo "✓ Pull Request HEAD unchanged"
echo "✓ Pull Request is mergeable"
echo


printf "Merge Pull Request into %s? [y/N]: " \
    "$PRODUCTION_BRANCH"


read -r MERGE_ANSWER


case "$MERGE_ANSWER" in

    y|Y|yes|YES)
        ;;

    *)
        echo
        echo "✗ Merge cancelled."
        echo

        echo "The Pull Request remains open:"
        echo "https://github.com/$REPOSITORY/pull/$PR_NUMBER"

        exit 0
        ;;

esac


# ============================================================
# 26. Final merge
# ============================================================

echo
echo "🚀 Merging Pull Request #$PR_NUMBER..."
echo


gh pr merge "$PR_NUMBER" \
    --repo "$REPOSITORY" \
    --merge \
    --delete-branch=false \
    --match-head-commit "$CURRENT_PR_HEAD_SHA"


# ============================================================
# 27. Done
# ============================================================

echo
echo "========================================"
echo "       Production Deployment Started"
echo "========================================"
echo

echo "✓ Pull Request #$PR_NUMBER merged."
echo "✓ $SOURCE_BRANCH → $PRODUCTION_BRANCH"
echo

echo "✓ Existing DevOps/CD pipeline will now"
echo "  handle the production deployment."
echo

echo "========================================"
echo
