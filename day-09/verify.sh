#!/usr/bin/env bash
# Day 09 checks. Run after lab.sh.
set -uo pipefail
cd "$(dirname "$0")"
. ../setup/lib.sh
need_docker

REG=localhost:5000
work=$PWD/.work
repo=$work/app-repo
remote=$work/github.git
PW_FILE=$HOME/.course/registry-password

g() { git -C "$repo" "$@"; }
tags() { curl -s -m 5 -u "courselab:$(cat "$PW_FILE")" "http://$REG/v2/day09-app/tags/list" | jq -r '.tags[]'; }
head_short() { g rev-parse --short=7 main; }
first_short() { g rev-list --max-parents=0 main | head -1 | cut -c1-7; }
feature_short() { g rev-parse --short=7 feature/greeting; }
info() { curl -s -m 3 http://localhost:8109/api/info | jq -r "$1"; }

git_installed() { git --version; }
three_commits() { [ "$(g rev-list --count main)" = "3" ]; }
has_merge_commit() { [ "$(g rev-list --merges --count main)" = "1" ]; }
two_branches() { [ "$(g branch --format='%(refname:short)' | sort | paste -sd,)" = "feature/greeting,main" ]; }
clean_tree() { [ -z "$(g status --porcelain)" ]; }
ignored() { g check-ignore -q node_modules/ignored.txt; }
not_tracked() { [ -z "$(g ls-files node_modules)" ]; }
local_identity() { [ "$(g config --local user.email)" = "lab@example.invalid" ]; }
global_untouched() { [ "$(git config --global user.email 2>/dev/null || true)" != "lab@example.invalid" ]; }
bare_repo() { [ "$(git -C "$remote" rev-parse --is-bare-repository)" = "true" ]; }
hook_executable() { [ -x "$remote/hooks/post-receive" ]; }
remote_has_main() { [ "$(git -C "$remote" rev-parse main)" = "$(g rev-parse main)" ]; }
remote_has_feature() { [ "$(git -C "$remote" rev-parse feature/greeting)" = "$(g rev-parse feature/greeting)" ]; }
tag_present() { local t; t=$(tags); grep -qx "$1" <<<"$t"; }
tag_absent() { local t; t=$(tags); ! grep -qx "$1" <<<"$t"; }
exactly_tags() { [ "$(tags | sort | paste -sd,)" = "$(printf '%s\n' latest "$(first_short)" "$(head_short)" | sort | paste -sd,)" ]; }
running() { [ "$(docker container inspect -f '{{.State.Running}}' day09-app)" = "true" ]; }
runs_latest_commit() { [ "$(docker container inspect -f '{{.Config.Image}}' day09-app)" = "$REG/day09-app:$(head_short)" ]; }
app_commit() { [ "$(info .commit)" = "$(head_short)" ]; }
app_version() { [ "$(info .version)" = "1.1.0" ]; }
app_greeting() { [ "$(info .greeting)" = "Hello from the automated pipeline" ]; }
app_health() { [ "$(curl -s -m 3 http://localhost:8109/health | jq -r .status)" = "ok" ]; }
old_image_version() { [ "$(docker run --rm "$REG/day09-app:$(first_short)" node -p "require('./package.json').version")" = "1.0.0" ]; }
old_image_commit() { [ "$(docker run --rm "$REG/day09-app:$(first_short)" printenv APP_COMMIT)" = "$(first_short)" ]; }
latest_is_head() {
  [ "$(docker image inspect "$REG/day09-app:latest" --format '{{.Id}}')" = "$(docker image inspect "$REG/day09-app:$(head_short)" --format '{{.Id}}')" ]
}

step "Day 09 verification"
echo "Git"
check "git is installed" git_installed
check "main has 3 commits (initial, feature, merge)" three_commits
check "one of them is a merge commit" has_merge_commit
check "branches are main and feature/greeting" two_branches
check "the working tree is clean" clean_tree
check ".gitignore excludes node_modules/" ignored
check "node_modules/ is not tracked" not_tracked
check "the repository uses its own identity (repository-local config)" local_identity
check "the global Git config was not changed" global_untouched
echo "the remote ('GitHub') and its hook"
check "the remote is a bare repository" bare_repo
check "the build hook is installed and executable" hook_executable
check "the remote's main equals the local main" remote_has_main
check "the feature branch was pushed too" remote_has_feature
echo "automated builds"
check "the registry has an image tagged with the first commit hash" tag_present "$(first_short)"
check "the registry has an image tagged with the latest main hash" tag_present "$(head_short)"
check "the registry has the tag latest" tag_present latest
check "the feature branch push did not create an image" tag_absent "$(feature_short)"
check "the tags are exactly: latest and one per push to main" exactly_tags
check "latest is the same image as the newest commit's tag" latest_is_head
echo "the deployed container"
check "day09-app is running" running
check "it runs the image of the newest commit" runs_latest_commit
check "its page reports that commit hash" app_commit
check "it reports version 1.1.0 (the merged change)" app_version
check "it shows the new greeting" app_greeting
check "/health reports ok" app_health
echo "going back"
check "the first commit's image still exists and reports version 1.0.0" old_image_version
check "that image knows its own commit hash" old_image_commit
summary
