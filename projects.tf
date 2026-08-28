locals {
  # New TFC projects beyond "Default Project" go here.
  projects = {
    # "platform" = { name = "Platform" }
  }
}

resource "tfe_project" "this" {
  for_each = local.projects

  name         = each.value.name
  organization = data.tfe_organization.this.name
}
