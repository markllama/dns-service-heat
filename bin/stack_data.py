!/usr/bin/env python
#
#
#
import os,sys,re
from optparse import OptionParser

from novaclient import client

import yaml

def parse_cli():
    opts = OptionParser()
    opts.add_option("-u", "--username", default=os.environ['OS_USERNAME'])
    opts.add_option("-p", "--password", default=os.environ['OS_PASSWORD'])
    opts.add_option("-P", "--project", default=os.environ['OS_TENANT_NAME'])
    opts.add_option("-U", "--auth-url", default=os.environ['OS_AUTH_URL'])

    opts.add_option("-z", "--zone", default="example.com")
    opts.add_option("-c", "--contact", default="admin.example.com")
    opts.add_option("-k", "--update-key", default=os.getenv('UPDATE_KEY'))

    opts.add_option("-n", "--network", default="dns-network")
    opts.add_option("-m", "--master", default="ns-master")
    opts.add_option("-s", "--slave-prefix", default="ns")

    opts.add_option("-f", "--forwarder", type="string", action="append", dest="forwarders", default=[])
    
    return opts.parse_args()

def floating_ip(server, network):
    entry = None
    for interface in server.addresses[network]:
        if interface['OS-EXT-IPS:type'] == 'floating':
            entry = {"name": server.name, "address": interface['addr']}
    return entry

def forwarders():
    ns_re = re.compile("^nameserver *(.*)$")
    f = open('/etc/resolv.conf')
    return [ns_re.match(l).groups()[0] for l in f.readlines() if ns_re.match(l)]

if __name__ == "__main__":

    (opts, args) = parse_cli()

    master_re = re.compile("^(%s)\." % opts.master)

    zone_re = re.compile("\.%s$" % opts.zone)
    
    nova = client.Client("2.0",
                         opts.username,
                         opts.password,
                         opts.project,
                         opts.auth_url)

    servers = [floating_ip(server, opts.network) for server in nova.servers.list()
]

    struct = dict()

    struct['zone'] = opts.zone
    struct['contact'] = opts.contact
    struct['update_key'] = opts.update_key
    if len(opts.forwarders) > 0:
        struct['forwarders'] = opts.forwarders
    else:
        struct['forwarders'] = forwarders()
    struct['masters'] = [h for h in servers if master_re.match(h['name'])]
    struct['masters'] = [{'name': zone_re.sub('', s['name']), 'address': s['address']} for s in struct['masters']]

    struct['slaves'] = [h for h in servers if not master_re.match(h['name'])]

    struct['slaves'] = [{'name': zone_re.sub('', s['name']), 'address': s['address']} for s in struct['slaves']]
    print yaml.dump(struct, default_flow_style=False)
#    print yaml.dump(struct)
