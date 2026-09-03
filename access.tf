locals {
  # team_name => { project_key => access_level }
  # access_level: "read" | "write" | "maintain" | "admin" | "custom"
  team_project_access = {
    # "developers" = { "platform" = "write" }
  }
}

resource "tfe_team_project_access" "this" {
  for_each = merge([
    for team, projects in local.team_project_access : {
      for project, access in projects : "${team}-${project}" => {
        team    = team
        project = project
        access  = access
      }
    }
  ]...)

  team_id    = tfe_team.this[each.value.team].id
  project_id = tfe_project.this[each.value.project].id
  access     = each.value.access
}

locals {
  # team_name => { workspace_key => access_level }, workspace_key matches
  # a key in workspaces.tf's local.repo_workspaces.
  # access_level: "read" | "plan" | "write" | "admin" | "custom"
  # "plan" can queue plans but is rejected on apply — use for local-only CLI tokens.
  team_workspace_access = {
    # "local-plan-only" = { "tf-terraform" = "plan", "tf-github" = "plan" }
  }
}

resource "tfe_team_access" "this" {
  for_each = merge([
    for team, workspaces in local.team_workspace_access : {
      for workspace, access in workspaces : "${team}-${workspace}" => {
        team      = team
        workspace = workspace
        access    = access
      }
    }
  ]...)

  team_id      = tfe_team.this[each.value.team].id
  workspace_id = tfe_workspace.this[each.value.workspace].id
  access       = each.value.access
}
