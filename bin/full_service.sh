#!/bin/sh

PRIVATE_KEY_FILE=${PRIVATE_KEY_FILE:-~/.ssh/dns_stack_key}
[ -r $PRIVATE_KEY_FILE ] || (echo no key file $PRIVATE_KEY_FILE && exit 1)

openstack stack create -e dns_service_parameters.yaml -e rhn_credentials.yaml   -t dns_service.yaml  dns-service

function stack_complete() {
		# $1 = STACK_NAME
		[ $(openstack stack show $1 -f json | jq '.stack_status' | tr -d \") == "CREATE_COMPLETE" ]
}

POLL_TRY=0
POLL_INTERVAL=5
while ! stack_complete dns-service ; do
		echo Try $POLL_TRY: waiting $POLL_INTERVAL seconds
		sleep $POLL_INTERVAL
		POLL_TRY=$(($POLL_TRY + 1))
done

python bin/stack_data.py --zone dns.example.com --update-key bKcZ4P2FhWKRQoWtx5F33w== >dns_stack_data.yaml

jinja2-2.7 ansible/inventory.j2 dns_stack_data.yaml > inventory

ansible-playbook -i inventory --become --user cloud-user --private-key ${PRIVATE_KEY_FILE} --ssh-common-args "-o StrictHostKeyChecking=no" ../dns-service-playbooks/playbooks/bind-server.yml

python bin/prime_slave_servers.py
