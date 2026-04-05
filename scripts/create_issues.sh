#!/bin/bash

set -e

REPO="mschuhmacher/flash_forward"
PROJECT_NUMBER=2
PROJECT_OWNER="mschuhmacher"
PROJECT_ID="PVT_kwHOArUSts4BR6Lo"
STATUS_FIELD_ID="PVTSSF_lAHOArUSts4BR6Lozg_mONQ"
STATUS_TODO="f75ad846"
STATUS_DONE="98236657"

create_issue() {
  local title="$1"
  local type_label="$2"
  local complexity_label="$3"
  local status_option_id="$4"
  local milestone="$5"  # optional, pass milestone title

  echo "Creating: $title"

  local args=(--repo "$REPO" --title "$title" --body "" --label "$type_label" --label "$complexity_label")
  if [ -n "$milestone" ]; then
    args+=(--milestone "$milestone")
  fi

  url=$(gh issue create "${args[@]}" 2>&1 | tail -1)
  echo "  → $url"

  item_json=$(gh project item-add "$PROJECT_NUMBER" --owner "$PROJECT_OWNER" --url "$url" --format json)
  item_id=$(echo "$item_json" | python3 -c "import sys,json; print(json.load(sys.stdin)['id'])")

  gh project item-edit \
    --id "$item_id" \
    --project-id "$PROJECT_ID" \
    --field-id "$STATUS_FIELD_ID" \
    --single-select-option-id "$status_option_id" \
    > /dev/null

  echo "  ✓ done"
}

TODO=$STATUS_TODO
DONE=$STATUS_DONE

# ── BUGS ────────────────────────────────────────────────────────────────────
create_issue "Sign-up: continue button hidden by keyboard"                         "bug" "low"       $TODO "2.0.0"
create_issue "Sign-up: name not populated after email confirmation on different device" "bug" "medium" $TODO "2.0.0"
create_issue "Home screen: no clear path to create a session"                      "bug" "low"       $DONE "2.0.0"
create_issue "RAM overusage — WatchdogTermination (Sentry)"                        "bug" "medium"    $TODO "2.0.0"
create_issue "Conflict resolution: local vs. cloud data"                           "bug" "high"      $TODO ""
create_issue "Offline mode tests"                                                  "bug" "medium"    $TODO ""
create_issue "Review default exercise time fields (activeTime)"                    "bug" "low"       $TODO ""

# ── CHORES ──────────────────────────────────────────────────────────────────
create_issue "App Store Connect: add business name"                                "chore" "low"     $TODO "2.0.0"
create_issue "Supabase health-check cron job"                                      "chore" "low"     $TODO ""
create_issue "Add logger package (dev tooling)"                                    "chore" "low"     $TODO ""
create_issue "Ask Claude: add const for runtime optimisation"                      "chore" "low"     $TODO ""
create_issue "Ask Claude: evaluate widget extraction"                              "chore" "low"     $TODO ""
create_issue "Ask Claude: Flutter framework code review"                           "chore" "low"     $TODO ""

# ── FEATURES ────────────────────────────────────────────────────────────────
create_issue "Edit load in active session screen"                                  "feature" "medium" $TODO "2.0.0"
create_issue "Separate reps and load per set"                                      "feature" "high"   $TODO "2.1.0"
create_issue "Active session: next / previous set & rep navigation"                "feature" "medium" $TODO "2.0.0"
create_issue "Edit catalog sessions"                                               "feature" "medium" $DONE "2.0.0"
create_issue "Hide / restore catalog sessions"                                     "feature" "medium" $TODO "2.1.0"
create_issue "Onboarding screens"                                                  "feature" "high"   $TODO ""
create_issue "Supersets functionality"                                             "feature" "high"   $TODO "2.1.0"
create_issue "Remove logged sessions by swiping"                                   "feature" "low"    $TODO "2.1.0"
create_issue "Catalog field edit — UI feedback"                                    "feature" "low"    $TODO "2.0.0"
create_issue "Catalog propagation"                                                 "feature" "high"   $TODO "2.0.0"
create_issue "Option: exercise with no fixed time"                                 "feature" "medium" $DONE "2.0.0"
create_issue "Supabase deep linking (email confirmation)"                          "feature" "medium" $TODO ""
create_issue "lbs vs. kg setting"                                                  "feature" "low"    $TODO "2.0.0"
create_issue "Band resistance support"                                             "feature" "medium" $TODO "2.0.0"
create_issue "Today button in calendar"                                            "feature" "low"    $TODO ""
create_issue "Clear all logs button"                                               "feature" "low"    $TODO "2.0.0"
create_issue "Apple / Google sign-in"                                              "feature" "high"   $TODO ""
create_issue "Split add_item_screen"                                               "feature" "medium" $DONE "2.0.0"
create_issue "Convert addExerciseModalSheet to a screen"                           "feature" "low"    $DONE "2.0.0"
create_issue "Privacy statement screen"                                            "feature" "low"    $TODO "2.0.0"
create_issue "Profile settings menu"                                               "feature" "high"   $TODO "2.0.0"

# ── IDEAS ────────────────────────────────────────────────────────────────────
create_issue "Start a standalone workout or exercise"                              "idea" "medium"    $TODO ""
create_issue "Bottom navigation bar"                                               "idea" "high"      $DONE "2.0.0"
create_issue "Home screen: logged workouts tab"                                    "idea" "medium"    $DONE "2.0.0"
create_issue "Edit sessions / workouts / exercises screen"                         "idea" "medium"    $DONE "2.0.0"
create_issue "Profile page"                                                        "idea" "medium"    $DONE "2.0.0"
create_issue "Profile: app theme toggle"                                           "idea" "low"       $TODO "2.0.0"
create_issue "Grid view of exercise labels / phases"                               "idea" "high"      $TODO ""
create_issue "Long-press pause to extend timer"                                    "idea" "low"       $TODO "2.1.0"
create_issue "Animations"                                                          "idea" "medium"    $TODO ""
create_issue "Longitudinal progress tracking"                                      "idea" "high"      $TODO "2.1.0"
create_issue "Testing sessions"                                                    "idea" "medium"    $TODO "2.1.0"
create_issue "Timers without sessions"                                             "idea" "medium"    $TODO ""
create_issue "Import training schedule"                                            "idea" "high"      $TODO ""
create_issue "Friend profiles & social graph"                                      "idea" "very high" $TODO ""
create_issue "Public and private sessions"                                         "idea" "high"      $TODO ""
create_issue "Add sessions from other users (teams / coaches)"                     "idea" "very high" $TODO ""

echo ""
echo "All issues created."
