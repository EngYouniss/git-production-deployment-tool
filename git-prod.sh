#!/usr/bin/env bash

set -e

# ============================================================
# Git Production Deployment
#
# Usage:
#
#   git prod
#   git prod --dry-run
#
# Flow:
#
#   master/main
#       ↓
#   Pull Request → prod
#       ↓
#   Wait for GitHub Actions / Checks
#       ↓
#   Verify checks
#       ↓
#   Re-check prod
#       ↓
#   Final confirmation
#       ↓
#   Merge PR
#       ↓
#   Existing DevOps / CD
#       ↓
#   Production
# ============================================================


DRY_RUN=false

if [ "$1" = "--dry-run" ]; then
    DRY_RUN=true
fi


# ============================================================
# Helpers
# ============================================================

error() {
    echo
    echo "❌ $1"
    exit 1
}

info() {
    echo "ℹ️  $1"
}

success() {
    echo "✓ $1"
}


# ============================================================
# 1. Validate Git repository
# ============================================================

git rev-parse --is-inside-work-tree >/dev/null 2>&1 \
    || error "This is not a Git repository."


# ============================================================
# 2. Detect current branch
# ============================================================

CURRENT_BRANCH=$(git branch --show-current)

if [ "$CURRENT_BRANCH" != "main" ] && [ "$CURRENT_BRANCH" != "master" ]; then
    error "Production deployment is only allowed from main or master.

Current branch: $CURRENT_BRANCH"
fi

DEPLOY_BRANCH="$CURRENT_BRANCH"


# ============================================================
# 3. Working tree must be clean
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
# 4. Get GitHub repository
# ============================================================

REPOSITORY=$(gh repo view --json nameWithOwner --jq '.nameWithOwner')

[ -n "$REPOSITORY" ] \
    || error "Could not determine GitHub repository."


# ============================================================
# 5. Header
# ============================================================

echo
echo "========================================"
echo "       Production Deployment"
echo "========================================"
echo
echo "Repository: $REPOSITORY"
echo "Branch:     $DEPLOY_BRANCH → prod"

if [ "$DRY_RUN" = true ]; then
    echo "Mode:       DRY RUN (no changes will be made)"
fi

echo


# ============================================================
# 6. Fetch latest remote branches
# ============================================================

echo "🔄 Fetching latest $DEPLOY_BRANCH and prod..."

git fetch origin "$DEPLOY_BRANCH" prod

success "Remote branches updated."


# ============================================================
# 7. Local branch must match origin
# ============================================================

LOCAL_SHA=$(git rev-parse HEAD)
REMOTE_SHA=$(git rev-parse "origin/$DEPLOY_BRANCH")

if [ "$LOCAL_SHA" != "$REMOTE_SHA" ]; then

    error "Local $DEPLOY_BRANCH does not match origin/$DEPLOY_BRANCH.

Local :  $LOCAL_SHA
Remote: $REMOTE_SHA

Please push/pull the latest changes first."

fi

success "Local $DEPLOY_BRANCH matches origin/$DEPLOY_BRANCH."


# ============================================================
# 8. Check whether there is anything to deploy
#
# We compare the actual file content.
# This avoids relying only on Git ancestry because prod
# may contain merge commits.
# ============================================================

if git diff --quiet "origin/prod..origin/$DEPLOY_BRANCH"; then

    echo
    info "No file differences between $DEPLOY_BRANCH and prod."
    echo "Nothing to deploy."

    exit 0
fi

success "Changes detected between $DEPLOY_BRANCH and prod."


# ============================================================
# 9. Dry run
# ============================================================

if [ "$DRY_RUN" = true ]; then

    echo
    echo "========================================"
    echo "           DRY RUN RESULT"
    echo "========================================"
    echo

    echo "Deployment:"
    echo "$DEPLOY_BRANCH → prod"
    echo

    echo "The following WOULD happen:"
    echo

    echo "  1. Create/find Pull Request"
    echo "     $DEPLOY_BRANCH → prod"
    echo

    echo "  2. Wait for GitHub Actions / Checks"
    echo

    echo "  3. Verify all checks succeeded"
    echo

    echo "  4. Re-check prod before merge"
    echo

    echo "  5. Merge the Pull Request"
    echo

    echo "  6. Existing DevOps/CD handles Production"
    echo

    echo "✓ No Pull Request was created."
    echo "✓ No merge was performed."
    echo "✓ Production was NOT changed."
    echo

    exit 0
