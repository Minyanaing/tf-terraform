locals {
  # All TFC projects and whether workspaces under them auto-apply on merge.
  # "default" is pre-existing (not created by Terraform) — set its `id` directly.
  # New projects: set `name`, omit `id` — the resource below creates them.
  projects = {
    "default" = {
      id         = "prj-HBLiyKu4fh1kbwVw" # Default Project
      auto_apply = false
    }
    # "platform" = { name = "Platform", auto_apply = false }
  }
}

resource "tfe_project" "this" {
  for_each = { for key, cfg in local.projects : key => cfg if !contains(keys(cfg), "id") }

  name         = each.value.name
  organization = data.tfe_organization.this.name
}

locals {
  project_ids = {
    for key, cfg in local.projects : key => try(cfg.id, tfe_project.this[key].id)
  }

  project_auto_apply = {
    for key, cfg in local.projects : key => cfg.auto_apply
  }
}
