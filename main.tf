terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

provider "google" {
  project = local.env.project_id
  region  = local.env.region
  zone    = local.env.zone
}

locals {
  env = var.environments[var.target_env]
  service_account_id = "video-processor-controller"
}

# Create service account if it doesn't exist
resource "google_service_account" "cost_manager" {
  count        = var.create_service_account ? 1 : 0
  account_id   = "cost-manager"
  display_name = "Cost Manager Service Account"
  project      = "e360-lab"

  lifecycle {
    prevent_destroy = true
    ignore_changes = [
      account_id,
      display_name
    ]
  }
}

# IAM bindings for the service account
resource "google_project_iam_member" "cost_manager_roles" {
  for_each = toset([
    "roles/compute.admin",
    "roles/monitoring.metricWriter",
    "roles/iam.serviceAccountUser",
    "roles/resourcemanager.projectIamAdmin",
    "roles/billing.projectManager",
    "roles/logging.logWriter",
    "roles/artifactregistry.reader",
    "roles/run.invoker"
  ])

  project = local.env.project_id
  role    = each.key
  member  = "serviceAccount:video-processor-controller@e360-lab.iam.gserviceaccount.com"
}

# Worker Instances
resource "google_compute_instance" "worker" {
  count        = var.instance_count
  name         = "video-processor-e360-${format("%03d", count.index + 1)}"
  machine_type = var.machine_type
  zone         = local.env.zone

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-11"
      size  = 100  # 100 GB boot disk
    }
  }

  network_interface {
    network = "default"
    access_config {
      // Ephemeral public IP
    }
  }

  service_account {
    email  = "video-processor-controller@e360-lab.iam.gserviceaccount.com"
    scopes = ["cloud-platform"]
  }

  metadata = {
    startup-script = <<-EOF
      #!/bin/bash
      apt-get update
      apt-get install -y python3-pip
      pip3 install google-cloud-compute google-cloud-monitoring
    EOF
  }

  allow_stopping_for_update = true
}

# Create Artifact Registry Repository if it doesn't exist
resource "google_artifact_registry_repository" "cost_manager" {
  count         = var.create_artifact_registry ? 1 : 0
  location      = local.env.region
  repository_id = "cost-manager"
  description   = "Cost Manager container images"
  format        = "DOCKER"
  project       = "e360-lab"

  lifecycle {
    prevent_destroy = true
    ignore_changes = all
  }
}

# Cloud Run Job
resource "google_cloud_run_v2_job" "cost_manager" {
  name     = "cost-manager-${var.target_env}"
  location = local.env.region

  template {
    template {
      containers {
        image = "${local.env.region}-docker.pkg.dev/${local.env.project_id}/cost-manager/app:latest"

        resources {
          limits = {
            cpu    = "1"
            memory = "2Gi"
          }
        }

        env {
          name  = "GCP_PROJECT_ID"
          value = local.env.project_id
        }
        env {
          name  = "TARGET_SPEND"
          value = tostring(local.env.target_spend)
        }
        env {
          name  = "GCP_REGION"
          value = local.env.region
        }
        env {
          name  = "GCP_ZONE"
          value = local.env.zone
        }
        env {
          name  = "CHECK_INTERVAL_MINUTES"
          value = "1"
        }
        env {
          name  = "MAX_RETRIES"
          value = "0"
        }
        env {
          name  = "MAX_INSTANCES"
          value = "1"
        }
      }

      service_account = "video-processor-controller@e360-lab.iam.gserviceaccount.com"
      timeout = "86000s"  # ~24 hours
      max_retries = 0
    }
  }
}

# Create a key for local development
resource "google_service_account_key" "cost_manager" {
  service_account_id = "projects/e360-lab/serviceAccounts/video-processor-controller@e360-lab.iam.gserviceaccount.com"
  private_key_type   = "TYPE_GOOGLE_CREDENTIALS_FILE"
}
