#!/bin/sh
#
# 
#

#
#
#
function parse_args() {
    while getopts "c:k:K:n:N:P:R:s:S:z:" arg ; do
        case $arg in
            k) DNS_UPDATE_KEY=$OPTARG ;;
            s) SLAVES=$OPTARG ;;
            z) ZONE=$OPTARG ;;
            f) FORWARDERS=$OPTARG ;;
            c) ZONE_CONTACT=$OPTARG ;;

            n) STACK_NAME=$OPTARG ;;
            N) NETWORK_NAME=$OPTARG ;;
            S) SERVER_SPEC=$OPTARG ;;
            R) RHN_CREDENTIALS_SPEC=$OPTARG ;;
            K) SSH_KEY_NAME=$OPTARG ;;
            P) PRIVATE_KEY_FILE=$OPTARG ;;
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
    DNS_UPDATE_KEY=${DNS_UPDATE_KEY:-NODEFAULT}
    SLAVES=${SLAVES:-2}
    ZONE=${ZONE:-example.com}
    ZONE_CONTACT=${ZONE_CONTACT:-"admin.${ZONE}."}
    FORWARDERS=${FORWARDERS:-$(local_nameservers)}

    # == OSP settings ==
    #
    # Public network to attach to
    NETWORK_NAME=${NETWORK_NAME:-public_network}

    # OSP Instance values
    #   flavor
    #   image
    #   ssh_user
    SERVER_SPEC=${SERVER_SPEC:-env_server.yaml}

    SSH_KEY_NAME=${SSH_KEY_NAME:-ocp3}
    STACK_NAME=${STACK_NAME:-dns-service}

    # RHN Credentials: no default
    #  rhn_username
    #  rhn_password
    #  rhn_pool_id
    #  sat6_organization
    #  sat6_activationkey
    #RHN_CREDENTIALS_SPEC=${RHN_CREDENTIALS_SPEC:-rhn_credentials.yaml}

    PRIVATE_KEY_FILE=${PRIVATE_KEY_FILE:-~/.ssh/id_rsa}
}

# Get local nameserver list from /etc/resolv.con
function local_nameservers() {
    # Get the nameserver list, replace newlines with commas
    grep nameserver /etc/resolv.conf \
        | awk '{print $2}' \
        | sed ':a;N;$!ba;s/\n/,/g'
}

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

function create_stack() {

    # RHN credentials are only needed for RHEL images in the SERVER SPEC
    [ -z "$RHN_CREDENTIALS_SPEC" ] || local RHN_CREDENTIALS_ARG="-e $RHN_CREDENTIALS_SPEC"

    openstack stack create \
              -e ${SERVER_SPEC} \
              ${RHN_CREDENTIALS_ARG} \
              --parameter external_network=${NETWORK_NAME} \
              --parameter domain_name=${ZONE} \
              --parameter slave_count=${SLAVES} \
              --parameter dns_forwarders=${FORWARDERS} \
              --parameter ssh_key_name=${SSH_KEY_NAME} \
              -t dns_service.yaml ${STACK_NAME}
}

function stack_status() {
		openstack stack show $1 -f json | jq '.stack_status' | tr -d \"
}

function stack_complete() {
		local STATUS=$(stack_status $1)
		[ ${STATUS} == 'CREATE_COMPLETE' -o ${STATUS} == 'CREATE_FAILED' ]
}

function ssh_user_from_stack() {
  openstack stack show $1 -f json | jq '.parameters.ssh_user'
}

function generate_inventory() {
    # Write a YAML file as input to jinja to create the inventory
    # master and slave name/ip information comes from OSP

		F=$(echo $FORWARDERS | sed -e 's/,/", "/g' -e 's/^/"/' -e 's/$/"/')
		
    (
        cat <<EOF
contact: "${ZONE_CONTACT}"
forwarders: [ ${F} ]
update_key: ${DNS_UPDATE_KEY}
EOF
         python bin/stack_data.py --zone osp10.e2e.bos.redhat.com
    ) > stack_data.yaml
		jinja2-2.7 inventory.j2 stack_data.yaml > inventory
    
}

function configure_dns_services() {
		SSH_USER_NAME=$(ssh_user_from_stack ${STACK_NAME})

		export ANSIBLE_HOST_KEY_CHECKING=False
		ansible-playbook \
				-i inventory \
				--become --user ${SSH_USER_NAME} \
				--private-key ${PRIVATE_KEY_FILE} \
				../dns-service-playbooks/playbooks/bind-server.yml
}

# =============================================================================
# MAIN
# =============================================================================

parse_args $@

set_defaults

create_stack

retry stack_complete ${STACK_NAME}

if [ $(stack_status ${STACK_NAME}) == "CREATE_FAILED" ] ; then
		echo "Create failed"
		exit 1
fi

generate_inventory

configure_dns_services
