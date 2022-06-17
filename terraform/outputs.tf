
output "cp_external_ip" {
 value = "${yandex_compute_instance.cp.network_interface.0.nat_ip_address}"
}
output "instance_external_ip" {
 value = "${yandex_compute_instance.worknode[*].network_interface.0.nat_ip_address}"
}
output "ingress_external_ip" {
    value = "${yandex_compute_instance.ingress.network_interface.0.nat_ip_address}"
}
output "gitlab_external_ip" {
    value = "${yandex_compute_instance.gitlab.network_interface.0.nat_ip_address}"
}