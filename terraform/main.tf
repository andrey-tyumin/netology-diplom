terraform {
	required_providers {
	  yandex = {
	    source = "terraform-registry.storage.yandexcloud.net/yandex-cloud/yandex"
		   }
      local = {
	    source = "terraform-registry.storage.yandexcloud.net/hashicorp/local"
      }
		}
  backend "s3" {
    endpoint   = "storage.yandexcloud.net"
    bucket     = "diplom-bucket"
    region     = "ru-central1"
    key        = "terraform/terraform.tfstate"
    access_key = "here_you_need_access_key"
    secret_key = "here_you_need_secret_key"

    skip_region_validation      = true
    skip_credentials_validation = true
  }  
}

provider "yandex" {
#	token = "${var.token}"
  service_account_key_file = "./sa-diplom-key.json"
	folder_id = "${var.folderid}"
  zone = "${var.zoneid}"
	cloud_id = "${var.cloudid}"
}

locals {
  instance_image_map = {
    prod = "fd8ciuqfa001h8s9sa7i"
    stage = "fd8fs0qmhjiiqc4t5h93"
  }
  instance_count_map = {
    prod = 4
    stage = 2
  }
  template_file = {
    prod = "inventory_prod.tmpl"
    stage = "inventory_stage.tmpl"
  }
}

#Create network
resource "yandex_vpc_network" "diplom" {
	name = "diplom vpc ${terraform.workspace}"
}
#Create public subnet in ru-central1-a zone
resource "yandex_vpc_subnet" "subnet-a" {
    name = "public subnet-a ${terraform.workspace}"
	v4_cidr_blocks = ["192.168.10.0/24"]
	zone = "ru-central1-a"
	network_id = "${yandex_vpc_network.diplom.id}"
}
#Create public subnet in ru-central1-b zone
resource "yandex_vpc_subnet" "subnet-b" {
    name = "public subnet-b ${terraform.workspace}"
	v4_cidr_blocks = ["192.168.20.0/24"]
	zone = "ru-central1-b"
	network_id = "${yandex_vpc_network.diplom.id}"
  depends_on = [yandex_vpc_subnet.subnet-a]
}
#Create public subnet in ru-central1-c zone
resource "yandex_vpc_subnet" "subnet-c" {
    name = "public subnet-c ${terraform.workspace}"
	v4_cidr_blocks = ["192.168.30.0/24"]
	zone = "ru-central1-c"
	network_id = "${yandex_vpc_network.diplom.id}"
  depends_on = [yandex_vpc_subnet.subnet-b]
}

#Create control plane
resource yandex_compute_instance "cp"{
name = "cp-${terraform.workspace}"
resources {
  cores = 4
  memory = 4
  }

boot_disk {
  initialize_params {
    image_id = local.instance_image_map[terraform.workspace]
    size = "50"
    }
  }

metadata = {
  user-data = "${file("./metadata.txt")}"
  }

network_interface {
  subnet_id = "${yandex_vpc_subnet.subnet-a.id}"
  nat = true
  }
  depends_on = [yandex_vpc_subnet.subnet-c]
}

#Create worknodes
resource yandex_compute_instance "worknode"{

count = local.instance_count_map[terraform.workspace]
name = "node-${count.index}-${terraform.workspace}"
zone = (count.index == 0 ? "${yandex_vpc_subnet.subnet-a.zone}" : 
       (count.index == 1 ? "${yandex_vpc_subnet.subnet-b.zone}" : "${yandex_vpc_subnet.subnet-c.zone}"))
resources {
  cores=2
  memory=2
  }

boot_disk {
  initialize_params {
    image_id = local.instance_image_map[terraform.workspace]
    size=80
    }
  }

metadata = {
  user-data = "${file("./metadata.txt")}"
  }

network_interface {
  subnet_id = (count.index == 0 ? "${yandex_vpc_subnet.subnet-a.id}" : 
              (count.index == 1 ? "${yandex_vpc_subnet.subnet-b.id}" : "${yandex_vpc_subnet.subnet-c.id}"))
  nat = true
  }
depends_on=[yandex_compute_instance.cp]
 }

#Create instance for ingress
resource yandex_compute_instance "ingress" {
	name = "ingress-${terraform.workspace}"
	resources {
	cores=2
	memory=2
	}

	boot_disk {
	initialize_params {
	image_id = local.instance_image_map[terraform.workspace]
  size=50
		}
	}

	metadata={
	user-data="${file("./metadata.txt")}"
	}

	network_interface {
	subnet_id="${yandex_vpc_subnet.subnet-a.id}"
	nat=true
	}
}

#Create instance for gitlab
resource yandex_compute_instance "gitlab" {
	name = "gitlab"
	resources {
	cores=2
	memory=4
	}

	boot_disk {
	initialize_params {
	image_id = "fd8ntvncmp9m3avtvgkf"
  size=30
		}
	}

	metadata={
	user-data="${file("./metadata.txt")}"
	}

	network_interface {
	subnet_id="${yandex_vpc_subnet.subnet-a.id}"
	nat=true
	}
  allow_stopping_for_update = true
}

#Create inventory for stage
resource "local_file" "Create_inventory_for_stage" {
count = terraform.workspace == "stage" ? 1:0
content = templatefile("inventory_stage.tmpl",
{
cp = yandex_compute_instance.cp.network_interface.0.nat_ip_address
cp_internal_address = yandex_compute_instance.cp.network_interface.0.ip_address
node-0-stage = yandex_compute_instance.worknode[0].network_interface.0.nat_ip_address
node-0-stage_internal_address = yandex_compute_instance.worknode[0].network_interface.0.ip_address
node-1-stage = yandex_compute_instance.worknode[1].network_interface.0.nat_ip_address
node-1-stage_internal_address = yandex_compute_instance.worknode[1].network_interface.0.ip_address
ingress-stage = yandex_compute_instance.ingress.network_interface.0.nat_ip_address
ingress-stage_internal_address = yandex_compute_instance.ingress.network_interface.0.ip_address
}
)
filename = "./inventory-stage.ini"
}

#Create inventory for prod
resource "local_file" "Create_inventory_for_prod" {
count = terraform.workspace == "prod" ? 1:0
content = templatefile("inventory_prod.tmpl",
{
cp = yandex_compute_instance.cp.network_interface.0.nat_ip_address
cp_internal_address = yandex_compute_instance.cp.network_interface.0.ip_address
node-0-prod = yandex_compute_instance.worknode[0].network_interface.0.nat_ip_address
node-0-prod_internal_address = yandex_compute_instance.worknode[0].network_interface.0.ip_address
node-1-prod = yandex_compute_instance.worknode[1].network_interface.0.nat_ip_address
node-1-prod_internal_address = yandex_compute_instance.worknode[1].network_interface.0.ip_address
node-2-prod = yandex_compute_instance.worknode[2].network_interface.0.nat_ip_address
node-2-prod_internal_address = yandex_compute_instance.worknode[2].network_interface.0.ip_address
node-3-prod = yandex_compute_instance.worknode[3].network_interface.0.nat_ip_address
node-3-prod_internal_address = yandex_compute_instance.worknode[3].network_interface.0.ip_address
ingress-prod = yandex_compute_instance.ingress.network_interface.0.nat_ip_address
ingress-prod_internal_address = yandex_compute_instance.ingress.network_interface.0.ip_address
}
)
filename = "./inventory-prod.ini"
}