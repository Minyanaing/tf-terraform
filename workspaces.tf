locals {
  oauth_token_id = "ot-88FTKAson2vX6xVm" # GitHub.com (Custom) VCS provider

  # One entry per repo (in tf-github) that needs its own TFC workspace.
  # `project` must match a key in local.projects (projects.tf) — auto_apply
  # is inherited from that project's setting unless overridden here.
  repo_workspaces = {
    "tf-github"    = { name = "terraform-github", project = "default", auto_apply = false }
    "tf-terraform" = { name = "terraform-infra", project = "default", auto_apply = false}
    # "data-platform" = { name = "data-platform", project = "default" }
    # "some-repo"     = { name = "some-workspace", project = "default", auto_apply = false }
  }
}

resource "tfe_workspace" "this" {
  for_each = local.repo_workspaces

  name           = each.value.name
  organization   = data.tfe_organization.this.name
  project_id     = local.project_ids[each.value.project]
  queue_all_runs = true
  auto_apply     = try(each.value.auto_apply, local.project_auto_apply[each.value.project])

  vcs_repo {
    identifier     = "Minyanaing/${each.key}"
    branch         = "main"
    oauth_token_id = local.oauth_token_id
  }
}
