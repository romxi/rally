#!/bin/bash
export OS_INTERFACE='admin'

# local vars
name_prefix=cvp
filename=${name_prefix}.manifest
rcfile=${name_prefix}rc
huge_pages=false
logfile=prepare.log

# Project, User, Roles
project=${name_prefix}.project
user=${name_prefix}.user
admin=${name_prefix}.admin
password=mcp1234

# Security group
sg_all=${name_prefix}.sg.all
sg_icmp=${name_prefix}.sg.icmp
sg_ssh=${name_prefix}.sg.ssh
sg_iperf=${name_prefix}.sg.perf

# Testkey
key=${name_prefix}_testkey

# Flavors: tiny, small (cirrus and migration), medium (ubuntu and volume/stress activities)
flavor_t=${name_prefix}.tiny
flavor_s=${name_prefix}.small
flavor_m=${name_prefix}.medium

# Fixed Networks (2, for testing router interconnection)
net_left=${name_prefix}.net.1
net_right=${name_prefix}.net.2
subnet1=${name_prefix}.subnet.1
subnet2=${name_prefix}.subnet.2

# Router
router=${name_prefix}.router

# Images: cirros (3.5, 4.0), ubuntu (16.04)
cirros3=${name_prefix}.cirros.35
cirros4=${name_prefix}.cirros.40
ubuntu16=${name_prefix}.ubuntu.1604

cirros3_link=http://download.cirros-cloud.net/0.3.5/cirros-0.3.5-x86_64-disk.img
cirros4_link=http://download.cirros-cloud.net/0.4.0/cirros-0.4.0-aarch64-disk.img
ubuntu16_link=https://cloud-images.ubuntu.com/xenial/current/xenial-server-cloudimg-amd64-disk1.img

# Volume (2GB)
volume=${name_prefix}.volume

function show_help {
    printf "CVP Pipeline: Resource creation script\n\t-h, -?\t\tShow this help\n"
    printf "\t-H\t\tAdds '--property hw:mem_page_size=large' to flavors, i.e. huge_pages for DPDK\n"
    printf "\t-w <path>\tSets working folder"
}

OPTIND=1 # Reset in case getopts has been used previously in the shell.
while getopts "h?:Hw:" opt; do
    case "$opt" in
    h|\?)
        show_help
        exit 0
        ;;
    w)  working_folder=${OPTARG}
        printf "# Working folder is ${working_folder}\n"
        ;;
    h)  huge_pages=true
        printf "# Using 'huge_pages' property in flavors\n"
        ;;
    esac
done

shift $((OPTIND-1))
[ "${1:-}" = "--" ] && shift

function put() {
    echo "$1=$2" | tee -a ${filename}
}

# now, some hard to understand stuff...
# f1 $(<command with output to cut>)
function f1() { echo $1 | cut -d' ' -f1; };
# <commands with output to cut> | p1
function p1() { while read input; do echo ${input} | cut -d' ' -f1; done; };
# ol1 is short for openstack list with 1 param. Also grep and cut
# "ol1 network public" will list all networks, grep by name public and return IDs
function ol1() { echo $(openstack $1 list -c ID -c Name -f value | grep $2 | cut -d' ' -f1); }
# same as ol1 but with 2 initial commands before list
function ol2() { echo $(openstack $1 $2 list -c ID -c Name -f value | grep $3 | cut -d' ' -f1); }

function print_manifest() {
    touch ./${filename}
    truncate -s 0 ${filename}
    printf "\n\n# Checking and filling manifest: $(pwd)/${filename}\n"
    put project_name ${project}
    put project_id $(ol1 project ${project})
    put user_name ${user}
    put user_id $(ol1 user ${user})
    put admin_name ${admin}
    put admin_id $(ol1 user ${admin})
    # sg
    put secgroup_all_name ${sg_all}
    put secgroup_all_id $(ol2 security group ${sg_all})
    put secgroup_icmp_name ${sg_icmp}
    put secgroup_icmp_id $(ol2 security group ${sg_icmp})
    put secgroup_ssh_name ${sg_ssh}
    put secgroup_ssh_id $(ol2 security group ${sg_ssh})
    put secgroup_iperf_name ${sg_iperf}
    put secgroup_iperf_id $(ol2 security group ${sg_iperf})

    # keypair
    put keypair_name ${key}
    put keypair_id $(ol1 keypair ${key})

    # flavors
    put flavor_tiny_name ${flavor_t}
    put flavor_tiny_id $(ol1 flavor ${flavor_t})
    put flavor_small_name ${flavor_s}
    put flavor_small_id $(ol1 flavor ${flavor_s})
    put flavor_medium_name ${flavor_m}
    put flavor_medium_id $(ol1 flavor ${flavor_m})

    # fixed nets
    put fixed_net_left_name ${net_left}
    put fixed_net_left_id $(ol1 network ${net_left})
    put fixed_net_right_name ${net_right}
    put fixed_net_right_id $(ol1 network ${net_right})
    put fixed_net_left_subnet_name ${subnet1}
    put fixed_net_left_subnet_id $(openstack subnet list --network ${net_left} -c ID -f value | p1)
    put fixed_net_right_subnet_name ${subnet2}
    put fixed_net_right_subnet_id $(openstack subnet list --network ${net_right} -c ID -f value | p1)

    # router
    put router_name ${router}
    put router_id $(ol1 router ${router})

    # volumes
    put volume_name ${volume}
    put volume_id $(ol1 volume ${volume})

    # images
    put cirros35_name ${cirros3}
    put cirros35_id $(ol1 image ${cirros3})
    put cirros40_name ${cirros4}
    put cirros40_id $(ol1 image ${cirros4})
    put ubuntu16_name ${cirros3}
    put ubuntu16_id $(ol1 image ${ubuntu16})
}

