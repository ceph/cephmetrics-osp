Assumptions
===========
A working tripleo cluster with ceph

Installing Cephmetrics
======================
First, we will create an instance in the overcloud to use as the dashboard host. Then, we will execute the cephmetrics Ansible playbook to complete the installation.


Creating the Instance
---------------------
1. Access the undercloud
2. Ensure that ~/overcloudrc is present
3. TODO explain creating conf file and running create.sh


Building the Inventory
----------------------
1. Run get-inventory.sh
2. Rename inventory


Deploying
---------
1. cd /path/to/cephmetrics/ansible
2. ansible-playbook -v -i /path/to/inventory/ playbook.yml


Uninstalling cephmetrics
========================
1. cd /path/to/cephmetrics/ansible
2. ansible-playbook -v -i /path/to/inventory purge.yml
3. Using the instance configuration you created previously, run destroy.sh
