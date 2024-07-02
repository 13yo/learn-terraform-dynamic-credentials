provider "google" {
  project = var.gcp_project_id
}

provider "google-beta" {
  project = var.gcp_project_id
}

resource "google_compute_network" "hashi-test" {
  name                    = var.network_name
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "default" {
  name                     = var.network_name
  ip_cidr_range            = "10.0.0.0/16"
  network                  = google_compute_network.hashi-test.self_link
  region                   = var.region
  private_ip_google_access = true
}

resource "google_compute_router" "default" {
  name    = "acme-router"
  network = google_compute_network.hashi-test.self_link
  region  = var.region
}

module "cloud-nat" {
  source     = "terraform-google-modules/cloud-nat/google"
  version    = "~> 5.2.0"
  router     = google_compute_router.default.name
  project_id = var.gcp_project_id
  region     = var.region
  name       = "acme-cloud-nat"
}

module "mig_template" {
  source  = "terraform-google-modules/vm/google//modules/instance_template"
  version = "~> 11.1.0"

  source_image_project = "debian-cloud"
  source_image_family  = "debian-12"
  source_image         = "debian-12-bookworm-v20240701"

  network    = google_compute_network.hashi-test.self_link
  subnetwork = google_compute_subnetwork.default.self_link
  service_account = {
    email  = ""
    scopes = ["cloud-platform"]
  }
  name_prefix    = var.network_name
  startup_script = <<-EOF1
      #! /bin/bash
      set -euo pipefail

      export DEBIAN_FRONTEND=noninteractive
      apt-get update
      apt-get install -y nginx-light jq

      NAME=$(curl -H "Metadata-Flavor: Google" "http://metadata.google.internal/computeMetadata/v1/instance/hostname")
      
      cat <<EOF > /var/www/html/index.html
      <html><body><div>Hello, this is $NAME!</div></body></html>
      EOF
    EOF1
  tags = [
    var.network_name,
    module.cloud-nat.router_name
  ]
}

module "mig" {
  source            = "terraform-google-modules/vm/google//modules/mig"
  version           = "~> 11.1.0"
  instance_template = module.mig_template.self_link
  region            = var.region
  hostname          = var.network_name
  target_size       = 2
  named_ports = [{
    name = "http",
    port = 80
  }]
}

module "gce-lb-http" {
  source            = "terraform-google-modules/lb-http/google"
  version           = "~> 11.0.0"
  name              = "acme-mig-http-lb"
  project           = var.gcp_project_id
  target_tags       = [var.network_name]
  firewall_networks = [google_compute_network.hashi-test.name]


  backends = {
    default = {
      protocol    = "HTTP"
      port        = 80
      port_name   = "http"
      timeout_sec = 10
      enable_cdn  = false

      health_check = {
        request_path = "/"
        port         = 80
      }

      log_config = {
        enable = false
      }

      groups = [
        {
          group = module.mig.instance_group
        }
      ]

      iap_config = {
        enable = false
      }
    }
  }
}