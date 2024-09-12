#
#  Google Storage definitions
#

resource "google_storage_bucket" "distribution" {
  project       = var.project
  name          = "myappname-${var.account_name}-distribution"
  location      = var.region
  storage_class = "STANDARD"
  force_destroy = true

  uniform_bucket_level_access = true
}

variable "folders_name_set" {
  description = "The folder list name"
  type        = list(string)
  default     = [  "dist/myappname/empty",  "versions/myappname/empty"]
}

resource "google_storage_bucket_object" "content_folder" {
  for_each      = toset(var.folders_name_set)
  name          = each.value
  content       = "Not really a directory, but it's empty."
  bucket        = "${google_storage_bucket.distribution.name}"
}

