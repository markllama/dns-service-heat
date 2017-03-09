#!/bin/sh

DNS_SPEC=${DNS_SPEC:-dns_service_parameters.yaml}
ZONE=${ZONE:-example.com}
UPDATE_KEY=${UPDATE_KEY:-"bKcZ4P2FhWKRQoWtx5F33w=="}
STACK_NAME=${STACK_NAME:-dns-service}
#RHN_CREDENTIALS="-e rhn_credentials.yaml"
INSTANCE_USER=fedora

PRIVATE_KEY_FILE=${PRIVATE_KEY_FILE:-~/.ssh/dns_stack_key_rsa}
[ -r $PRIVATE_KEY_FILE ] || (echo no key file $PRIVATE_KEY_FILE && exit 1)

function retry() {
    # cmd = $@
    local POLL_TRY=0
    local POLL_INTERVAL=5
    echo "Trying $@ at $POLL_INTERVAL second intervals"
    local START=$(date +%s)
    while ! $@ ; do
        [ $(($POLL_TRY % 6)) -eq 0 ] && echo -n $(($POLL_TRY * $POLL_INTERVAL)) || echo -n .
        echo -n .
		    sleep $POLL_INTERVAL
		    POLL_TRY=$(($POLL_TRY + 1))
    done
    local END=$(date +%s)
    local DURATION=$(($END - $START))
    echo Done
    echo Completed in $DURATION seconds
}

function stack_complete() {
		# $1 = STACK_NAME
		[ $(openstack stack show $1 -f json | jq '.stack_status' | tr -d \") == "CREATE_COMPLETE" ]
}

# =============================================================================
# MAIN
# =============================================================================


# Create DNS service stack

# INPUTS
#   instance_parameters
#     image
#     flavor
#     ssh_user
#
#   RHN credentials
#     RHN_USERNAME
#     RHN_PASSWORD
#     RHN_POOL_ID
#
#   OSP parameters
#
#     OS_AUTH_URL
#     OS_USERNAME
#     OS_PASSWORD
#     OS_TENANT_NAME
#     OS_REGION
#
#   DNS configuration parameters
#
#     DNS_ZONE
#     DNS_UPDATE_KEY
#
#   Stack Identification
#     STACK_NAME
#
set -x
openstack stack create \
          -e ${DNS_SPEC} \
          --parameter domain_name=${ZONE} \
          ${RHN_CREDENTIALS} \
          --parameter ssh_user=$INSTANCE_USER \
          -t dns_service.yaml \
          ${STACK_NAME}
set +x

retry stack_complete ${STACK_NAME}

# Generate a YAML file with the ansible configuration information:
#
# INPUTS
#   OSP Credentials
#     OS_AUTH_URL
#     OS_USERNAME
#     OS_PASSWORD
#     OS_TENANT_NAME
#     OS_REGION_NAME
#     
#   DNS Configuration
#     DNS_ZONE
#     DNS_CONTACT
#     DNS_UPDATE_KEY
#     DNS_FORWARDER_LIST
#
#   OSP Configuration
#     NETWORK_NAME - the Neutron network name to locate IP addresses
#
#     DNS_MASTER_HOSTNAME
#     DNS_SLAVE_HOSTNAME_PREFIX
#
# OUTPUTS
#    
#   DNS Configuration
#     DNS_ZONE
#     DNS_CONTACT
#     DNS_UPDATE_KEY
#     DNS_FORWARDER_LIST
#     DNS_MASTER_LIST {'name': '<name>', 'address': '<address>' }
#     DNS_SLAVE_LIST {'name': '<name>', 'address': '<address>' }
python bin/stack_data.py \
       --zone $ZONE \
       --update-key ${UPDATE_KEY}\
       > dns_stack_data.yaml

#
# create an inventory from a template and the stack host information
#
# INPUTS
#   YAML file above
# OUTPUTS
#   INI formatted inventory file for Ansible
jinja2-2.7 ansible/inventory.j2 dns_stack_data.yaml > inventory

echo "Sleeping for stack instances to stabilize"
sleep 30

#
# Apply the playbook to the OSP instances to create a DNS service
#
# INPUTS
#   INVENTORY FILE
#   INSTANCE_USER
#   SSH_PRIVATE_KEY_FILE
export ANSIBLE_HOST_KEY_CHECKING=False
ansible-playbook -i inventory \
  --become --user $INSTANCE_USER --private-key ${PRIVATE_KEY_FILE} \
  --ssh-common-args "-o StrictHostKeyChecking=no" \
  ../dns-service-playbooks/playbooks/bind-server.yml


#
# Add the secondary name servers to the zone as both A and NS records
#
#python bin/prime_slave_servers.py
