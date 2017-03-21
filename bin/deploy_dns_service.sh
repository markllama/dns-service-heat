#!/bin/sh
#
# Create a small DNS service.

function usage() {
    cat <<EOF

usage sh bin/full_service.sh [options]

OPTIONS
  -u <dns update keystring>
     A BASE64 encoded MD5 hash string generated by rndc-confgen(8)
     This can also be placed in DNS_UPDATE_KEY to avoid placing a symmetric
     key on the command line
     required (but can be from ENV)

  -s <slaves>
     An integer number of DNS slave servers to create.
     default: 2

  -z <zone>
     The DNS domain suffix for your DNS service
     required

  -f <forwarders>
     A comma separated list of IP addresses. These are the DNS servers
     that will accept forwarding requests from the new service.
     default: nameservers from /etc/resolv.conf on the calling host  

  -c <zone contact>
     The email address of an administrtor responsible for the DNS service and
     content.
     default: admin.<zone>

  -n <stack name>
     The name of the Heat stack to create
     required

  -e <external network name>
     A Neutron network name that allows inbound and outbound traffic
     required

  -S <server_spec_file>
     The name of a file containing a YAML formatted set of Nova instance
     required

     EXAMPLE
        parameters:
          flavor: <nova flavor name>
          image: <glance image name>
          ssh_user: <username>

     Provided sample files:
        env_server_rhel.yaml
        env_server_fedora.yaml

  -R <rhn_credentials_file>
     The name of a file containing a YAML formatted set of RHN or Satellite
     registration information

     EXAMPLE
       parameters:
         rhn_username: <username>
         rhn_password: <password>
         rhn_pool: <pool id>

  -k <nova keypair name>
     The name of a nova keypair to use for access to the instances
     required

  -K <private key file name>
     The name of a file containing the private key for the nova keypair.
     Used by ansible to access the instances for configuration
     required

  -C
     Do not create the stack (use existing stack)

  -A
     Do not run the Ansible playbook to configure the instances
EOF
}

#
# Process arguments into environment variables
#
function parse_args() {
    while getopts "Ac:Ce:f:hk:K:n:N:P:R:s:S:u:z:" arg ; do
        case $arg in
            u) DNS_UPDATE_KEY=$OPTARG ;;
            s) SLAVES=$OPTARG ;;
            z) ZONE=$OPTARG ;;
            f) FORWARDERS=$OPTARG ;;
            c) ZONE_CONTACT=$OPTARG ;;

            n) STACK_NAME=$OPTARG ;;
            e) EXTERNAL_NETWORK_NAME=$OPTARG ;;
            S) SERVER_SPEC_FILE=$OPTARG ;;
            R) RHN_CREDENTIALS_SPEC=$(echo $OPTARG | tr @ .)  ;;
            k) KEYPAIR_NAME=$OPTARG ;;
            K) PRIVATE_KEY_FILE=$OPTARG ;;

            C) NO_STACK=false ;;
            A) NO_CONFIGURE=false ;;

            h) usage && exit
        esac
    done
}

#
# Defaults
#
function set_defaults() {
    #
    # == named service settings ==
    #
    # DNS_UPDATE_KEY=${DNS_UPDATE_KEY:-NODEFAULT}
    SLAVES=${SLAVES:-2}
    # ZONE=${ZONE:-example.com}
    ZONE_CONTACT=${ZONE_CONTACT:-"admin.${ZONE}."}
    FORWARDERS=${FORWARDERS:-$(local_nameservers)}

    # == OSP settings ==
    #
    # Public network to attach to
    # EXTERNAL_NETWORK_NAME=${EXTERNAL_NETWORK_NAME:-public_network}

    # OSP Instance values
    #   flavor
    #   image
    #   ssh_user
    SERVER_SPEC_FILE=${SERVER_SPEC_FILE:-env_server.yaml}

    KEYPAIR_NAME=${KEYPAIR_NAME:-ocp3}
    STACK_NAME=${STACK_NAME:-dns-service}

    # RHN Credentials: no default
    #  rhn_username
    #  rhn_password
    #  rhn_pool_id
    #  sat6_organization
    #  sat6_activationkey
    #RHN_CREDENTIALS_SPEC=${RHN_CREDENTIALS_SPEC:-rhn_credentials.yaml}

    #PRIVATE_KEY_FILE=${PRIVATE_KEY_FILE:-~/.ssh/id_rsa}

    # Defaults to true
    #CREATE_STACK = false
    #CONFIGURE = false
}

