#!/usr/bin/env bash
# Prints the conclusion of every required check on a commit and fails
# unless all of them succeeded. Used by merge-pr.sh and the main guard
# while the repository cannot have a ruleset (see .github/rulesets/).
# Usage: required-checks.sh <commit-sha>   (GH_REPO or the current repo)
set -euo pipefail

REQUIRED_CHECKS=(ci pr-title)
sha=${1:?usage: required-checks.sh <commit-sha>}
repo=${GH_REPO:-$(gh repo view --json nameWithOwner --jq .nameWithOwner)}

status=0
for check in "${REQUIRED_CHECKS[@]}"; do
  conclusion=$(gh api "repos/$repo/commits/$sha/check-runs?check_name=$check&filter=latest" \
    --jq '.check_runs | max_by(.started_at) | if . == null then "missing" else (.conclusion // .status) end')
  echo "$check: $conclusion"
  [ "$conclusion" = success ] || status=1
done
exit "$status"
