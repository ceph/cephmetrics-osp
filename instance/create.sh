#!/usr/bin/env bash
# https://docs.openstack.org/networking-ovn/latest/install/tripleo.html
if [ -z "$1" ];
then
    echo "Usage: $0 conf_file" >&2
    exit 1
fi
set -ex

. $1
ADMIN_RC="$HOME/overcloudrc"
. $ADMIN_RC

# Create the project, and also create an rc file for it
openstack project create $PROJECT_NAME
openstack user create $PROJECT_USER --password $PROJECT_USER_PASSWORD
openstack role create $PROJECT_ROLE
openstack role add --user $PROJECT_USER --project $PROJECT_NAME $PROJECT_ROLE

PROJECT_RC="$HOME/${PROJECT_NAME}rc"
cat << EOF > $PROJECT_RC
# Clear any old environment that may conflict.
for key in \$( set | awk '{FS="="}  /^OS_/ {print \$1}' ); do unset \$key ; done
export OS_NO_CACHE=$OS_NO_CACHE
export COMPUTE_API_VERSION=$COMPUTE_API_VERSION
export OS_USERNAME=$PROJECT_USER
export no_proxy=$no_proxy
export OS_USER_DOMAIN_NAME=$OS_USER_DOMAIN_NAME
export OS_VOLUME_API_VERSION=$OS_VOLUME_API_VERSION
export OS_CLOUDNAME=$OS_CLOUDNAME
export OS_AUTH_URL=$OS_AUTH_URL
export NOVA_VERSION=$NOVA_VERSION
export OS_IMAGE_API_VERSION=$OS_IMAGE_API_VERSION
export OS_PASSWORD=$PROJECT_USER_PASSWORD
export OS_PROJECT_DOMAIN_NAME=$OS_PROJECT_DOMAIN_NAME
export OS_IDENTITY_API_VERSION=$OS_IDENTITY_API_VERSION
export OS_PROJECT_NAME=$PROJECT_NAME
export OS_AUTH_TYPE=$OS_AUTH_TYPE
export PYTHONWARNINGS="ignore:Certificate has no, ignore:A true SSLContext object is not available"

# Add OS_CLOUDNAME to PS1
if [ -z "\${CLOUDPROMPT_ENABLED:-}" ]; then
    export PS1=\${PS1:-""}
    export PS1=\\\${OS_CLOUDNAME:+"(\\\$OS_CLOUDNAME)"}\ \$PS1
    export CLOUDPROMPT_ENABLED=1
fi
EOF

# Create a security group and add several rules
. $PROJECT_RC
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

# Create the private network and subnet
openstack network create $PRIV_NET_NAME
PRIV_NET_ID=$(openstack network show $PRIV_NET_NAME -c id -f value)
openstack subnet create --network $PRIV_NET_NAME $PRIV_SUBNET_NAME \
                        --dns-nameserver $DNS_IP \
                        --subnet-range 192.168.99.0/24
# For some reason, we need to capitalize ID here and nowhere else
PRIV_SUBNET_ID=$(openstack subnet list --network $PRIV_NET_ID -c ID -f value)

# Create the private port
openstack port create $PRIV_PORT_NAME --network $PRIV_NET_ID \
                      --fixed-ip subnet=$PRIV_SUBNET_NAME \
                      --security-group $SEC_GROUP_NAME \
                      --tag $PRIV_PORT_NAME
PRIV_PORT_ID=$(openstack port list --network $PRIV_NET_ID --tags $PRIV_PORT_NAME -c id -f value)

. $ADMIN_RC
# Create the public network and subnet
openstack network create $PUB_NET_NAME --provider-physical-network datacentre \
                                --provider-network-type vlan \
                                --provider-segment 10 \
                                --external --share
openstack subnet create --network $PUB_NET_NAME $PUB_SUBNET_NAME --subnet-range 10.0.0.0/24 \
                         --allocation-pool start=10.0.0.20,end=10.0.0.250 \
                         --dns-nameserver $DNS_IP --gateway 10.0.0.1 \
                         --no-dhcp

