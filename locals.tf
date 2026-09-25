# Shared naming convention and mandatory tags.
#
# Every resource in this stack is named from the same prefix so it is obvious
# at a glance in the AWS console which project and environment it belongs to:
#   {project}-{environment}[-{component}]
#
# MandatoryTags are applied to every resource through the provider's
# default_tags block, so cost allocation and ownership never depend on a
# module remembering to tag something.
locals {
  name_prefix = "${var.project_name}-${var.environment}"

  mandatory_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}
