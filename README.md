# tf-terraform

Manages Terraform Cloud itself — projects, teams, users/access, and workspaces (including its own) — run through TFC workspace `terraform-infra`.

## Files

| File | Purpose |
|---|---|
| `main.tf` | provider/backend config — rarely touched |
| `projects.tf` | TFC projects + per-project `auto_apply` policy — **edit to add a project** |
| `teams.tf` | TFC teams, org membership — **edit to add a team/user** |
| `access.tf` | team → project access grants — **edit to grant access** |
| `workspaces.tf` | one `tfe_workspace` per managed repo (including this one) — **edit to add a workspace** |

## One-time setup (console/UI)

1. **TFC org** created, plus a user token via `terraform login`.
2. **VCS Provider** (Org Settings → Providers → Add VCS Provider → **GitHub.com (Custom)** — use this over "GitHub App" if that's greyed out, common on personal accounts):
   - Create a GitHub OAuth App (Settings → Developer settings → OAuth Apps), callback URL copied from TFC's form.
   - Paste Client ID/Secret into TFC → authorize.
   - Copy the resulting **Token ID** (`ot-...`) into `workspaces.tf`'s `local.oauth_token_id`.
3. **TFE_TOKEN workspace variable** on `terraform-infra` itself (Org Settings → API Tokens → create an Org token → set as sensitive env var `TFE_TOKEN` on the workspace) — the workspace's default execution identity has limited permissions and can't reliably create/modify other workspaces or projects without this.
4. **Connect `terraform-infra` to VCS** — do this manually via console first (Settings → Version Control), the same way you would for any workspace, *then* `terraform import` it so code matches reality. Trying to have `apply` create the VCS connection from scratch on a not-yet-connected workspace has been unreliable in practice.

## Local commands

```cmd
terraform login
terraform init
terraform validate
terraform plan
```

Importing a workspace/project that already exists in TFC (don't let `apply` try to create a duplicate):
```cmd
terraform import "tfe_workspace.this[\"<key>\"]" ws-xxxxxxxxxxxxx   # ID: TFC UI → workspace → Settings → General
terraform import "tfe_project.this[\"<key>\"]" prj-xxxxxxxxxxxxx    # ID: from the project's URL in TFC UI
```

## `projects.tf` field reference

```hcl
projects = {
  "default" = {
    id         = "prj-xxxxxxxxxxxxx"   # pre-existing project — set `id`, not `name`
    auto_apply = true                   # controls auto_apply for every workspace assigned to this project
  }
  "platform" = {
    name       = "Platform"             # new project — set `name`, omit `id` — Terraform creates it
    auto_apply = false
  }
}
```
`auto_apply` here is a **default per project** — any workspace can still override it individually (see below).

## `workspaces.tf` field reference

```hcl
repo_workspaces = {
  "repo-name" = {
    name              = "workspace-name"
    project           = "default"          # must match a key in projects.tf's local.projects
    auto_apply        = false               # optional — overrides the project's default for just this workspace
    working_directory = "infra/terraform"   # optional — blank ("") if .tf files live at repo root
  }
}
```

## `teams.tf` / `access.tf` field reference

```hcl
# teams.tf
teams        = { "developers" = {} }
team_members = { "developers" = ["user@example.com"] }

# access.tf
team_project_access = { "developers" = { "platform" = "write" } }   # access: read | write | maintain | admin | custom
```

## Adding things

| Task | Edit |
|---|---|
| New project | `projects.tf` → `local.projects` |
| New team | `teams.tf` → `local.teams` |
| Add user to team | `teams.tf` → `local.team_members` |
| Grant team access to project | `access.tf` → `local.team_project_access` |
| New repo's workspace | `workspaces.tf` → `local.repo_workspaces` |

```cmd
git checkout -b my-change
git add <files>
git commit -m "message"
git push origin my-change
```
Open PR → TFC auto-plans → review → merge → applies per the target workspace's `auto_apply` setting.

## Known gotchas

- **This repo manages its own workspace** (`terraform-infra`) — self-referential. Changes here that affect `terraform-infra` itself (VCS link, auto_apply) apply to the very workspace running the change.
- **"Project not found" on `tfe_workspace` creation** — a newly created workspace needs an explicit `project_id`; don't omit it. Don't rely on looking up "Default Project" by name via `data "tfe_project"` — that lookup has failed even with an exact name match on some orgs. Use the hardcoded ID from the project's TFC UI URL instead.
- **"Repository doesn't exist or isn't accessible"** on `tfe_workspace` apply, for a repo that's public and otherwise identical in setup to one that already works — re-authorize the OAuth grant: GitHub → Settings → Applications → Authorized OAuth Apps → revoke the TFC app → reconnect via TFC's VCS Provider settings → retry.
- **Module `source = "../..."` breaks on remote/CLI-driven runs** — TFC's CLI-driven remote execution uploads only the working directory, not parent paths. Keep resource files flat in this directory.
- **`terraform state mv` needed** whenever a resource's map key or address changes (e.g. renaming an entry in `repo_workspaces`) — otherwise `plan` shows a destroy+recreate of a resource that already exists, which can be dangerous if it's a workspace actively running your own state.
