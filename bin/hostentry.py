#!/usr/bin/env python
#
#
#

import os
from novaclient import client

if __name__ == "__main__":
    nova = client.Client("2.0",
                         os.environ["OS_USERNAME"],
                         os.environ["OS_PASSWORD"],
                         os.environ["OS_TENANT_NAME"],
                         os.environ["OS_AUTH_URL"])

    for server in nova.servers.list():
        #print server.name
        for interface in server.addresses['dns-network']:
            if interface['OS-EXT-IPS:type'] == 'floating':
                print interface['addr'] + ' ' + server.name
            #print "  " + interface['OS-EXT-IPS:type'] + " " + interface['addr']
            #print "  " + str(interface)
