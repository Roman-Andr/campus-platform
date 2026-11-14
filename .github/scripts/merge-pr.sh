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

gh pr merge "$pr" --squash --match-head-commit "$head"
