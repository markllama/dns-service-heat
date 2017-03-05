#!/usr/bin/env python

from argparse import ArgumentParser

# prime yaml to accept it's very own output
import yaml

# python2-dns
import dns.query
import dns.tsigkeyring
import dns.update

def python_unicode(loader, node):
    return node.value

def add_a_record(server, zone, key, name, address, ttl=300):
    # make input zones absolute
    #zone = zone + '.' if not zone.endswith('.')
    keyring = dns.tsigkeyring.from_text({'update-key': key})
    update = dns.update.Update(zone, keyring=keyring)
    update.replace(name, ttl, 'a', address)
    response = dns.query.tcp(update, server)
    return response

# apparently python yaml emits the python/unicode tag but doesn't read it. Hmm
yaml.SafeLoader.add_constructor(
    "tag:yaml.org,2002:python/unicode",
    python_unicode)

def add_ns_record(server, zone, key, nameserver, ttl=300):

    # make input zones absolute
    #zone = zone + '.' if not zone.endswith('.')

    keyring = dns.tsigkeyring.from_text({'update-key': key})
    update = dns.update.Update(zone, keyring=keyring)
    update.add(zone, ttl, 'ns', nameserver)
    response = dns.query.tcp(update, server)
    return response

def process_arguments():
        parser = ArgumentParser()
        parser.add_argument("-f", "--file", type=str, default="dns_stack_data.yaml")
        parser.add_argument("-t", "--ttl", type=str, default=300)

        return parser.parse_args()

if __name__ == "__main__":


    opts = process_arguments()

    f = open(opts.file)
    service_spec = yaml.safe_load(f)
    f.close()


    zone = service_spec['zone']
    key = service_spec['update_key']
    master= service_spec['masters'][0]['address']

    
    for slave in service_spec['slaves']:
        add_a_record(master, zone+'.', key, slave['name']+'.', slave['address'])
        add_ns_record(master, zone+'.', key, slave['name'])
