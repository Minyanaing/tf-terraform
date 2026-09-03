locals {
  # Teams and their org-level permissions.
  teams = {
    # "developers"      = { visibility = "organization" }
    # "local-plan-only" = { visibility = "organization" }  # example: scope a team to plan-only, see workspaces.tf
  }

  # team_name => list of user emails to add as members.
  team_members = {
    # "developers" = ["someone@example.com"]
  }
}

resource "tfe_team" "this" {
  for_each = local.teams

  name         = each.key
  organization = data.tfe_organization.this.name

  organization_access {
    manage_projects = false
    manage_workspaces = false
  }
}

resource "tfe_team_organization_member" "this" {
  for_each = merge([
    for team, emails in local.team_members : {
      for email in emails : "${team}-${email}" => {
        team  = team
        email = email
      }
    }
  ]...)

  team_id                  = tfe_team.this[each.value.team].id
  organization_membership_id = tfe_organization_membership.this[each.value.email].id
}

resource "tfe_organization_membership" "this" {
  for_each = toset(flatten(values(local.team_members)))

  organization = data.tfe_organization.this.name
  email        = each.value
}