fi


# ============================================================
# 10. Production confirmation
# ============================================================

echo
echo "⚠️  You are about to deploy ${DEPLOY_BRANCH^^} to PRODUCTION."
printf "Continue? [y/N]: "

read ANSWER

case "$ANSWER" in

    y|Y|yes|YES)
        ;;

    *)
        echo
        echo "✗ Deployment cancelled."
        exit 0
        ;;

esac

echo


# ============================================================
# 11. Re-fetch after confirmation
# ============================================================

echo "🔄 Re-checking remote state before deployment..."

git fetch origin "$DEPLOY_BRANCH" prod

LATEST_REMOTE_SHA=$(git rev-parse "origin/$DEPLOY_BRANCH")

if [ "$LATEST_REMOTE_SHA" != "$REMOTE_SHA" ]; then

    error "The $DEPLOY_BRANCH branch changed while waiting for confirmation.

Please run git prod again."

fi

success "Remote $DEPLOY_BRANCH has not changed."


# ============================================================
# 12. Save current production SHA
#
# We will use this later to make sure that another developer
# did not change prod while our CI was running.
# ============================================================

PROD_SHA_BEFORE=$(git rev-parse "origin/prod")


# ============================================================
# 13. Find existing Pull Request
# ============================================================

echo
echo "🔍 Checking for existing Pull Request..."

PR_NUMBER=$(gh pr list \
    --repo "$REPOSITORY" \
    --base prod \
    --head "$DEPLOY_BRANCH" \
    --state open \
    --json number \
    --jq '.[0].number')


# ============================================================
# 14. Create PR if it doesn't exist
# ============================================================

if [ -z "$PR_NUMBER" ]; then

    echo
    echo "➕ Creating Pull Request..."
    echo "$DEPLOY_BRANCH → prod"

    PR_URL=$(gh pr create \
        --repo "$REPOSITORY" \
        --base prod \
        --head "$DEPLOY_BRANCH" \
        --title "Deploy $DEPLOY_BRANCH to production" \
        --body "Automated production deployment from $DEPLOY_BRANCH.")

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
# 15. Get PR HEAD SHA
# ============================================================

PR_HEAD_SHA=$(gh pr view "$PR_NUMBER" \
    --repo "$REPOSITORY" \
    --json headRefOid \
    --jq '.headRefOid')

[ -n "$PR_HEAD_SHA" ] \
    || error "Could not determine Pull Request HEAD commit."


# ============================================================
# 16. Wait for GitHub Actions / Checks
#
# IMPORTANT:
#
# Immediately after creating a PR, GitHub Actions may not have
# registered the checks yet.
#
# Therefore:
#
#   no checks
#       ↓
#   wait
#       ↓
#   check again
#
# We do NOT treat "no checks reported" as a failure.
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

# Maximum wait for checks to appear:
# 60 attempts × 10 seconds = 10 minutes.

MAX_CHECK_ATTEMPTS=60


while [ "$CHECKS_FOUND" = false ]; do

    CHECK_ATTEMPTS=$((CHECK_ATTEMPTS + 1))

    CHECK_OUTPUT=$(gh pr checks "$PR_NUMBER" \
        --repo "$REPOSITORY" 2>&1 || true)


    # --------------------------------------------------------
    # Checks have appeared
    # --------------------------------------------------------

    if ! echo "$CHECK_OUTPUT" | grep -qi "no checks reported"; then

        CHECKS_FOUND=true
        break

    fi


    # --------------------------------------------------------
    # Timeout
    # --------------------------------------------------------

    if [ "$CHECK_ATTEMPTS" -ge "$MAX_CHECK_ATTEMPTS" ]; then

        echo
        echo "========================================"
        echo "       Production Deployment STOPPED"
        echo "========================================"
        echo

        echo "❌ No GitHub checks appeared within"
        echo "   the expected waiting period."
        echo

        echo "Pull Request: #$PR_NUMBER"
        echo

        echo "Please check the Pull Request on GitHub."

        exit 1

    fi


    # --------------------------------------------------------
    # Wait
    # --------------------------------------------------------

    printf "   Checks not available yet... waiting 10s (%s/%s)\r" \
        "$CHECK_ATTEMPTS" "$MAX_CHECK_ATTEMPTS"

    sleep 10

