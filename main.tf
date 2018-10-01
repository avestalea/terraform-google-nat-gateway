/*
 * Copyright 2017 Google Inc.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *   http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

data "template_file" "nat-startup-script" {
  template = "${file("${format("%s/config/startup.sh", path.module)}")}"

  vars {
    squid_enabled = "${var.squid_enabled}"
    squid_config  = "${var.squid_config}"
    module_path   = "${path.module}"
  }
}

data "google_compute_network" "network" {
  name    = "${var.network}"
  project = "${var.network_project == "" ? var.project : var.network_project}"
}

module "nat-gateway" {
  source            = "github.com/avestalea/terraform-google-managed-instance-group"
  project           = "${var.project}"
  region            = "${var.region}"
  zone              = "${var.zone == "" ? lookup(var.region_params["${var.region}"], "zone") : var.zone}"
  network           = "${var.network}"
  subnetwork        = "${var.subnetwork}"
  target_tags       = ["nat-${var.zone == "" ? lookup(var.region_params["${var.region}"], "zone") : var.zone}"]
  machine_type      = "${var.machine_type}"
  name              = "nat-gateway-${var.zone == "" ? lookup(var.region_params["${var.region}"], "zone") : var.zone}"
  compute_image     = "projects/debian-cloud/global/images/family/debian-9"
  size              = 1
  network_ip        = "${var.ip}"
  can_ip_forward    = "true"
  service_port      = "80"
  service_port_name = "http"
  startup_script    = "${data.template_file.nat-startup-script.rendered}"

  // Race condition when creating route with instance in managed instance group. Wait 30 seconds for the instance to be created by the manager.
  local_cmd_create = "sleep 30"

  access_config = [{
//    nat_ip = "${google_compute_address.default.address}"
    nat_ip = "${google_compute_address.default.*.address}"
  }]

//  access_config = [
//    {
//      nat_ip = "${element(concat(google_compute_address.default.*.address, data.google_compute_address.default.*.address, list("")), 0)}"
//      nat_ip = "${google_compute_address.default.*.address}"
//    },
//  ]
}

resource "google_compute_route" "nat-gateway" {
  name                   = "nat-${var.zone == "" ? lookup(var.region_params["${var.region}"], "zone") : var.zone}"
  dest_range             = "0.0.0.0/0"
  network                = "${data.google_compute_network.network.self_link}"
  next_hop_instance      = "${element(split("/", element(module.nat-gateway.instances[0], 0)), 10)}"
  next_hop_instance_zone = "${var.zone == "" ? lookup(var.region_params["${var.region}"], "zone") : var.zone}"
  tags                   = ["${compact(concat(list("nat-${var.region}"), var.tags))}"]
  priority               = "${var.route_priority}"
}

resource "google_compute_firewall" "nat-gateway" {
  name    = "nat-${var.zone == "" ? lookup(var.region_params["${var.region}"], "zone") : var.zone}"
  network = "${var.network}"

  allow {
    protocol = "all"
  }

  source_tags = ["${compact(concat(list("nat-${var.zone == "" ? lookup(var.region_params["${var.region}"], "zone") : var.zone}"), var.tags))}"]
  target_tags = ["${compact(concat(list("nat-${var.zone == "" ? lookup(var.region_params["${var.region}"], "zone") : var.zone}"), var.tags))}"]
}

resource "google_compute_address" "default" {
  name   = "nat-${var.zone == "" ? lookup(var.region_params["${var.region}"], "zone") : var.zone}"
  region = "${var.region}"
}
