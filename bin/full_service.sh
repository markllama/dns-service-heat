#!/bin/sh

DNS_SPEC=${DNS_SPEC:-dns_service_parameters.yaml}
ZONE=${ZONE:-example.com}
STACK_NAME=${STACK_NAME:-dns-service}

PRIVATE_KEY_FILE=${PRIVATE_KEY_FILE:-~/.ssh/dns_stack_key_rsa}
[ -r $PRIVATE_KEY_FILE ] || (echo no key file $PRIVATE_KEY_FILE && exit 1)

function retry() {
    # cmd = $@
    local POLL_TRY=0
    local POLL_INTERVAL=5
    while ! $@ ; do
        echo Try $POLL_TRY: waiting $POLL_INTERVAL seconds
		    sleep $POLL_INTERVAL
		    POLL_TRY=$(($POLL_TRY + 1))
    done
}

function stack_complete() {
		# $1 = STACK_NAME
		[ $(openstack stack show $1 -f json | jq '.stack_status' | tr -d \") == "CREATE_COMPLETE" ]
}

# =============================================================================
# MAIN
# =============================================================================

openstack stack create \
          -e ${DNS_SPEC} \
          --parameter domain_name=${ZONE} \
          -e rhn_credentials.yaml \
          -t dns_service.yaml \
          ${STACK_NAME}

retry stack_complete $STACK_NAME

#
# Extract the host information from openstack and create a yaml file with data
# to apply to an inventory template
#
python bin/stack_data.py \
       --zone $ZONE \
       --update-key bKcZ4P2FhWKRQoWtx5F33w== \
       > dns_stack_data.yaml

#
# create an inventory from a template and the stack host information
#
jinja2-2.7 ansible/inventory.j2 dns_stack_data.yaml > inventory

echo "Sleeping for stack instances to stabilize"
sleep 30

#
# Apply the playbook to the OSP instances to create a DNS service
#
ansible-playbook -i inventory \
  --become --user cloud-user --private-key ${PRIVATE_KEY_FILE} \
  --ssh-common-args "-o StrictHostKeyChecking=no" \
  ../dns-service-playbooks/playbooks/bind-server.yml


#
# Add the secondary name servers to the zone as both A and NS records
#
python bin/prime_slave_servers.py
