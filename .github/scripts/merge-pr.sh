#!/usr/bin/env bash
# Squash-merges a pull request only if its required checks are green on
# the current head commit, which must not change before the merge. Stands
# in for the required status checks of a ruleset (.github/rulesets/).
# Usage: .github/scripts/merge-pr.sh <pr-number>
set -euo pipefail

pr=${1:?usage: merge-pr.sh <pr-number>}
here=$(dirname "$0")

read -r head state base < <(gh pr view "$pr" \
  --json headRefOid,state,baseRefName --jq '"\(.headRefOid) \(.state) \(.baseRefName)"')
if [ "$state" != OPEN ] || [ "$base" != main ]; then
  echo "PR #$pr is $state against $base; expected an open PR against main." >&2
  exit 1
fi

if ! "$here/required-checks.sh" "$head"; then
  echo "PR #$pr: required checks are not green on $head; not merging." >&2
  exit 1
fi

# Check the actual Git history, without the file/commit limits of the
# compare API. Fetch both tips so this also works from another worktree.
# FETCH_HEAD's first entry is main; no local branch is checked out or moved.
git fetch --no-tags origin main "$head"
main=$(git rev-parse FETCH_HEAD)
ancestor=$(git merge-base "$head" "$main")
if ! git diff --quiet "$ancestor" "$main" -- backend/src/campus/migrations/; then
  echo "PR #$pr: main has migration changes missing from this branch; not merging." >&2
  echo "Merge or rebase onto main and wait for green ci and pr-title checks." >&2
  exit 1
fi

gh pr merge "$pr" --squash --match-head-commit "$head"
