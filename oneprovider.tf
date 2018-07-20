resource "openstack_networking_floatingip_v2" "oneprovider" {
  depends_on = ["openstack_compute_instance_v2.oneprovider"]
  port_id  = "${openstack_networking_port_v2.oneprovider-port.id}"
  # count = "${var.provider_count}"
  pool  = "${var.external_network}"
}


resource "openstack_compute_instance_v2" "oneprovider" {
  depends_on = ["openstack_networking_router_interface_v2.interface"]
  name            = "${var.project}-op"
  # image_name      = "${var.image_name}"
  flavor_name     = "${var.oneprovider_flavor_name}"
  key_pair        = "${openstack_compute_keypair_v2.otc.name}"
  availability_zone = "${var.otc_availability_zone}"

  network {
    port = "${openstack_networking_port_v2.oneprovider-port.id}"
    uuid = "${openstack_networking_network_v2.network.id}"
    access_network = true
  }
    block_device {
    uuid                  = "${openstack_blockstorage_volume_v2.oneprovider-image-vol.id}"
    source_type           = "volume"
    boot_index            = 0
    destination_type      = "volume"
    delete_on_termination = true
  }
}

resource "openstack_blockstorage_volume_v2" "oneprovider-image-vol" {
  name = "${var.project}-op-vol"
  size = "${var.image_vol_size}"
  volume_type = "${var.image_vol_type}"
  availability_zone = "${var.otc_availability_zone}"
  image_id = "${var.image_uuid}"
}

resource "openstack_networking_port_v2" "oneprovider-port" {
  network_id         = "${openstack_networking_network_v2.network.id}"
  security_group_ids = [
    "${openstack_compute_secgroup_v2.oneprovider.id}",
  ]
  admin_state_up     = "true"
  fixed_ip           = {
    subnet_id        = "${openstack_networking_subnet_v2.subnet.id}"
  }
}

resource "null_resource" "prepare-bastion" { # oneprivider will act as bastion
  connection {
    host = "${openstack_networking_floatingip_v2.oneprovider.address}"
    user     = "${var.ssh_user_name}"
    agent = true
    timeout = "10m"
  }
  provisioner "local-exec" {
    command = "./local-setup.sh"  # playbooks are tarred by this script
  }
  provisioner "file" {
    source = "playbooks.tgz"
    destination = "playbooks.tgz"
  }
  provisioner "remote-exec" {
    inline = [
      # "sudo yum -y install ansible",
      "sudo yum -y install epel-release",
      "sudo yum -y install ansible",
      "sudo yum -y install python-pip",
      "sudo pip install pexpect",
      "sudo pip install --upgrade jinja2", 
      "tar zxvf playbooks.tgz",
      "ssh-keygen -R localhost",
      "ssh -o StrictHostKeyChecking=no localhost date",
      "ansible-playbook -i \"localhost,\" playbooks/bastion.yml",
      "ansible-playbook -i \"localhost,\" playbooks/op-prereq.yml -e opname=${openstack_compute_instance_v2.oneprovider.name} -e domain=${var.opdomain}",
    ]
  }
}

resource "null_resource" "onedatify" { 
  depends_on = ["null_resource.provision-ceph","null_resource.prepare-bastion"]
  connection {
    host = "${openstack_networking_floatingip_v2.oneprovider.address}"
    user     = "${var.ssh_user_name}"
    agent = true
    timeout = "10m"
  }
  provisioner "remote-exec" {
    inline = [  
      "ansible-playbook playbooks/oneprovider.yml -i \"localhost,\" --extra-vars \"domain=${var.opdomain} support_token=${var.support_token} storage_type=${var.storage_type} oppass=${var.oppass} support_size=${var.support_size}\"",
    ]
  }
}
