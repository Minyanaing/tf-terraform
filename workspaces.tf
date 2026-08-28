locals {
  project_id     = "prj-HBLiyKu4fh1kbwVw" # Default Project
  oauth_token_id = "ot-88FTKAson2vX6xVm"  # GitHub.com (Custom) VCS provider

  # One entry per repo (in tf-github) that needs its own TFC workspace.
  repo_workspaces = {
    "tf-github" = { name = "terraform-github" }
  }
}

resource "tfe_workspace" "this" {
  for_each = local.repo_workspaces

  name           = each.value.name
  organization   = data.tfe_organization.this.name
  project_id     = local.project_id
  queue_all_runs = true
  auto_apply     = true

  vcs_repo {
    identifier     = "Minyanaing/${each.key}"
    branch         = "main"
    oauth_token_id = local.oauth_token_id
  }
}
