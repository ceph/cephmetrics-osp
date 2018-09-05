#!/usr/bin/env bash
if [ -z "$1" ];
then
    echo "Usage: $0 conf_file" >&2
    exit 1
fi
source "./$1"
exec ssh -i ~/$KEYPAIR_NAME.pem -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null $USER_NAME@$FLOAT_IP
