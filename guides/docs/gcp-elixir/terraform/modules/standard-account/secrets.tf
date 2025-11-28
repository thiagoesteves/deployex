# ATTENTION: The values are expected to be set manually by the DASHBOARD
#

resource "google_secret_manager_secret" "deployex_secrets" {
  secret_id = "deployex-myappname-${var.account_name}-secrets"
  replication {
    auto {}
  }
}

resource "google_secret_manager_secret" "myappname_secrets" {
  secret_id = "myappname-${var.account_name}-secrets"
  replication {
    auto {}
  }
}

resource "google_secret_manager_secret" "myappname_otp_tls_ca" {
  secret_id = "myappname-${var.account_name}-otp-tls-ca"
  replication {
    auto {}
  }
}

resource "google_secret_manager_secret" "myappname_otp_tls_key" {
  secret_id = "myappname-${var.account_name}-otp-tls-key"
  replication {
    auto {}
  }
}

resource "google_secret_manager_secret" "myappname_otp_tls_crt" {
  secret_id = "myappname-${var.account_name}-otp-tls-crt"
  replication {
    auto {}
  }
}
