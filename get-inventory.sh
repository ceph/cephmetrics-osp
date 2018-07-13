#!/bin/bash
set -ex

TRIPLEO_INVENTORY=tripleo-inventory.yaml

tripleo-ansible-inventory --static-yaml-inventory $TRIPLEO_INVENTORY
ansible --ssh-extra-args "-o StrictHostKeyChecking=no" -i $TRIPLEO_INVENTORY all -m ping
./convert_inventory.py $TRIPLEO_INVENTORY | tee inventory
