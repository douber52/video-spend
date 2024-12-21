variable "environments" {
  description = "Map of environment configurations"
  type = map(object({
    project_id         = string
    region            = string
    zone              = string
    billing_account_id = optional(string)
    instance_count    = number
    machine_type      = string
    target_spend      = number
  }))
}

variable "target_env" {
  description = "Target environment to deploy (e360 or yh)"
  type        = string
  default     = "e360"
}

variable "instance_count" {
  description = "Number of worker instances to create"
  type        = number
  default     = 4
}

variable "machine_type" {
  description = "Machine type for worker instances"
  type        = string
  default     = "n2-standard-32"
}

variable "create_service_account" {
  type        = bool
  description = "Whether to create the service account"
  default     = false
}

variable "create_artifact_registry" {
  type        = bool
  description = "Whether to create the artifact registry"
  default     = false
}