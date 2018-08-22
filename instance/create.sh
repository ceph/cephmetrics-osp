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

# Create the provider network and subnet
openstack network create $PROVIDER_NET_NAME --provider-physical-network datacentre \
                                            --provider-network-type vlan \
                                            --provider-segment $PROVIDER_SEGMENT \
                                            --share
openstack subnet create $PROVIDER_SUBNET_NAME --network $PROVIDER_NET_NAME \
                        --subnet-range $PROVIDER_NET_CIDR \
                        --allocation-pool $PROVIDER_NET_ALLOCATION_POOL \
                        --no-dhcp

# Create the public network and subnet
openstack network create $PUB_NET_NAME --provider-physical-network datacentre \
                                --provider-network-type vlan \
                                --provider-segment 10 \
                                --external --share
openstack subnet create --network $PUB_NET_NAME $PUB_SUBNET_NAME --subnet-range 10.0.0.0/24 \
                         --allocation-pool start=10.0.0.20,end=10.0.0.250 \
                         --dns-nameserver $DNS_IP --gateway 10.0.0.1 \
                         --no-dhcp

# Create the private network and subnet
openstack network create $PRIV_NET_NAME
openstack subnet create --network $PRIV_NET_NAME $PRIV_SUBNET_NAME \
                        --dns-nameserver $DNS_IP \
                        --subnet-range 192.168.99.0/24

# Create a router and use it to connect the public and private networks
openstack router create $ROUTER_NAME
openstack router set $ROUTER_NAME --external-gateway $PUB_NET_NAME
openstack router add subnet $ROUTER_NAME $PRIV_NET_NAME

# Create a security group and add several rules
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

# Create the provider port
PROVIDER_NET_ID=$(openstack network show $PROVIDER_NET_NAME -c id -f value)
openstack port create  $PROVIDER_PORT_NAME --network $PROVIDER_NET_ID \
                      --fixed-ip subnet=$PROVIDER_SUBNET_NAME,ip-address=$PROVIDER_NET_IP \
                      --security-group $SEC_GROUP_NAME \
                      --tag $PROVIDER_PORT_NAME
# For some reason, we need to capitalize ID here and nowhere else
PROVIDER_SUBNET_ID=$(openstack subnet list --network $PROVIDER_NET_ID -c ID -f value)
PROVIDER_PORT_ID=$(openstack port list --network $PROVIDER_NET_ID --tags $PROVIDER_PORT_NAME -c id -f value)

# Create the private port
PRIV_NET_ID=$(openstack network show $PRIV_NET_NAME -c id -f value)
openstack port create  $PRIV_PORT_NAME --network $PRIV_NET_ID \
                      --fixed-ip subnet=$PRIV_SUBNET_NAME \
                      --security-group $SEC_GROUP_NAME \
                      --tag $PRIV_PORT_NAME
PRIV_SUBNET_ID=$(openstack subnet list --network $PRIV_NET_ID -c ID -f value)
PRIV_PORT_ID=$(openstack port list --network $PRIV_NET_ID --tags $PRIV_PORT_NAME -c id -f value)

openstack keypair create $KEYPAIR_NAME > ~/$KEYPAIR_NAME.pem
chmod 600 ~/$KEYPAIR_NAME.pem

openstack server create --flavor $FLAVOR_NAME --image $IMAGE_NAME \
                        --key-name $KEYPAIR_NAME \
                        --nic port-id=$PRIV_PORT_ID \
                        --nic port-id=$PROVIDER_PORT_ID \
                        --security-group $SEC_GROUP_NAME \
                        --wait $SERVER_NAME
#PRIV_PORT_ID=$(openstack port list --server $SERVER_NAME --network $PRIV_NET_ID --tags $PRIV_PORT_NAME -c id -f value)

openstack floating ip create --port $PRIV_PORT_ID --floating-ip-address $FLOAT_IP $PUB_NET_NAME

echo "ssh -i ~/$KEYPAIR_NAME.pem -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null $USER_NAME@$FLOAT_IP"
