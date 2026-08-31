# Infra-as-Code: GitHub + Terraform Cloud

## Architecture

| Repo | Manages | TFC Workspace |
|---|---|---|
| `tf-github` | GitHub repos, branch protection | `terraform-github` |
| `tf-terraform` | TFC projects, teams, users, access, workspaces | `terraform-infra` |

`tf-terraform` manages `tf-github`'s workspace (and its own, self-referentially). Both VCS-driven: PR → speculative plan → merge → auto-apply.

Per-repo setup detail: 
- [tf-github/README.md](https://github.com/Minyanaing/tf-github/blob/main/README.md)
- [tf-terraform/README.md](https://github.com/Minyanaing/tf-terraform/blob/main/README.md)

Every step below states **Where:** — the exact folder to run commands in, or "Console" for browser-based setup. There are three possible locations throughout: the parent folder (containing both repos), `tf-github/`, and `tf-terraform/` — they are never interchangeable.

---

## Step 0 — Local folders

**Where:** parent folder (e.g. `infra-github/`, containing both repos as subfolders)
```cmd
mkdir tf-github
mkdir tf-terraform
```
**Why:** two separate state domains — GitHub-side resources shouldn't share a Terraform state/workspace with TFC-side resources, so they can be applied, reviewed, and permissioned independently.

## Step 1 — Create GitHub repos (manual, one-time)

**Where:** Console (github.com)

New repository → name it (`tf-github`, `tf-terraform`) → **no** README/.gitignore/license.
**Why no starter files:** an empty remote avoids a merge conflict on your first `git push` from a locally-initialized repo.

## Step 2 — Connect local folders to the repos

**Where:** inside `tf-terraform/`, then inside `tf-github/` — run each block from that specific folder
```cmd
cd tf-terraform
git init
git remote add origin https://github.com/<org>/tf-terraform.git
git branch -M main
```
```cmd
cd ..\tf-github
git init
git remote add origin https://github.com/<org>/tf-github.git
git branch -M main
```
**Why:** standard git bootstrap — nothing Terraform-specific yet. Note each `git remote add` points at a **different** repo URL — don't copy-paste both blocks into the same folder.

## Step 3 — Terraform Cloud org + user token

**Where:** Console (app.terraform.io) for the org; then **any one folder** (`tf-github/` or `tf-terraform/` — doesn't matter which) for the login command
1. Create Org in TFC (if not already created) — Console.
2. ```cmd
   terraform login
   ```
   **Why:** generates a personal API token and stores it in `%APPDATA%\terraform.d\credentials.tfrc.json` — a machine-wide file, **not** per-folder. Running this once from inside either `tf-github/` or `tf-terraform/` authenticates the CLI for both. You do NOT need to run it twice.

## Step 4 — GitHub token (PAT) creation + setup

**Where:** Console (github.com) to create it; **`tf-github/` only** to set it locally — the `github` provider only exists in that repo, `tf-terraform` never needs this token

**Create:** GitHub → Settings → Developer settings → Personal access tokens → Generate new token (classic). Scopes: `repo`, `admin:org`.
**Why these scopes:** `repo` lets Terraform manage repos/branch protection; `admin:org` is needed for any future org-level GitHub resources (teams, org membership).

**Set up locally (run inside `tf-github/`, or set it in your shell profile so it's always present):**
```cmd
set GITHUB_TOKEN=ghp_xxxxxxxxxxxx
```
**Why:** the `github` Terraform provider reads this env var automatically — no token in code, no token in state as a provider block argument. It has no effect and isn't needed in `tf-terraform/`.

Persistent across sessions: `setx GITHUB_TOKEN "ghp_xxxxxxxxxxxx"`.

**Test it works (can run from anywhere, it only hits GitHub's API):**
```cmd
curl.exe -H "Authorization: token %GITHUB_TOKEN%" https://api.github.com/user
```
**Why test first:** a bad/expired token surfaces as a confusing provider auth error later — cheaper to catch here.

## Step 5 — TFC VCS Provider (console, one-time)

**Where:** Console (app.terraform.io + github.com) — no local folder involved

Org Settings → Providers → Add VCS Provider → **GitHub.com (Custom)**.
**Why "Custom" over "GitHub App":** the App option is often greyed out on personal GitHub accounts (plan-gated); the Custom OAuth flow works on any account tier.

1. GitHub → Settings → Developer settings → OAuth Apps → New OAuth App.
   - Homepage URL: `https://app.terraform.io`
   - Callback URL: copy the exact value shown on TFC's "Add VCS Provider" form.
2. Generate Client Secret. Paste Client ID + Secret into TFC → Save → authorize via GitHub redirect.
3. Click into the created VCS provider in TFC → copy its **Token ID** (`ot-...`).
**Why you need this ID:** it's referenced directly in **`tf-terraform/workspaces.tf`**'s `vcs_repo.oauth_token_id` (not `tf-github` — workspace *linking* is managed from the `tf-terraform` codebase) — this is what lets a TFC workspace attach a webhook to a specific GitHub repo.

## Step 6 — Write provider config for both repos

**Where:** `tf-terraform/main.tf` for the first block, `tf-github/main.tf` for the second — two different files in two different folders

`tf-terraform/main.tf`:
```hcl
terraform {
  required_version = ">= 1.6.0"
  cloud {
    organization = "<YOUR_TFC_ORG>"
    workspaces { name = "terraform-infra" }
  }
  required_providers {
    tfe = { source = "hashicorp/tfe", version = "~> 0.55" }
  }
}
provider "tfe" {}
data "tfe_organization" "this" {
  name = "<YOUR_TFC_ORG>"
}
```

`tf-github/main.tf`:
```hcl
terraform {
  required_version = ">= 1.6.0"
  cloud {
    organization = "<YOUR_TFC_ORG>"
    workspaces { name = "terraform-github" }
  }
  required_providers {
    github = { source = "integrations/github", version = "~> 6.0" }
  }
}
variable "github_org" {
  type = string
}
provider "github" {
  owner = var.github_org
}
```
**Why the `cloud{}` block:** this is what makes `terraform init` create/attach to a TFC workspace and store state remotely — no local `.tfstate` to lose or leak. Note the two files point at **different** TFC workspace names (`terraform-infra` vs `terraform-github`) — this is what keeps the two folders' state separate.

**Where:** both `tf-github/.gitignore` and `tf-terraform/.gitignore` — same content, one file per folder
```
.terraform/
*.tfstate
*.tfstate.*
*.tfvars
crash.log
```
**Why commit `.terraform.lock.hcl` instead of ignoring it:** it pins the exact provider version + checksums, so local runs and TFC's remote runs resolve the identical provider — without it TFC could silently pull a newer version and produce unexpected diffs.

**Where:** `tf-github/terraform.tfvars` (this variable only exists in `tf-github`'s config)
```hcl
github_org = "<your-github-org-or-username>"
```
This file is gitignored (real value, don't commit it). Also add a **committed** `tf-github/terraform.tfvars.example` with the placeholder, so the repo documents the required variable without leaking it.

## Step 7 — Init, validate, first plan

**Where:** run this full block once inside `tf-github/`, and again once inside `tf-terraform/` — two separate runs, two separate folders
```cmd
terraform init
terraform validate
terraform plan
```
**Why `init` first:** on a workspace name that doesn't exist yet in TFC, `init` auto-creates it (CLI-driven, empty state) — this is how `terraform-infra` and `terraform-github` came into existence, one per folder.

## Step 8 — Build out `tf-github`

**Where:** `tf-github/repo_list.tf` (data you edit) and `tf-github/repo.tf` (resource logic, rarely touched) — see [tf-github/README.md](https://github.com/Minyanaing/tf-github/blob/main/README.md) for the full field reference.

## Step 9 — Import existing repos (they already exist on GitHub from Step 1)

**Where:** inside `tf-github/`
```cmd
cd tf-github
terraform import "github_repository.this[\"tf-github\"]" tf-github
terraform import "github_repository.this[\"tf-terraform\"]" tf-terraform
terraform plan
```
**Why import instead of apply:** the repos already exist — `apply` without importing first would try to create duplicates and fail (or, worse, could conflict/error in confusing ways). Reconcile any diff (e.g. `visibility`) in `repo_list.tf` to match reality, then `terraform apply` (still inside `tf-github/`).

## Step 10 — Build out `tf-terraform`

**Where:** `tf-terraform/projects.tf`, `tf-terraform/teams.tf`, `tf-terraform/access.tf`, `tf-terraform/workspaces.tf` — all data-driven from `local` maps. See [tf-terraform/README.md](https://github.com/Minyanaing/tf-terraform/blob/main/README.md) for the full field reference.

## Step 11 — Link workspaces to VCS

**Where:** inside `tf-terraform/` — this manages both workspaces (`terraform-github` AND `terraform-infra`) from this one folder, even though `terraform-github` belongs to the *other* repo. This is intentional: `tf-terraform` is where all TFC-side configuration lives.

Both `terraform-github` and `terraform-infra` workspaces already exist (created by `cloud{}` in Step 7) — **import, don't create**:
```cmd
cd tf-terraform
terraform import "tfe_workspace.this[\"tf-github\"]" ws-xxxxxxxxxxxxx      # get ID: TFC UI → workspace → Settings → General
terraform import "tfe_workspace.this[\"tf-terraform\"]" ws-yyyyyyyyyyyyy
terraform plan
terraform apply
```
**Why import here too:** same reasoning as Step 9 — these workspaces already exist; treating them as new-to-create would conflict.

**If `apply` fails with "Repository doesn't exist or isn't accessible"** even though the repo is public and the identifier is correct: the OAuth grant needs a refresh.
1. **Where:** Console (github.com) → Settings → Applications → Authorized OAuth Apps → find the TFC app → Revoke.
2. **Where:** Console (app.terraform.io) → VCS Providers → reconnect/re-authorize (redoes the OAuth handshake with a fresh view of your repos).
3. **Where:** inside `tf-terraform/` → retry `terraform apply`.

## Step 12 — TFC workspace variables (console, one-time per workspace)

**Where:** Console (app.terraform.io) — set on each workspace directly, not in any local file (this is what makes them visible to remote/VCS-triggered runs, which don't read your local shell or `.tfvars`)

| Workspace | Variable | Type | Why |
|---|---|---|---|
| `terraform-github` | `github_org` | terraform var | Same reason as local `terraform.tfvars` in `tf-github/` — but VCS-triggered runs execute on TFC's infra, not your machine, so they can't see your local file. |
| `terraform-github` | `GITHUB_TOKEN` | env var, sensitive | Same — the provider needs this env var, and remote runs don't inherit your shell's env vars from Step 4. |
| `terraform-infra` | `TFE_TOKEN` | env var, sensitive | The workspace's own default execution identity has limited org permissions (can't reliably create/modify other workspaces or projects) — an Org API token fixes this. |

## Step 13 — Push everything, verify the loop works

**Where:** run separately inside `tf-github/` and inside `tf-terraform/` — each repo has its own git history
```cmd
git add <files>
git commit -m "initial setup"
git push origin main
```
(First push per repo can go straight to `main` — branch protection doesn't exist until `github_branch_protection` is applied.)

**Standard day-2 workflow (from inside whichever folder you're changing):**
```cmd
git checkout -b my-change
:: edit files
git add <files>
git commit -m "message"
git push origin my-change
```
Open PR → TFC auto-runs a **speculative plan** (PR check + TFC UI, plan-only, never applies) → review → merge → TFC runs for real on `main` → auto-applies (if the workspace's project has `auto_apply = true`; else confirm manually in TFC UI — Console).

---

## Day-2 operations — what to edit for common changes

| Task | Folder + file |
|---|---|
| New GitHub repo | `tf-github/repo_list.tf` |
| New TFC project (+ its own auto-apply policy) | `tf-terraform/projects.tf` → `local.projects` |
| New team | `tf-terraform/teams.tf` → `local.teams` |
| Add user to team | `tf-terraform/teams.tf` → `local.team_members` |
| Grant team→project access | `tf-terraform/access.tf` → `local.team_project_access` |
| New repo needs its own TFC workspace | `tf-terraform/workspaces.tf` → `local.repo_workspaces` |

Full field references live in each repo's own README.

## Known gotchas

- **Module `source = "../..."` fails on remote/VCS runs** — CLI-driven remote execution uploads only the working directory, not parent paths. Keep everything flat in one directory rather than splitting into `configs/` + `modules/` across sibling folders.
- **`enforce_admins = false`** lets repo admins bypass branch protection entirely — set `true` if "no direct push" must apply to everyone, including owners.
- **All 3 GitHub merge methods `false`** is rejected by the API (`no_merge_method`) — at least one must stay `true`.
- **Branch protection on private repos needs GitHub Pro** on personal accounts (free plan only allows it on public repos) — use a per-repo `enable_branch_protection` toggle to skip it until upgraded.
- **`terraform state mv` required** whenever a resource's address changes (map key added, module wrap/unwrap, rename) — otherwise `plan` shows a destroy+recreate instead of a no-op.
- **Newly created TFC workspaces need an explicit `project_id`** — omitting it can fail with "Project not found"; look the ID up via the TFC UI URL (`.../projects/prj-...`) rather than the "Default Project" name lookup (unreliable via API).
- **"Repository doesn't exist or isn't accessible"** on `tfe_workspace` apply, even for a public repo with a working OAuth connection elsewhere — re-authorize the OAuth grant (revoke on GitHub, reconnect in TFC).
- **`GITHUB_TOKEN` set in one folder's terminal session doesn't carry to another** — if you `cd` between `tf-github/` and `tf-terraform/` in the same terminal it's fine (env vars persist per-session, not per-folder), but a **new** terminal window needs it set again unless you used `setx`.
