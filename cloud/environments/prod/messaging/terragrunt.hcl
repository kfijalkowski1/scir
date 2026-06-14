include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

terraform {
  source = "../../../modules/messaging"
}

inputs = {
  telemetry_topic_filter = include.root.locals.telemetry_topic_filter
  control_topic          = include.root.locals.control_topic
}
