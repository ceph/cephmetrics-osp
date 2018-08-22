#!/usr/bin/env bash
source ~/overcloudrc
set -x

openstack server list
openstack keypair list
openstack flavor list
openstack security group list
openstack floating ip list
openstack router list
openstack network list
openstack subnet list
openstack port list
