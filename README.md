Overview
========

This document describes how to modify a [TripleO Queens OpenStack with Ceph Luminous Deployment](https://docs.openstack.org/tripleo-docs/latest/install/advanced_deployment/ceph_config.html) to include [Ceph Metrics](https://github.com/ceph/cephmetrics/wiki).

TripleO's [composable networks](https://docs.openstack.org/tripleo-docs/latest/install/advanced_deployment/custom_networks.html) feature is used to deploy an overcloud with a dedicated CephMetrics network which is used by all Ceph nodes to share metrics data. Firewall ports are [opened](tht/cephmetrics.yaml) on all hosts with Ceph services for the [Prometheus exporter](http://docs.ceph.com/docs/mimic/mgr/prometheus). After the overcloud is deployed the overcloud admin configures the CephMetrics network as a [provider network](https://docs.openstack.org/newton/install-guide-rdo/launch-instance-networks-provider.html) and creates a separate [cephmetrics project](https://docs.openstack.org/keystone/queens/admin/cli-manage-projects-users-and-roles.html) with access to the provider network. Heat templates are [provided](instance) to launch an instance within the cephmetrics project and tools are provided to install ceph metrics with Ansible on the instance. An example of accessing the ceph metrics GUI via a floating IP is provided though it is at the discretion of the deployer how the ceph metrics GUI is accessed.

![CephMetrics Logical Network Diagram](https://www.dropbox.com/s/qprrraef9hvvhzy/CephMetricsNetworkDiagram.png?raw=1)

Deploying the Overcloud
=======================

There is a TripleO Heat Templates directory, [tht](tht), which contains the following templates.

- [cephmetrics.yaml](tht/cephmetrics.yaml) opens the firewall ports
- [network_data_ceph_metrics.yaml](tht/network_data_ceph_metrics.yaml) replaces the standard /usr/share/openstack-tripleo-heat-templates/network_data.yaml by adding a new CephMetrics network
- [roles_data_ceph_metrics.yaml](tht/roles_data_ceph_metrics.yaml) replaces the standard /usr/share/openstack-tripleo-heat-templates/roles_data.yaml by redefining the Controller and CephStorage roles to include the CephMetrics network

As the stack user on the undercloud, save a copy of the [tht](tht) directory in /home/stack/tht with the above contents. As the same user, create a ~/templates directory and render ~/templates/environments/network-environment.yaml with the following:
```
cp -r /usr/share/openstack-tripleo-heat-templates ~/templates
python ~/templates/tools/process-templates.py -n ~/tht/network_data_ceph_metrics.yaml -r ~/tht/roles_data_ceph_metrics.yaml -p ~/templates
```
Be sure to review the rendered ~/templates/environments/network-environment.yaml before deploying to ensure that the ControlPlaneDefaultRoute and DnsServers match the environment of your undercloud. E.g. if your undercloud is using 192.168.24.1 for the default route but the rendered ControlPlaneDefaultRoute isn't, then you may need to modify it (`sed -i s/192.168.24.254/192.168.24.1/g ~/templates/environments/network-environment.yaml`).

Deploy the [overcloud with ceph as usual](https://docs.openstack.org/tripleo-docs/latest/install/advanced_deployment/ceph_config.html) but include the templates above; [overcloud-deploy.sh](overcloud-deploy.sh) is provided as an example.

Configuring the Overcloud to Host Ceph Metrics
==============================================

In the first phase of this guide we will create a project in the
overcloud called cephmetrics. Within the cephmetrics project we will
create the following OpenStack resources:

- Neutron networks which can access the Ceph servers
- A Cinder volume to persist an instance based on a RHEL cloud image
- An instance based on the Cinder volume to host the dashboard

The above may be completed with the following steps:

1. Access the undercloud
2. Ensure that ~/overcloudrc is present
3. If you haven't already, create an image in your *overcloud* using a RHEL KVM image such as the [RHEL 7.5 image found here](https://access.redhat.com/downloads/content/69/ver=/rhel---7/7.5/x86_64/product-software) using a command similar to `openstack image create "rhel_7" --file ./rhel_7.img --disk-format qcow2 --container-format bare --public`
4. Inside the [`instance` directory](instance), run `cp example.conf cephmetrics.conf`
5. Edit cephmetrics.conf and make any changes you require, such as the name of the image
6. Run `./create.sh cephmetrics.conf`
7. After waiting for the instance to boot completely, SSH into it and register it using subscription-manager
8. On the instance, enable the necessary repos with `subscription-manager repos --enable=rhel-7-server-rhceph-3-tools-rpms --enable=rhel-7-server-extras-rpms --enable=rhel-7
-server-optional-rpms --enable=rhel-7-server-rpms`

Installing Cephmetrics
======================

In the second phase of this guide we will execute the cephmetrics
Ansible playbook to install Cephmetrics in the instance created in the
previous phase.

Building the Inventory
----------------------
1. Access the undercloud
2. `tripleo-ansible-inventory --static-yaml-inventory ooo-inventory.yaml`
3. `./convert_inventory.py -a instance/cephmetrics.conf ooo-inventory.yaml > inventory.yaml`
4. If you need to override any Ansible variables for the deploy, you may edit inventory.yaml and insert them into the 'vars' object inside the 'all' group.

Deploying
---------
1. `cd /path/to/cephmetrics/ansible`
2. `ansible-playbook -v -i /path/to/inventory/ playbook.yml`

Uninstalling cephmetrics
========================
1. `cd /path/to/cephmetrics/ansible`
2. `ansible-playbook -v -i /path/to/inventory purge.yml`
3. Using the instance configuration you created previously, run [`delete.sh`](instance/delete.sh)
4. Delete the cephmetrics project from the overcloud  as described in the [documentation](https://docs.openstack.org/horizon/latest/admin/manage-projects-and-users).