done


echo
echo "✓ GitHub checks detected."
echo


# ============================================================
# 17. Wait until all checks finish
# ============================================================

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
# 18. Re-fetch production after CI
#
# Another developer may have merged something into prod
# while our CI was running.
# ============================================================

echo
echo "🔄 Re-checking production branch..."

git fetch origin prod

PROD_SHA_AFTER=$(git rev-parse "origin/prod")


if [ "$PROD_SHA_AFTER" != "$PROD_SHA_BEFORE" ]; then

    echo
    echo "========================================"
    echo "       Production Changed"
    echo "========================================"
    echo

    echo "⚠️  Another Pull Request was merged into prod"
    echo "while your deployment was being validated."
    echo

    echo "Previous prod:"
    echo "  $PROD_SHA_BEFORE"
    echo

    echo "Current prod:"
    echo "  $PROD_SHA_AFTER"
    echo

    echo "Production deployment has been stopped for safety."
    echo

    echo "Please run:"
    echo
    echo "    git prod"
    echo

    echo "again so GitHub can validate your deployment"
    echo "against the latest production state."

    exit 1

fi


success "Production branch has not changed."


# ============================================================
# 19. Re-check PR state
# ============================================================

echo
echo "🔍 Re-checking Pull Request..."


PR_STATE=$(gh pr view "$PR_NUMBER" \
    --repo "$REPOSITORY" \
    --json state \
    --jq '.state')


if [ "$PR_STATE" != "OPEN" ]; then

    error "Pull Request #$PR_NUMBER is no longer open.

Current state: $PR_STATE"

fi


# ============================================================
# 20. Verify PR HEAD did not change
# ============================================================

CURRENT_PR_HEAD_SHA=$(gh pr view "$PR_NUMBER" \
    --repo "$REPOSITORY" \
    --json headRefOid \
    --jq '.headRefOid')


if [ "$CURRENT_PR_HEAD_SHA" != "$PR_HEAD_SHA" ]; then

    error "Pull Request HEAD changed while deployment was running.

The Pull Request must be revalidated before merging."

fi


success "Pull Request HEAD is unchanged."


# ============================================================
# 21. Check PR mergeability
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


# ============================================================
# 22. Handle conflicts
# ============================================================

if [ "$MERGEABLE" = "CONFLICTING" ]; then

    error "Pull Request has merge conflicts.

Resolve the conflicts manually before deploying."

fi


if [ "$MERGEABLE" = "UNKNOWN" ]; then

    error "GitHub could not determine whether the Pull Request is mergeable.

Please check Pull Request #$PR_NUMBER on GitHub."

fi


# ============================================================
# 23. Handle PR behind prod
# ============================================================

if [ "$MERGE_STATE" = "BEHIND" ]; then

    error "Pull Request is behind prod.

Another change may have reached production.
Please update/revalidate the Pull Request before running git prod again."

fi


success "Pull Request is ready to merge."


# ============================================================
# 24. Final confirmation
# ============================================================

echo
echo "========================================"
echo "       Ready for Production"
echo "========================================"
echo

echo "Pull Request: #$PR_NUMBER"
echo "Deployment:    $DEPLOY_BRANCH → prod"
echo

echo "✓ GitHub checks passed"
echo "✓ Production branch unchanged"
echo "✓ Pull Request HEAD unchanged"
echo "✓ Pull Request is mergeable"
echo


printf "Merge Pull Request into PROD? [y/N]: "


read MERGE_ANSWER


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
# 25. Final merge
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
# 26. Done
# ============================================================

echo
echo "========================================"
echo "       Production Deployment Started"
echo "========================================"
echo

echo "✓ Pull Request #$PR_NUMBER merged."
echo "✓ $DEPLOY_BRANCH → prod"
echo

echo "✓ Existing DevOps/CD pipeline will now"
echo "  handle the production deployment."
echo

echo "========================================"
echo

