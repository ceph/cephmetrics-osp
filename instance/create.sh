#!/usr/bin/env bash
# https://docs.openstack.org/networking-ovn/latest/install/tripleo.html
if [ -z "$1" ];
then
    echo "Usage: $0 conf_file" >&2
    exit 1
fi
set -ex

source ~/overcloudrc
source "./$1"


# curl http://download.cirros-cloud.net/0.4.0/cirros-0.4.0-x86_64-disk.img \
#  > cirros-0.4.0-x86_64-disk.img
# openstack image create "$IMAGE_NAME" --file cirros-0.4.0-x86_64-disk.img   \
#                --disk-format qcow2 --container-format bare --public

openstack network create $PROVIDER_NET_NAME --provider-physical-network datacentre \
                                            --provider-network-type vlan \
                                            --provider-segment $PROVIDER_SEGMENT \
                                            --share --no-dhcp
openstack subnet create $PROVIDER_SUBNET_NAME --network $PROVIDER_NET_NAME \
                        --subnet-range $PROVIDER_NET_CIDR \
                        --allocation-pool $PROVIDER_NET_ALLOCATION_POOL
openstack network create $PUB_NET_NAME --provider-physical-network datacentre \
                                --provider-network-type vlan \
                                --provider-segment 10 \
                                --external --share
openstack subnet create --network $PUB_NET_NAME $PUB_SUBNET_NAME --subnet-range 10.0.0.0/24 \
                         --allocation-pool start=10.0.0.20,end=10.0.0.250 \
                         --dns-nameserver $DNS_IP --gateway 10.0.0.1 \
                         --no-dhcp
openstack network create $PRIV_NET_NAME
openstack subnet create --network $PRIV_NET_NAME $PRIV_SUBNET_NAME \
                        --dns-nameserver $DNS_IP \
                        --subnet-range 192.168.99.0/24
openstack router create $ROUTER_NAME

openstack router set $ROUTER_NAME --external-gateway $PUB_NET_NAME
openstack router add subnet $ROUTER_NAME $PRIV_NET_NAME

openstack security group create $SEC_GROUP_NAME
# Open the SSH port
openstack security group rule create --ingress --protocol tcp \
                                     --dst-port 22 $SEC_GROUP_NAME
# Open Grafana's port
openstack security group rule create --ingress --protocol tcp \
                                     --dst-port 3000 $SEC_GROUP_NAME
# Open Prometheus' port
openstack security group rule create --ingress --protocol tcp \
                                     --dst-port 9090 $SEC_GROUP_NAME
# Open node_exporter's port
openstack security group rule create --ingress --protocol tcp \
                                     --dst-port 9100 $SEC_GROUP_NAME
# Allow pings
openstack security group rule create --ingress --protocol icmp $SEC_GROUP_NAME
openstack security group rule create --egress $SEC_GROUP_NAME

openstack flavor create $FLAVOR_NAME --disk $FLAVOR_DISK --vcpus $FLAVOR_CPUS --ram $FLAVOR_RAM

PRIV_NET_ID=$(openstack network show $PRIV_NET_NAME -c id -f value)
PROVIDER_NET_ID=$(openstack network show $PROVIDER_NET_NAME -c id -f value)

openstack keypair create $KEYPAIR_NAME > ~/$KEYPAIR_NAME.pem
chmod 600 ~/$KEYPAIR_NAME.pem

openstack server create --flavor $FLAVOR_NAME --image $IMAGE_NAME \
                        --key-name $KEYPAIR_NAME \
                        --nic net-id=$PRIV_NET_ID --nic net-id=$PROVIDER_NET_ID \
                        --security-group $SEC_GROUP_NAME \
                        --wait $SERVER_NAME

PRIV_PORT_ID=$(openstack port list --server $SERVER_NAME --network $PRIV_NET_ID -c id -f value)
openstack floating ip create --port $PRIV_PORT_ID --floating-ip-address $FLOAT_IP $PUB_NET_NAME

echo "ssh -i ~/$KEYPAIR_NAME.pem -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null $USER_NAME@$FLOAT_IP"
