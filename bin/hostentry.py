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
        print [i['addr'] for i in server.addresses['dns-network'] if i[u'OS-EXT-IPS:type' == u'floating']]