function check_defaults() {
    local MISSING=0
    local MESSAGE="ERROR: Missing required variables - use -h for help"
    
    # ZONE
    [ -z "${ZONE}" ] &&
        MISSING=$(($MISSING + 1)) && MESSAGE="$MESSAGE
  missing required variable ZONE (-z)"
    
    # DNS_UPDATE_KEY
    [ -z "${DNS_UPDATE_KEY}" ] &&
        MISSING=$(($MISSING + 1)) && MESSAGE="$MESSAGE
  missing required variable DNS_UPDATE_KEY (-u)"
    
    # SERVER_SPEC_FILE
    [ -z "${SERVER_SPEC_FILE}" ] &&
        MISSING=$(($MISSING + 1)) && MESSAGE="$MESSAGE
  missing required variable SERVER_SPEC_FILE (-S)"
    
    # EXTERNAL_NETWORK_NAME
    [ -z "${EXTERNAL_NETWORK_NAME}" ] &&
        MISSING=$(($MISSING + 1)) && MESSAGE="$MESSAGE
  missing required variable EXTERNAL_NETWORK_NAME (-e)"

    # KEYPAIR_NAME
    [ -z "${KEYPAIR_NAME}" ] &&
        MISSING=$(($MISSING + 1)) && MESSAGE="$MESSAGE
  missing required variable KEYPAIR_NAME (-k)"

    # PRIVATE_KEY_FILE
    [ -z "${PRIVATE_KEY_FILE}" ] &&
        MISSING=$(($MISSING + 1)) && MESSAGE="$MESSAGE
  missing required variable PRIVATE_KEY_FILE (-K)"

    [ "$MISSING" -gt 0 ] && echo "$MESSAGE" && exit 1
}

# Get local nameserver list from /etc/resolv.con
function local_nameservers() {
    # Get the nameserver list, replace newlines with commas
    grep nameserver /etc/resolv.conf \
        | awk '{print $2}' \
        | sed ':a;N;$!ba;s/\n/,/g'
}

# Execute a command until it passes
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

# Build and execute the stack create command
function create_stack() {

    # RHN credentials are only needed for RHEL images in the SERVER SPEC
    [ -z "$RHN_CREDENTIALS_SPEC" ] ||
        local RHN_CREDENTIALS_ARG="-e $RHN_CREDENTIALS_SPEC"

    set -x
    openstack stack create \
              -e ${SERVER_SPEC_FILE} \
              ${RHN_CREDENTIALS_ARG} \
              --parameter external_network=${EXTERNAL_NETWORK_NAME} \
              --parameter domain_name=${ZONE} \
              --parameter slave_count=${SLAVES} \
              --parameter dns_forwarders=${FORWARDERS} \
              --parameter ssh_key_name=${KEYPAIR_NAME} \
              -t heat/dns_service.yaml ${STACK_NAME}
    set +x
}

# Extract the status of a named stack by CLI
function stack_status() {
		openstack stack show $1 -f json | jq '.stack_status' | tr -d \"
}

# Check for stack complete status
function stack_complete() {
		local STATUS=$(stack_status $1)
		[ "${STATUS}" == 'CREATE_COMPLETE' -o "${STATUS}" == 'CREATE_FAILED' ]
}

# Determine the ssh user for logins by querying the stack
function ssh_user_from_stack() {
  openstack stack show $1 -f json | jq '.parameters.ssh_user'
}

# The python script wants multiple -f <ip> values
function split_forwarders() {
    # FORWARDERS=$1
    for I in $(echo $1 | tr , ' ') ; do echo -n " -f $I" ; done 
}

# Write a YAML file as input to jinja to create the inventory
# master and slave name/ip information comes from OSP
function generate_inventory() {

    python bin/stack_data.py --zone ${ZONE} \
           --contact ${ZONE_CONTACT} \
           -k ${DNS_UPDATE_KEY} \
           $(split_forwarders ${FORWARDERS}) > inventory.${STACK_NAME}
}

# Execute the ansible playbook on the new instances
function configure_dns_services() {
		SSH_USER_NAME=$(ssh_user_from_stack ${STACK_NAME})

		export ANSIBLE_HOST_KEY_CHECKING=False
		ansible-playbook \
				-i inventory.${STACK_NAME} \
				--become --user ${SSH_USER_NAME} \
				--private-key ${PRIVATE_KEY_FILE} \
				ansible/bind-server.yml
}

# =============================================================================
# MAIN
# =============================================================================

# Prepare input values
parse_args $@
set_defaults
check_defaults

if [ -z "${NO_STACK}" ] ; then
    create_stack
    retry stack_complete "${STACK_NAME}"
fi

# Don't try ansible if the stack failed
if [ "$(stack_status ${STACK_NAME})" == "CREATE_FAILED" ] ; then
		echo "Create failed"
		exit 1
fi

# Configure the service on the instances
if [ -z "${NO_CONFIGURE}" ] ; then
    generate_inventory
    configure_dns_services
fi
