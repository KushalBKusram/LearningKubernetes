#!/usr/bin/env bash
# Day 09 lab: Git, "GitHub", and automated image builds (slides 197-215).
# Runs on the server. Safe to run more than once: it recreates its repositories
# and its container. Commit dates are fixed, so every run produces the same commit
# hashes and therefore the same image tags.
#
# Needs: the day 7 registry running, and the app sources from day 6.
#
# Leaves running:
#   day09-app   port 8109   deployed from the latest push to main
set -euo pipefail
cd "$(dirname "$0")"
. ../setup/lib.sh
need_docker

REG=localhost:5000
work=$PWD/.work # scratch space on the server, recreated on every run
repo=$work/app-repo
remote=$work/github.git
PW_FILE=$HOME/.course/registry-password

[ -s "$PW_FILE" ] && [ "$(docker container inspect -f '{{.State.Running}}' day07-registry 2>/dev/null)" = "true" ] || {
  echo "The day 7 registry is not running. Run: setup/run.sh day-07/lab.sh" >&2
  exit 1
}

registry_get() { curl -s -m 5 -u "courselab:$(cat "$PW_FILE")" "http://$REG$1"; }

# A neutral identity and fixed dates, only for this repository and this script.
author() { export GIT_AUTHOR_DATE="$1" GIT_COMMITTER_DATE="$1"; }

docker rm -f day09-app >/dev/null 2>&1 || true
rm -rf "$work"
mkdir -p "$repo"

step "1. Git is installed (slides 198-199)"
run git --version

step "2. A new repository: git init, .gitignore (slide 201)"
cd "$repo"
run git init -q -b main
git config user.name "Course Lab"
git config user.email "lab@example.invalid"
git config advice.detachedHead false
echo "The repository's identity is set for this repository only, not globally:"
echo "  $(git config --local user.name) <$(git config --local user.email)>"
echo
cp ../../../day-06/app/{server.js,package.json,package-lock.json,.dockerignore} .
cp ../../Dockerfile .
cat >.gitignore <<'EOF'
# Typical entries (slide 201)
.env
node_modules/
dist/
.DS_Store
EOF
mkdir node_modules && echo "never committed" >node_modules/ignored.txt
run ls -a
echo
echo "git status sees everything new except what .gitignore lists (node_modules/ is not shown):"
run git status --short

step "3. The three areas: working directory, staging area, repository (slide 203)"
run git add .
echo "Staged, not yet in the repository:"
run git status --short
author "2026-01-01T10:00:00Z"
run git commit -q -m "Add the Node.js app and its Dockerfile"
echo "Committed: nothing left to stage, and the commit has a unique hash (slide 205):"
run git status --short
run git log --oneline

step "4. A remote repository, and a hook that builds on every push (slides 209, 215)"
echo "GitHub is not available. A bare repository (a repository with no working files) plays"
echo "its part: it is what 'git push' sends to. Its post-receive hook is the automation:"
echo "git runs it after every push, as a GitHub-triggered build would."
run git init -q --bare -b main "$remote"
run cp ../../post-receive "$remote/hooks/post-receive"
chmod +x "$remote/hooks/post-receive"
run git remote add origin "$remote"
run git remote -v

step "5. Push: git push -> image build -> registry -> deployed container (slides 211, 215)"
echo "Everything after 'remote:' is printed by the hook, running inside the push."
echo "The registry stands in for Amazon ECR, and replacing the container for App Runner's auto-deploy."
run git push -u origin main 2>&1 | grep -E 'remote:|->|branch' | sed -e 's/^remote: /  hook: /' -e 's/ *$//'
first=$(git rev-parse --short=7 main)
echo
echo "Tags in the registry: $(registry_get /v2/day09-app/tags/list)"
echo "The running app:      $(curl -s -m 3 http://localhost:8109/api/info | jq -c '{version, commit, greeting}')"

step "6. Branches: develop a change without touching main (slide 207)"
run git checkout -q -b feature/greeting
sed -i 's/Hello from the Node app/Hello from the automated pipeline/' server.js
sed -i 's/"version": "1.0.0"/"version": "1.1.0"/' package.json
run git diff --stat
run git add server.js package.json
author "2026-01-01T11:00:00Z"
run git commit -q -m "Change the greeting and bump the version"
echo
echo "The hook only builds main. Pushing the branch builds nothing:"
run git push -q origin feature/greeting 2>&1 | sed -e 's/^remote: /  hook: /' -e 's/ *$//'
echo "Tags in the registry: $(registry_get /v2/day09-app/tags/list) (unchanged)"
echo
echo "Merge the branch into main (--no-ff keeps a visible merge commit) and push:"
run git checkout -q main
author "2026-01-01T12:00:00Z"
run git merge --no-ff -q -m "Merge feature/greeting" feature/greeting
run git push -q origin main 2>&1 | sed -e 's/^remote: /  hook: /' -e 's/ *$//'
second=$(git rev-parse --short=7 main)
echo
echo "History as a graph:"
run git log --oneline --graph --all

step "7. The result of the second push"
echo "Tags in the registry: $(registry_get /v2/day09-app/tags/list)"
echo "The running app:      $(curl -s -m 3 http://localhost:8109/api/info | jq -c '{version, commit, greeting}')"
echo "main is at $second, so the tag $second is the image that is running."

step "8. Going back: every image is still in the registry, tagged by commit (slides 205, 213)"
echo "The first image, built from commit $first, still says version 1.0.0:"
run docker run --rm "$REG/day09-app:$first" node -p "require('./package.json').version"
echo "(Starting one is a pull from the registry away, on any machine that can reach it.)"
echo
echo "Restoring the old state of a file from a commit (slide 205):"
run git checkout "$first" -- package.json
run git status --short
echo "package.json now says: $(jq -r .version package.json). Put it back:"
run git checkout HEAD -- package.json
echo "package.json says: $(jq -r .version package.json)"
echo
echo "Looking at the whole project as it was at the first commit, then returning to main:"
run git checkout -q "$first"
echo "greeting then: $(grep -o "GREETING = '[^']*'" server.js)"
run git checkout -q main
echo "greeting now:  $(grep -o "GREETING = '[^']*'" server.js)"

step "Done"
echo "day09-app  http://localhost:8109  (commit $second)"
echo "The working repository is $repo, and the 'GitHub' repository is $remote"
echo "Next: setup/run.sh day-09/verify.sh"
