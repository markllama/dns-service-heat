#!/usr/bin/env python
#
# given:
#   osp_credentials:
#     - username
#     - password
#     - project_name
#     - auth_url
#   network_name
#   
# 
#

import os,sys,re
from optparse import OptionParser

from novaclient import client

# python2-dns
import dns.query
import dns.tsigkeyring
import dns.update

                       
def parse_cli():
    opts = OptionParser()
    opts.add_option("-u", "--username", default=os.environ['OS_USERNAME'])
    opts.add_option("-p", "--password", default=os.environ['OS_PASSWORD'])
    opts.add_option("-P", "--project", default=os.environ['OS_TENANT_NAME'])
    opts.add_option("-U", "--auth-url", default=os.environ['OS_AUTH_URL'])
    opts.add_option("-n", "--network", default="dns-network")
    opts.add_option("-m", "--nameserver")
    opts.add_option("-k", "--update-key", default=os.getenv('UPDATE_KEY'))
    opts.add_option("-S", "--stack", default="ocp3")
    opts.add_option("-z", "--zone", default="example.com")
    opts.add_option("-s", "--subzone", default="control")
    opts.add_option("-M", "--master-pattern", default="master")
    opts.add_option("-I", "--infra-pattern", default="infra")
    opts.add_option("-N", "--node-pattern", default="node")
#    opts.add_option("-s", "--slave-prefix", default="ns")

    return opts.parse_args()

def floating_ip(server, network):
    entry = None
    if server.addresses.get(network):
        for interface in server.addresses[network]:
            if interface['OS-EXT-IPS:type'] == 'floating':
                entry = {"name": server.name, "address": interface['addr']}
    return entry

def fixed_ip(server, network):
    entry = None
    if server.addresses.get(network):
        for interface in server.addresses[network]:
            if interface['OS-EXT-IPS:type'] == 'fixed':
                entry = {"name": server.name, "address": interface['addr']}
    return entry

def add_a_record(name,zone,ipv4addr,master,key):
    keyring = dns.tsigkeyring.from_text({'update-key': key})
    update = dns.update.Update(zone, keyring=keyring)
    update.replace(name, 300, 'a', ipv4addr)
    response = dns.query.tcp(update, master)
    return response

def host_part(fqdn,zone):
    zone_re = re.compile("(.*).(%s)$" % zone)
    response = zone_re.match(fqdn)
    return response.groups()[0]
    
if __name__ == "__main__":

    (opts, args) = parse_cli()

    #master_re = re.compile("^(%s)\." % opts.master)
    
    nova = client.Client("2.0",
                         opts.username,
                         opts.password,
                         opts.project,
                         opts.auth_url)

    
    #print nova.servers.list()[0].addresses[opts.network]
    pairs = [fixed_ip(server, opts.network) for server in nova.servers.list() if fixed_ip(server,opts.network) is not None]
    #print pairs
    
    #set_a_record(pairs
    for record in pairs:
        add_a_record(
            host_part(record['name'], opts.zone),
            opts.zone,
            record['address'],
            opts.nameserver,
            opts.update_key
        )
                

    pairs = [floating_ip(server, opts.network) for server in nova.servers.list() if floating_ip(server,opts.network) is not None]
    #print pairs
    
    #set_a_record(pairs
    for record in pairs:
        add_a_record(
            host_part(re.sub(opts.subzone + '.', '', record['name']), opts.zone),
            opts.zone,
            record['address'],
            opts.nameserver,
            opts.update_key
        )
                