# create rc file out of current ENV vars
function putrc() {
    printf "# Saving ${1} file\n"
    echo "export OS_IDENTITY_API_VERSION=${OS_IDENTITY_API_VERSION:-3}" >${1}
    echo "export OS_AUTH_URL=${OS_AUTH_URL}" >>${1}
    echo "export OS_PROJECT_DOMAIN_NAME=${OS_PROJECT_DOMAIN_NAME}" >>${1}
    echo "export OS_USER_DOMAIN_NAME=${OS_USER_DOMAIN_NAME}" >>${1}
    echo "export OS_PROJECT_NAME=${OS_PROJECT_NAME}" >>${1}
    echo "export OS_TENANT_NAME=${OS_TENANT_NAME}" >>${1}
    echo "export OS_USERNAME=${OS_USERNAME}" >>${1}
    echo "export OS_PASSWORD=${OS_PASSWORD}" >>${1}
    echo "export OS_REGION_NAME=${OS_REGION_NAME}" >>${1}
    echo "export OS_INTERFACE=${OS_INTERFACE}" >>${1}
    echo "export OS_ENDPOINT_TYPE=${OS_ENDPOINT_TYPE}" >>${1}
    echo "export OS_CACERT=${OS_CACERT}" >>${1}
}

# update ENV vars to newly created project
function updatesession() {
    export OS_PROJECT_NAME=${project}
    export OS_TENANT_NAME=${project}
    export OS_USERNAME=${admin}
    export OS_PASSWORD=${password}
}

function process_cmds() {
    if [ -s ${cmds} ]; then
        cat ${cmds} | tr '\n' '\0' | xargs -P 1 -n 1 -0 echo | tee /dev/tty | openstack -v 2>&1 >>${logfile}
        truncate -s 0 ${cmds}
    fi
}

function _project() {
    echo project create --description \"CVP Pipeline project\" ${project} >>${cmds}
    echo role add --user admin --project ${project} admin >>${cmds}
}

function _users() {
    echo user create --project ${project} --password ${password} ${user} >>${cmds}
    echo user create --project ${project} --password ${password} ${admin} >>${cmds}
    echo role add --user ${admin} --project ${project} admin >>${cmds}
}

function _sg_all() {
    echo security group create --project ${project} --description \"ICMP, SSH, iPerf, HTTP\" ${sg_all} >>${cmds}
    # icmp
    echo security group rule create --protocol icmp ${sg_all} >>${cmds}
    # ssh
    echo security group rule create --protocol tcp --dst-port 22 ${sg_all} >>${cmds}
    # iperf
    echo security group rule create --protocol tcp --dst-port 5001 ${sg_all} >>${cmds}
    # iperf3
    echo security group rule create --protocol tcp --dst-port 5201 ${sg_all} >>${cmds}
    # nc connectivity
    echo security group rule create --protocol tcp --dst-port 3000 ${sg_all} >>${cmds}
    # http
    echo security group rule create --protocol tcp --dst-port 80 ${sg_all} >>${cmds}
}

function _sg_icmp() {
    echo security group create --project ${project} --description \"ICMP\" ${sg_icmp} >>${cmds}
    echo security group rule create --protocol icmp ${sg_icmp} >>${cmds}
}

function _sg_ssh() {
    echo security group create --project ${project} --description \"ICMP, SSH\" ${sg_ssh} >>${cmds}
    # icmp
    echo security group rule create --protocol icmp ${sg_ssh} >>${cmds}
    # ssh
    echo security group rule create --protocol tcp --dst-port 22 ${sg_ssh} >>${cmds}
}

function _sg_iperf() {
    echo security group create --project ${project} --description \"ICMP, iPerf\" ${sg_iperf} >>${cmds}
    # icmp
    echo security group rule create --protocol icmp ${sg_iperf} >>${cmds}
    # iperf
    echo security group rule create --protocol tcp --dst-port 5001 ${sg_iperf} >>${cmds}
    # iperf3
    echo security group rule create --protocol tcp --dst-port 5201 ${sg_iperf} >>${cmds}
}

