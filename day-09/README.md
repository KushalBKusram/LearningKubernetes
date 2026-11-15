# Day 09: Git, GitHub, ECR and automated image builds

**Status:** run on the server on 2026-11-14; all 27 checks in `verify.sh` pass, and the deployed app answers from the Mac. Ready for you to validate.

**Slides:** 197-215. It needs the day 7 registry and the day 6 app sources.

## What the slides cover

- What Git is, installing it, `git init`, `.gitignore` (slides 198-201).
- The three areas (working directory, staging area, repository); `git add`, `git commit`, `git status` (slide 203).
- Commit hashes, `git log`, restoring a previous state (slide 205).
- Branches and merging (slide 207).
- GitHub as a hosting platform for Git repositories (slide 209).
- Amazon ECR as a registry, and the automated chain: a change on GitHub builds an image in ECR, which deploys to App Runner (slides 211-215).

## What gets built here

The chain from slide 211, all on the server:

```
git push main  ->  "GitHub" (a bare repository)  ->  post-receive hook  ->  docker build
               ->  registry (ECR stand-in)  ->  new container (App Runner stand-in)
```

| File | What it does |
|---|---|
| `lab.sh` | Creates a repository for the app, makes commits, branches and a merge, and pushes. Each push to `main` builds, publishes and deploys. Leaves `day09-app` running. |
| `post-receive` | The hook. It builds the pushed commit, tags the image with the commit hash, pushes it to the registry, and replaces the container. |
| `Dockerfile` | The day 6 Dockerfile plus `ARG COMMIT`, so the page shows which commit it was built from. |
| `verify.sh` | 27 pass/fail checks. |
| `cleanup.sh` | Removes the container, the local images and both repositories. |

Commit dates are fixed in the lab, so every run produces the same commit hashes and the same image tags. The hashes written in this README (`1c06480`, `b12a242`) are from the run on 2026-11-14; they change only if the day 6 app files change.

The app runs on port 8109.

## Run it

From the Mac:

```bash
setup/run.sh day-09/lab.sh
```

```bash
setup/run.sh day-09/verify.sh
```

## How to validate

| # | Do this | You should see |
|---|---|---|
| 1 | Run `setup/validate.sh 09` on the Mac | `27 passed, 0 failed` |
| 2 | Open http://<server>:8109/api/info | `"version":"1.1.0"`, `"commit":"b12a242"`, greeting "Hello from the automated pipeline" |
| 3 | Run `ssh $COURSE_HOST 'git -C ~/Projects/Kubernetes/day-09/.work/app-repo log --oneline --graph --all'` | Three commits: the first, a feature commit, and a merge commit |
| 4 | Run `ssh $COURSE_HOST 'curl -s -u courselab:$(cat ~/.course/registry-password) localhost:5000/v2/day09-app/tags/list'` | Tags `1c06480`, `b12a242` and `latest`. Those are the hashes of the first commit and of the merge commit. The feature commit has no image |

Things to try yourself.

**Push a change and watch it deploy.** Make a third commit in the working repository and push it. The hook's output appears in your terminal, and the page at port 8109 shows the new hash.

```bash
ssh $COURSE_HOST 'cd ~/Projects/Kubernetes/day-09/.work/app-repo && sed -i "s/automated pipeline/pipeline, third change/" server.js && git commit -qam "Third change" && git push origin main'
```

Then reload http://<server>:8109. A new commit hash is shown, and the registry has a third tag.

**Roll back.** Run the first commit's image next to the new one. It is still in the registry, tagged by its hash:

```bash
ssh $COURSE_HOST 'docker run --rm -p 8199:3000 localhost:5000/day09-app:1c06480'
```

Open http://<server>:8199 (stop it with Ctrl+C). It shows version 1.0.0.

The next run of `lab.sh` recreates the repositories from scratch, so the third commit disappears.

## Differences from the slides

- **There is no GitHub.** A bare Git repository on the server takes its place. `git push` works the same way. What GitHub adds on top (the website, pull requests, issues, collaborators) is not reproduced. Slide 209 mentions these, and they are not needed for the build chain.
- **The automation is a Git hook, not an AWS service.** The slides have AWS watch a GitHub repository and build the image. Here the same trigger is a `post-receive` hook, which runs after every push. A hook runs on the machine that receives the push, as any CI system does.
- **The registry is the day 7 registry, not ECR.** The build logs in with its own credentials (the `courselab` user), kept in a separate Docker config directory, so it does not change anyone's login. On AWS this would be an IAM role (day 8), with no password.
- **Replacing the container stands in for App Runner's automatic deployment.** App Runner does a managed rolling deployment, which this does not.
- The slides give the install commands for Git on each system. Git was already installed on the server.
- Images are tagged with the commit hash, plus `latest`. Slide 17 already showed tags; the hash tag is what lets you go back to any version, which `latest` cannot.

## Without AWS

ECR and App Runner are not available, so a local registry and a replaced container stand in, as described above. Nothing was needed from AWS for the Git part.

Images pushed to the registry stay there until the registry's volume is removed (`day-07/cleanup.sh --all`), because that registry does not allow deleting images through its API.
