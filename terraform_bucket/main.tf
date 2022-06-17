terraform {
	required_providers {
	  yandex = {
	    source = "terraform-registry.storage.yandexcloud.net/yandex-cloud/yandex"
		   }
    null = {
	    source = "terraform-registry.storage.yandexcloud.net/hashicorp/null"			}   
		}
  }

provider "yandex" {
	token = "${var.token}"
	folder_id = "${var.folderid}"
    zone = "${var.zoneid}"
	cloud_id = "${var.cloudid}"
}

#Create service account
resource "yandex_iam_service_account" "sa-diplom" {
  folder_id = "${var.folderid}"
  name      = "sa-diplom"
}

#Add persmission to service account (for create bucket)
resource "yandex_resourcemanager_folder_iam_member" "sa-editor" {
  folder_id = "${var.folderid}"
  role      = "storage.editor"
  member    = "serviceAccount:${yandex_iam_service_account.sa-diplom.id}"
}

#Add persmission to service account (for create instance group)
resource "yandex_resourcemanager_folder_iam_member" "sa-ig-editor" {
  folder_id = "${var.folderid}"
  role = "editor"
  member = "serviceAccount:${yandex_iam_service_account.sa-diplom.id}"
}

#Add persmission to service account (for create instance group)
resource "yandex_resourcemanager_folder_iam_member" "sa-ig-compute-admin" {
  folder_id = "${var.folderid}"
  role = "compute.admin"
  member = "serviceAccount:${yandex_iam_service_account.sa-diplom.id}"
}

#Create service account authorized keys
resource "yandex_iam_service_account_key" "sa-diplom-auth-key" {
  service_account_id = "${yandex_iam_service_account.sa-diplom.id}"
  description        = "key for service account sa-diplom"
  key_algorithm      = "RSA_4096"
}

#Create Static Access Keys
resource "yandex_iam_service_account_static_access_key" "sa-diplom-static-key" {
  service_account_id = "${yandex_iam_service_account.sa-diplom.id}"
  description = "static access key for sa-diplom"
}

#Create kms key for encrypt\decrypt bucket
resource "yandex_kms_symmetric_key" "kms-key" {
  name              = "kms-key"
  description       = "key for encrypt/decrypt bucket"
  default_algorithm = "AES_128"
  rotation_period   = "120h"
}

#create bucket
resource "yandex_storage_bucket" "diplom-bucket" {
  access_key = "${yandex_iam_service_account_static_access_key.sa-diplom-static-key.access_key}"
  secret_key = "${yandex_iam_service_account_static_access_key.sa-diplom-static-key.secret_key}"
  bucket = "diplom-bucket"
  acl    = "public-read"
  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        kms_master_key_id = yandex_kms_symmetric_key.kms-key.id
        sse_algorithm     = "aws:kms"
      }
    }
  }
  depends_on = [yandex_resourcemanager_folder_iam_member.sa-editor]
}

resource "null_resource" "get-auth-key-json" {
	provisioner "local-exec" {
	command = "yc iam key create --service-account-name sa-diplom -o sa-diplom-key.json"
	}
  depends_on = [yandex_iam_service_account.sa-diplom]
}

#Create registry
resource "yandex_container_registry" "diplom-registry" {
  name      = "diplom-registry"
  folder_id = "${var.folderid}"

  labels = {
    label1 = "diplom-registry"
  }
}

#Allow public pulling
resource "yandex_container_registry_iam_binding" "puller" {
  registry_id = yandex_container_registry.diplom-registry.id
  role        = "container-registry.images.puller"

  members = [
    "system:allUsers",
  ]
}

#Get data for registry
data "yandex_container_registry" "diplom-registry" {
  registry_id = "${yandex_container_registry.diplom-registry.id}"
}