# Create a router and use it to connect the public and private networks
openstack router create $ROUTER_NAME
openstack router set $ROUTER_NAME --external-gateway $PUB_NET_NAME
openstack router add subnet $ROUTER_NAME $PRIV_NET_NAME

# Create the floating IP that we will use for the instance
openstack floating ip create --port $PRIV_PORT_ID --floating-ip-address $FLOAT_IP $PUB_NET_NAME

# Create the provider network and subnet
openstack network create $PROVIDER_NET_NAME --provider-physical-network datacentre \
                                            --provider-network-type vlan \
                                            --provider-segment $PROVIDER_SEGMENT \
                                            --share
PROVIDER_NET_ID=$(openstack network show $PROVIDER_NET_NAME -c id -f value)
openstack subnet create $PROVIDER_SUBNET_NAME --network $PROVIDER_NET_NAME \
                        --subnet-range $PROVIDER_NET_CIDR \
                        --allocation-pool $PROVIDER_NET_ALLOCATION_POOL \
                        --no-dhcp
# For some reason, we need to capitalize ID here and nowhere else
PROVIDER_SUBNET_ID=$(openstack subnet list --network $PROVIDER_NET_ID -c ID -f value)

# Create the provider port
openstack port create $PROVIDER_PORT_NAME --network $PROVIDER_NET_ID \
                      --fixed-ip subnet=$PROVIDER_SUBNET_NAME,ip-address=$PROVIDER_NET_IP \
                      --security-group $SEC_GROUP_NAME --project $PROJECT_NAME \
                      --tag $PROVIDER_PORT_NAME
PROVIDER_PORT_ID=$(openstack port list --network $PROVIDER_NET_ID --tags $PROVIDER_PORT_NAME -c id -f value)

# Create the flavor
openstack flavor create $FLAVOR_NAME --disk $FLAVOR_DISK --vcpus $FLAVOR_CPUS --ram $FLAVOR_RAM

. $PROJECT_RC
openstack keypair create $KEYPAIR_NAME > ~/$KEYPAIR_NAME.pem
chmod 600 ~/$KEYPAIR_NAME.pem

# Create a volume with the same name as the server; when we create the server
# using this volume, our data will persist across reboots.
openstack volume create --image $IMAGE_NAME --size $FLAVOR_DISK --bootable \
    $SERVER_NAME

# volume create has no --wait flag
while [ "$(openstack volume show $SERVER_NAME -c status -f value)" != "available" ]
    do sleep 5
done

# Assemble the user-data
# This is necessary because up until cloud-init 18.3, network configuration
# data sent by OpenStack wasn't used. This meant that only one NIC was usable.
# RHEL 7.6 is slated to ship 18.2.
# https://github.com/cloud-init/cloud-init/commit/cd1de5f
# https://bugs.launchpad.net/cloud-init/+bug/1749717
cat << USER_DATA > /tmp/user-data.txt
#!/usr/bin/env bash
cat << IFCFG > /etc/sysconfig/network-scripts/ifcfg-eth1
DEVICE="eth1"
ONBOOT=yes
HWADDR=$(openstack port list --tags $PROVIDER_PORT_NAME -c "MAC Address" -f value)
TYPE=Ethernet
BOOTPROTO=static
IPADDR=$PROVIDER_NET_IP
$(ipcalc --netmask $PROVIDER_NET_CIDR)
IFCFG
ifup eth1
USER_DATA

openstack server create --flavor $FLAVOR_NAME --volume $SERVER_NAME \
                        --key-name $KEYPAIR_NAME \
                        --nic port-id=$PRIV_PORT_ID \
                        --nic port-id=$PROVIDER_PORT_ID \
                        --security-group $SEC_GROUP_NAME \
                        --user-data /tmp/user-data.txt \
                        --wait $SERVER_NAME

echo "Success! Please allow a few minutes for the instance to boot and initialize before proceeding."
echo "Once the instance is fully up, you should be able to use the following command to access it:"
echo "ssh -i ~/$KEYPAIR_NAME.pem -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null $USER_NAME@$FLOAT_IP"
