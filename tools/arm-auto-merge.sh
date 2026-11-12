#!/usr/bin/env bash
# Arm GitHub auto-merge on a bot pull request, but ONLY when it is safe to.
#
# THE TRAP THIS EXISTS FOR. On a branch with no required status check, GitHub
# auto-merge does not wait for anything: it merges IMMEDIATELY. A bot that runs
# `gh pr merge --auto` against an unprotected main is pushing to main with
# extra steps, and the `check` job it was meant to wait for would run after the
# merge, on a layer that is already being signed.
#
# So this refuses to arm unless the API says, right now, that:
#
#   1. the repository allows auto-merge at all, and
#   2. an ACTIVE ruleset on main requires the `check` job's status check,
#      by the exact context name check.yml gives that job.
#
# Anything else, including an API call that fails, leaves the pull request
# OPEN and unarmed, says so in the job summary, and exits 0. "Could not
# establish that the check is required" is treated as "it is not required":
# arming on a guess is the one outcome this must never produce. A PR left open
# costs a human a click; a PR merged unchecked costs a signed layer.
#
# It also refuses unless the pull request is the bot's own: opened by the App
# (ARM_BOT_LOGIN, e.g. `my-app[bot]`), from a branch of THIS repository, still
# open against the branch, and with its head at exactly the commit the caller
# made or inspected. A branch name proves nothing (anyone can open a pull
# request from a fork with a branch called `scanner/pins-x`), and auto-merge is
# armed with --match-head-commit so a later push cannot ride the armed merge.
#
# Usage:  tools/arm-auto-merge.sh <pr-number> <head-commit-sha>
# Needs:  GH_TOKEN (a token that can merge PRs), GITHUB_REPOSITORY,
#         ARM_BOT_LOGIN (the App's bot login).
# Writes: a line to $GITHUB_STEP_SUMMARY either way.

set -euo pipefail

PR="${1:?usage: arm-auto-merge.sh <pr-number> <head-commit-sha>}"
HEAD_OID="${2:?usage: arm-auto-merge.sh <pr-number> <head-commit-sha>}"
REPO="${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is not set}"
BOT="${ARM_BOT_LOGIN:?ARM_BOT_LOGIN is not set}"
BRANCH="${ARM_BRANCH:-main}"
CHECK_YML="${CHECK_YML:-.github/workflows/check.yml}"
SUMMARY="${GITHUB_STEP_SUMMARY:-/dev/stderr}"

leave_for_human() {
  echo "::warning::#$PR left open and NOT armed for auto-merge: $1. A human must merge it."
  echo "- #$PR was **not** armed for auto-merge: $1. **A human must merge it.**" >> "$SUMMARY"
  exit 0
}

# ── 0. is this the bot's own pull request, at the commit the caller means? ──
case "$PR" in ''|*[!0-9]*) leave_for_human "\"$PR\" is not a pull request number" ;; esac
printf '%s' "$HEAD_OID" | grep -Eqx '[0-9a-f]{40}' \
  || leave_for_human "\"$HEAD_OID\" is not a full commit sha"
PRJSON="$(gh api "repos/$REPO/pulls/$PR" 2>/dev/null)" \
  || leave_for_human "could not read pull request #$PR"
WHY="$(printf '%s' "$PRJSON" | jq -r --arg bot "$BOT" --arg repo "$REPO" \
         --arg oid "$HEAD_OID" --arg base "$BRANCH" '
  if .state != "open" then "it is not open"
  elif .user.login != $bot or .user.type != "Bot" then "it was opened by \(.user.login) (\(.user.type)), not the App \($bot)"
  elif .head.repo.full_name != $repo then "its head is not a branch of \($repo)"
  elif .base.ref != $base then "it targets \(.base.ref), not \($base)"
  elif .head.sha != $oid then "its head moved to \(.head.sha), not the inspected \($oid)"
  else "" end' 2>/dev/null)" || leave_for_human "could not parse pull request #$PR"
[ -z "$WHY" ] || leave_for_human "$WHY"

# ── the context name, read from check.yml rather than typed here ─────────────
# The `name:` of the `check:` job is the status-check context GitHub reports
# and a ruleset requires. Typed a second time here it would drift the first
# time someone rewords the job, and this script would then look for a context
# that no ruleset names and never arm again, silently.
CONTEXT="$(awk '
  /^  check:[[:space:]]*$/ { in_job = 1; next }
  in_job && /^  [^ #]/      { exit }
  in_job && /^    name:[[:space:]]/ {
    sub(/^    name:[[:space:]]*/, "")
    sub(/[[:space:]]+$/, "")
    gsub(/^["\047]|["\047]$/, "")
    print
    exit
  }' "$CHECK_YML")"
[ -n "$CONTEXT" ] || leave_for_human "could not read the check job's name from $CHECK_YML"

# ── 1. does the repository allow auto-merge at all? ──────────────────────────
ALLOW="$(gh api "repos/$REPO" --jq '.allow_auto_merge' 2>/dev/null || true)"
if [ "$ALLOW" != "true" ]; then
  # The REST field is only returned to some tokens; GraphQL's autoMergeAllowed
  # is readable with metadata access. Either must say an explicit `true`.
  ALLOW="$(gh api graphql \
    -f query='query($o:String!,$n:String!){repository(owner:$o,name:$n){autoMergeAllowed}}' \
    -f o="${REPO%%/*}" -f n="${REPO#*/}" \
    --jq '.data.repository.autoMergeAllowed' 2>/dev/null || true)"
fi
[ "$ALLOW" = "true" ] || leave_for_human "auto-merge is not enabled in this repository's settings (allow_auto_merge=${ALLOW:-unreadable})"

# ── 2. is `check` a required status check on main, by an ACTIVE ruleset? ─────
RULES="$(gh api "repos/$REPO/rules/branches/$BRANCH" 2>/dev/null)" \
  || leave_for_human "could not read the rules that apply to $BRANCH"
IDS="$(printf '%s' "$RULES" | jq -r --arg c "$CONTEXT" '
  [ .[]
    | select(.type == "required_status_checks")
    | select(any(.parameters.required_status_checks[]?; .context == $c))
    | .ruleset_id ] | unique | .[]' 2>/dev/null)" \
  || leave_for_human "could not parse the rules that apply to $BRANCH"
[ -n "$IDS" ] || leave_for_human "no ruleset on $BRANCH requires the status check \"$CONTEXT\""

# A ruleset in `evaluate` mode reports but does not block, so it does not make
# auto-merge wait either. Only `active` counts.
REQUIRED_BY=""
for id in $IDS; do
  ENF="$(gh api "repos/$REPO/rulesets/$id" --jq '.enforcement' 2>/dev/null || true)"
  if [ "$ENF" = "active" ]; then REQUIRED_BY="$id"; break; fi
done
[ -n "$REQUIRED_BY" ] || leave_for_human "the status check \"$CONTEXT\" is named only by rulesets that are not active ($(echo "$IDS" | tr '\n' ' '))"

# ── both hold: arm it ────────────────────────────────────────────────────────
# Squash: one signed commit per change on main, the shape main had when these
# bots pushed directly. GitHub makes and signs the merge commit.
gh pr merge "$PR" --repo "$REPO" --auto --squash --match-head-commit "$HEAD_OID"
echo "::notice::#$PR armed for auto-merge: ruleset $REQUIRED_BY requires \"$CONTEXT\" on $BRANCH"
echo "- #$PR armed for auto-merge. It merges once \`$CONTEXT\` passes (required by ruleset $REQUIRED_BY)." >> "$SUMMARY"
