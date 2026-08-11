# Git Production Deploy

Safely deploy your main development branch to a production branch through a GitHub Pull Request.

`git-production-deploy` is a small Git helper designed to make production deployment simple while keeping the existing GitHub Actions and DevOps pipeline untouched.

## How it works

```text
main / master
      │
      │ git prod
      ▼
Pull Request
      │
      ▼
GitHub Actions / CI
      │
      ├── Failed → STOP
      │
      └── Passed
            │
            ▼
      Production re-check
            │
            ▼
      Merge confirmation
            │
            ▼
      Merge PR
            │
            ▼
   Existing DevOps / CD
            │
            ▼
       Production
```

The tool does not deploy Docker containers, connect to servers, or modify your existing CI/CD pipeline.

It only manages the GitHub Pull Request flow.

## Requirements

You need:

* Git
* GitHub CLI
* A GitHub account with permission to create and merge Pull Requests

Install GitHub CLI:

https://cli.github.com/

Authenticate:

```bash
gh auth login
```

Verify:

```bash
gh auth status
```

## Installation

Clone the repository:

```bash
git clone https://github.com/YOUR_USERNAME/git-production-deploy.git
cd git-production-deploy
```

Run:

```bash
./install.sh
```

After installation:

```bash
git prod
```

## Basic usage

From your `main` or `master` branch:

```bash
git prod
```

The tool will:

1. Verify the repository.
2. Verify GitHub authentication.
3. Check the working tree.
4. Fetch the latest branches.
5. Verify the local branch is up to date.
6. Detect changes against production.
7. Ask for confirmation.
8. Create or reuse a Pull Request.
9. Wait for GitHub Actions checks.
10. Stop if checks fail.
11. Verify production has not changed.
12. Verify the Pull Request has not changed.
13. Verify that the Pull Request is mergeable.
14. Ask for final merge confirmation.
15. Merge the Pull Request.
16. Allow the existing DevOps/CD pipeline to handle production.

## Dry run

To see what would happen without creating or merging anything:

```bash
git prod --dry-run
```

The dry run does not:

* Create Pull Requests
* Merge Pull Requests
* Modify production
* Trigger a deployment directly

## Production branch

The default production branch is:

```text
prod
```

If your production branch has another name:

```bash
git prod --production-branch production
```

For example:

```bash
git prod --production-branch release
```

## Example

Suppose your repository has:

```text
main
prod
```

You finish your work:

```bash
git add .
git commit -m "Add new feature"
git push origin main
```

Then:

```bash
git prod
```

The tool creates:

```text
main → prod
```

and waits for the GitHub checks.

If the checks pass, you get a final confirmation:

```text
Merge Pull Request into prod? [y/N]:
```

Only after you confirm with:

```text
y
```

will the Pull Request be merged.

## Safety

The tool intentionally performs several safety checks before merging.

### Clean working tree

Uncommitted local changes stop the deployment.

### Up-to-date source branch

The local branch must match the remote branch.

### CI checks

The tool waits for GitHub Actions checks and stops if they fail.

### Production protection

The production branch is checked before and after CI.

If another developer changes production while the checks are running, the merge is stopped.

### Pull Request integrity

The Pull Request HEAD commit is checked before merging.

If someone changes the Pull Request while CI is running, the merge is stopped.

### Final confirmation

The tool never merges without an explicit confirmation.

## DevOps compatibility

`git-production-deploy` does not replace your DevOps pipeline.

After the Pull Request is merged:

```text
main → prod
```

your existing GitHub Actions / CD pipeline can continue to handle the actual production deployment.

This means the tool can be added to an existing project without changing its existing deployment infrastructure.

## License

MIT License.
