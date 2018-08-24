#!/bin/bash

set -ux


### --start_docs
## Deploying the overcloud
## =======================

## Prepare Your Environment
## ------------------------

## * Source in the undercloud credentials.
## ::

source /home/stack/stackrc

### --stop_docs
# Wait until there are hypervisors available.
while true; do
    count=$(openstack hypervisor stats show -c count -f value)
    if [ $count -gt 0 ]; then
        break
    fi
done

### --start_docs


## * Deploy the overcloud!
## ::
openstack overcloud deploy \
    --templates ~/templates \
    -n ~/tht/network_data_ceph_metrics.yaml \
    -r ~/tht/roles_data_ceph_metrics.yaml \
    --libvirt-type qemu \
    --control-flavor oooq_control \
    --compute-flavor oooq_compute \
    --ceph-storage-flavor oooq_ceph \
    --timeout 90 \
    --compute-scale 1 --control-scale 3 --ceph-storage-scale 3 \
    --ntp-server clock.redhat.com \
    -e /home/stack/cloud-names.yaml \
    -e ~/templates/environments/docker.yaml \
    -e ~/templates/environments/docker-ha.yaml \
    -e /home/stack/containers-default-parameters.yaml \
    -e ~/templates/environments/low-memory-usage.yaml \
    -e ~/templates/environments/disable-telemetry.yaml \
    -e ~/templates/environments/ceph-ansible/ceph-ansible.yaml \
    -e ~/templates/environments/network-isolation.yaml \
    -e ~/templates/environments/net-single-nic-with-vlans.yaml \
    -e ~/templates/environments/network-environment.yaml \
    -e ~/tht/cephmetrics.yaml \
    ${DEPLOY_ENV_YAML:+-e $DEPLOY_ENV_YAML} "$@" && status_code=0 || status_code=$?

### --stop_docs

# Check if the deployment has started. If not, exit gracefully. If yes, check for errors.
if ! openstack stack list | grep -q overcloud; then
    echo "overcloud deployment not started. Check the deploy configurations"
    exit 1

    # We don't always get a useful error code from the openstack deploy command,
    # so check `openstack stack list` for a CREATE_COMPLETE or an UPDATE_COMPLETE
    # status.
elif ! openstack stack list | grep -Eq '(CREATE|UPDATE)_COMPLETE'; then
        # get the failures list
    openstack stack failures list overcloud --long > /home/stack/failed_deployment_list.log || true
    # NOTE(emilien) "openstack overcloud failures" was introduced in Rocky
    openstack overcloud failures >> /home/stack/failed_deployment_list.log || true
    
    # get any puppet related errors
    for failed in $(openstack stack resource list \
        --nested-depth 5 overcloud | grep FAILED |
        grep 'StructuredDeployment ' | cut -d '|' -f3)
    do
    echo "openstack software deployment show output for deployment: $failed" >> /home/stack/failed_deployments.log
    echo "######################################################" >> /home/stack/failed_deployments.log
    openstack software deployment show $failed >> /home/stack/failed_deployments.log
    echo "######################################################" >> /home/stack/failed_deployments.log
    echo "puppet standard error for deployment: $failed" >> /home/stack/failed_deployments.log
    echo "######################################################" >> /home/stack/failed_deployments.log
    # the sed part removes color codes from the text
    openstack software deployment show $failed -f json |
        jq -r .output_values.deploy_stderr |
        sed -r "s:\x1B\[[0-9;]*[mK]::g" >> /home/stack/failed_deployments.log
    echo "######################################################" >> /home/stack/failed_deployments.log
    # We need to exit with 1 because of the above || true
    done
    exit 1
fi
exit $status_code
