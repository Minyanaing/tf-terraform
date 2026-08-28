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
