#!/usr/bin/env bash
if [ -z "$1" ];
then
    echo "Usage: $0 conf_file" >&2
    exit 1
fi
set -x

source ~/overcloudrc
source "./$1"

openstack server delete $SERVER_NAME
openstack keypair delete $KEYPAIR_NAME
rm ~/$KEYPAIR_NAME.pem
openstack flavor delete $FLAVOR_NAME

FLOAT_IP_ID=$(openstack floating ip show $FLOAT_IP -c id -f value)
openstack floating ip delete $FLOAT_IP_ID

openstack router remove subnet $ROUTER_NAME $PRIV_SUBNET_NAME
openstack router unset --external-gateway $ROUTER_NAME
openstack router delete $ROUTER_NAME

PRIV_NET_ID=$(openstack network show $PRIV_NET_NAME -c id -f value)
PRIV_SUBNET_ID=$(openstack subnet list --network $PRIV_NET_ID -c ID -f value)
PRIV_PORT_ID=$(openstack port list --network $PRIV_NET_ID -c id -f value)
openstack port delete $PRIV_PORT_ID
openstack subnet delete $PRIV_SUBNET_NAME
openstack network delete $PRIV_NET_ID

openstack subnet delete $PUB_SUBNET_NAME
PUB_NET_ID=$(openstack network show $PUB_NET_NAME -c id -f value)
openstack network delete $PUB_NET_ID

PROVIDER_NET_ID=$(openstack network show $PROVIDER_NET_NAME -c id -f value)
PROVIDER_PORT_ID=$(openstack port list --network $PROVIDER_NET_ID -c id -f value)
openstack port delete $PROVIDER_PORT_ID
openstack subnet delete $PROVIDER_SUBNET_NAME
openstack network delete $PROVIDER_NET_ID

openstack security group delete $SEC_GROUP_NAME