function create_keypair() {
    echo "# Creating keypair"
    openstack keypair create ${key} >${key}
    chmod 600 ${key}
    echo "-> created keyfile: $(pwd)/${key}"
}

function _flavors() {
    # huge paged flavors
    if [ "$huge_pages" = true ]; then
        echo flavor create --id 1 --ram 64 --disk 1 --vcpus 1 ${flavor_t} --property hw:mem_page_size=large >>${cmds}
        echo flavor create --id 1 --ram 256 --disk 2 --vcpus 1 ${flavor_s} --property hw:mem_page_size=large >>${cmds}
        echo flavor create --id 1 --ram 2048 --disk 5 --vcpus 2 ${flavor_m} --property hw:mem_page_size=large >>${cmds}
    else
        echo flavor create --ram 64 --disk 1 --vcpus 1 ${flavor_t} >>${cmds}
        echo flavor create --ram 256 --disk 2 --vcpus 1 ${flavor_s} >>${cmds}
        echo flavor create --ram 2048 --disk 5 --vcpus 2 ${flavor_m} >>${cmds}
    fi
}

function _volumes() {
    echo volume create --size 2 ${volume} >>${cmds}
}

function create_fixed_nets() {
    echo "# Creating fixed networks"
    echo network create --project ${project} ${net_left} >>${cmds}
    echo subnet create ${subnet1} --network ${net_left} --subnet-range 10.10.11.0/24 >>${cmds}
    echo network set --share ${net_left} >>${cmds}
    echo network create --project ${project} ${net_right} >>${cmds}
    echo subnet create ${subnet2} --network ${net_right} --subnet-range 10.10.12.0/24 >>${cmds}
    echo network set --share ${net_right} >>${cmds}
    process_cmds

    # get subnet ids
    subnet1_id=$(openstack subnet list --network ${net_left} -c ID -f value)
    subnet2_id=$(openstack subnet list --network ${net_right} -c ID -f value)

    echo router create --project ${project} ${router} >>${cmds}
    process_cmds

    router_id=$(openstack router list -c ID -c Name -f value | grep ${router} | cut -d' ' -f1)
    echo router add subnet ${router_id} ${subnet1_id} >>${cmds}
    echo router add subnet ${router_id} ${subnet2_id} >>${cmds}
    process_cmds

    # TODO: Search for external net
    external=ext-net
    echo router set ${router} --external-gateway ${external} >>${cmds}
    process_cmds
}

function _get_image() {
    # build vars for name and link
    name="${1}"
    link="${1}_link"
    which wget >/dev/nul
    if [ $? -ne 0 ]; then
        printf "\nERROR: 'wget' not detected. Download skipped: ${!name}\n"
    else
        # no redownloads, quet, save named and show progress
        r=$(wget --no-check-certificate -nc -q -O ./${!name} --show-progress ${!link})
        if [ $? -ne 0 ]; then
            # non-empty output on error
            echo ${r}
        fi
    fi
}

function create_image() {
    name="${1}"
    # Check if image is in the cloud
    echo "# Checking image '${!name}'"
    ids=( $(ol1 image ${!name}) )
    # if array is not empty, download and upload it
    if [ ${#ids[@]} -eq 0 ]; then
        # check and download
        if [ ! -f ${!name} ]; then
            r=$(_get_image ${1})
        else
            r=""
        fi
        # check if output is not empty
        if [ ${#r} -eq 0 ]; then
            image_id=$(openstack image create --public --disk-format qcow2 --container-format bare --file ${!name} ${!name} -c id -f value)
            echo "-> created ${!name} (${image_id})"
        else
            printf "\n-> Error detected, creation skipped\n"
        fi
    else
        # image(s) already there, list them
        for id in ${ids[@]}; do
            echo "-> found ${!name} with ID of '${id}'"
        done
    fi
}

###################
### Main
###################
if [[ -z ${working_folder+x} ]]; then
    # cwd into working dir
    cd ${working_folder}
fi

cmds=$(mktemp)
trap "rm -f ${cmds}" EXIT
echo "Using tempfile: '${cmds}'"

touch ${logfile}
echo "Using log file: '${logfile}'"

# Create
echo "# Creating project and users"
_project
_users
process_cmds

echo "# Creating 'rc' and switching"
putrc "./adminrc"
updatesession
putrc "./${rcfile}"

echo "# Creating basic resources"
# not dependent stuff
_sg_all
_sg_icmp
_sg_ssh
_sg_iperf
_flavors
_volumes
process_cmds

# sophisticated, step dependent stuff
create_keypair
create_fixed_nets

# images
create_image cirros3
create_image cirros4
create_image ubuntu16

### Manifest and fall back to original rc
print_manifest
source "./adminrc"
printf "\n\nOriginal rc preserved and backed up in 'adminrc'\nNew rc is '${rcfile}'\n"