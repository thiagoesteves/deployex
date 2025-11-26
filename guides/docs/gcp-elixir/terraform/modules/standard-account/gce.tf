resource "google_compute_firewall" "firewall" {
  name    = "myfirstapp-${var.account_name}-firewall-externalssh"
  network = "default"
  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
  source_ranges = ["0.0.0.0/0"] # Not So Secure. Limit the Source Range
  target_tags   = ["externalssh"]
}

resource "google_compute_firewall" "webserverrule" {
  name    = "myfirstapp-${var.account_name}-webserver"
  network = "default"
  allow {
    protocol = "tcp"
    ports    = ["80","443"]
  }
  source_ranges = ["0.0.0.0/0"] # Not So Secure. Limit the Source Range
  target_tags   = ["webserver"]
}

resource "google_compute_address" "static" {
  name = "myfirstapp-${var.account_name}-vm-public-address"
  project = var.project
  region = var.region
  depends_on = [ google_compute_firewall.firewall ]
}

data "cloudinit_config" "server_config" {
  gzip          = false
  base64_encode = false
  part {
    content_type = "text/cloud-config"
    content = templatefile("${path.module}/cloud-config.tpl", {
      hostname = "${var.server_dns}"
      deployex_hostname = "${var.deployex_dns}"
      deployex_version = "${var.deployex_version}"
      account_name = "${var.account_name}"
      replicas = "${var.replicas}"
    })
  }
}

resource "google_compute_instance" "dev" {
  name         = "myfirstapp-${var.account_name}-instance"
  machine_type = "${var.machine_type}"
  zone         = "${var.region}-a"
  tags         = ["externalssh","webserver"]
  boot_disk {
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-2004-lts"
    }
  }
  network_interface {
    network = "default"
    access_config {
      nat_ip = google_compute_address.static.address
    }
  }
  # Ensure firewall rule is provisioned before server, so SSH doesn't fail.
  depends_on = [ google_compute_firewall.firewall, google_compute_firewall.webserverrule ]

  metadata = {
    user-data = "${data.cloudinit_config.server_config.rendered}"
  }
}

output "ad_ip_address" {
  value = google_compute_address.static.address
}