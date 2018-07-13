#!/usr/bin/env python
import argparse
import json
import os
import yaml


def parse_args():
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "file",
        nargs=1,
    )
    parser.add_argument(
        "-i", "--input-format",
        choices=["tripleo", "ceph-ansible"],
        default="tripleo",
    )
    parser.add_argument(
        "-f", "--format",
        choices=["hosts", "hosts_yaml", "raw", "yaml"],
        default="yaml",
    )
    parser.add_argument(
        "-a", "--add-host",
        help="Optionally add a host to the inventory using information in"
             "create.sh format",
    )
    return parser.parse_args()


def load_file(path):
    ext = None
    if '.' in path:
        ext = path.split('.')[-1]
    with open(path) as f:
        contents = f.read()
    if ext in ('yaml', 'yml'):
        return yaml.safe_load(contents)
    elif ext == 'json':
        return json.loads(contents)
    elif ext == 'conf':
        return dict(map(
            lambda s: s.split('='),
            contents.strip().split('\n'),
        ))
    elif ext is None:
        raise NotImplementedError


def simplify_tripleo_inventory(orig_obj):
    group_map = dict(
      Controller=['mons', 'mgrs'],
      CephStorage=['osds'],
      Compute=['iscsis'],
    )
    new_obj = dict(
        all=dict(),
    )
    for orig_group_name, new_group_names in group_map.items():
        orig_group = orig_obj.get(orig_group_name)
        if orig_group is None:
            continue
        ips = dict()
        for child_name in orig_group['children'].keys():
            ips[child_name] = orig_obj[child_name]['vars']['ctlplane_ip']
            new_obj['all'].setdefault('hosts', dict())[child_name] = dict(
                ansible_host=ips[child_name],
                ansible_ssh_user='heat-admin',
            )
            for new_group_name in new_group_names:
                new_obj.setdefault(new_group_name, dict()).setdefault(
                    'hosts', dict())[child_name] = dict()
    return new_obj


def format_hosts_dict(inventory_obj):
    hosts_obj = dict()
    for group_name, group in inventory_obj.items():
        for host_name, host in group.get('hosts', dict()).items():
            if 'ansible_host' in host:
                hosts_obj[host_name] = host['ansible_host']
    return hosts_obj


def format_hosts(inventory_obj):
    hosts_obj = format_hosts_dict(inventory_obj)
    return reduce(
        lambda x, y: "\n".join([x, y]),
        map(
            lambda x: " ".join(x[::-1]),
            hosts_obj.items(),
        ),
    )


def format_hosts_yaml(inventory_obj):
    hosts_obj = format_hosts_dict(inventory_obj)
    return yaml.safe_dump(
        hosts_obj,
        default_flow_style=False,
    )


def add_host(inventory, host_conf):
    host_obj = dict(
        ansible_host=host_conf['FLOAT_IP'],
        ansible_ssh_common_args="-o StrictHostKeyChecking=no "
                                "-o UserKnownHostsFile=/dev/null",
        ansible_ssh_private_key_file=os.path.expanduser(
            '~/%s.pem' % host_conf['KEYPAIR_NAME']),
        ansible_ssh_user=host_conf['USER_NAME'],
    )
    server_name = host_conf['SERVER_NAME']
    inventory.setdefault('all', dict()).\
        setdefault('hosts', dict())[server_name] = host_obj
    group_name = host_conf.get('GROUP_NAME', 'ceph-grafana')
    inventory.setdefault(group_name, dict()).\
        setdefault('hosts', dict())[server_name] = dict()
    return inventory


def add_vars(inventory):
    etc_hosts = format_hosts_dict(inventory)
    inventory.setdefault('all', dict()).\
        setdefault('vars', dict()).\
        setdefault('prometheus', dict())['etc_hosts'] = etc_hosts
    inventory['all']['vars'].\
        setdefault('grafana', dict())['admin_password'] = 'admin'
    return inventory


if __name__ == "__main__":
    args = parse_args()

    orig_obj = load_file(args.file[0])

    if args.input_format == "tripleo":
        inv = simplify_tripleo_inventory(orig_obj)
    elif args.input_format == "ceph-ansible":
        inv = orig_obj

    if args.add_host:
        new_host_conf = load_file(args.add_host)
        add_host(inv, new_host_conf)

    add_vars(inv)

    if args.format == "yaml":
        print yaml.safe_dump(inv, default_flow_style=False)
    elif args.format == "hosts":
        print format_hosts(inv)
    elif args.format == "hosts_yaml":
        print format_hosts_yaml(inv)
    elif args.format == "raw":
        print inv
