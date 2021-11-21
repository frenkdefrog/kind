#!/usr/bin/env bash

# This script is a small tool for making easier to spin up kind kubernetes cluster with docker in your local.
# Please mind, that having a Docker installed is a prerequisity.
# It can handle the following arguments and options:
# -h prints the help
# -w number: how many worker nodes should be added to the cluster
# -n test: what should be the name of the newly created cluster
# -i eth0: what is the network interface that's IP address should be used for apiServer. It should be ONLY used, when you would like to provide remote access to this cluster for TESTING purposes. Otherwise don't provide it, the local lo interface and address will be used.
# -p 6443: what is the port number the apiServer should listen on. It can be useful if you would like to let remote access to this kind cluster. Otherwise don't provide it, therefore, a random port number will be used.
# -r: by passing this parameter a local docker-registry can be created and attached to the local kind cluster.
# -e 80,443: you can pass those ports you would like to map/forward to the cluster


#======================================================================#
#===========================FUNCTIONS==================================#
#======================================================================#


show_help () {
   # Display Help
   echo
   echo "This script helps you to create a kind kubernetes kluster with options"
   echo
   echo "Syntax: createCluster [-h|n|i|p]"
   echo "options:"
   echo "-h     Print this Help."
   echo "-w     The number of the workers"
   echo "-i     Interface name of your local. The kind cluster serverApi will listen on its ip address"
   echo "-p     The port number the serverApi will listen on."
   echo "-n     The name of your cluster."
   echo "-r     Create/connect to a docker registry for the cluster. It will be created with the name of kind-registry and will listen on port 5000."
   echo "       If you would like to create a registry, plese make sure that the prerequisites are presented:"
   echo "       1. apache2-utils is installed"
   echo "       2. you created a directory for the registry data in /srv/docker/local_registry/{data,auth}"
   echo "       3. you created at least on username and password using apache2-utils, and the .htpasswd file is located in /srv/docker/local_registry/auth"
   echo "         htpasswd -Bc /srv/docker/local_registry/auth/registry.password [username]"
   echo "-e     You can pass all those TCP ports here separated by comma  you would like to map to the cluster"
   echo "If none of this paramaters are set up, then the cluster will have the default values. (name=kind, ipAddress: 127.0.0.1, port: random number)"
   echo
   exit 0
}


check_dockerdir(){
    if [ ! -d "${DOCKER_DIR}" ]; then
        sudo mkdir ${DOCKER_DIR}
        sudo chown -R ${USER}:docker ${DOCKER_DIR}
    fi
}

create_registry (){

    #checking if apache2-utils is represented. If not, it tries to install it, otherwise docker registry auth can not be set.
	pkg_ok=$(dpkg-query -W --showformat='${Status}\n' ${REQUIRED_PKG}|grep "install ok installed")
	echo Checking for ${REQUIRED_PKG}: ${pkg_ok}
	if [ "" = "${pkg_ok}" ]; then
		echo "No ${REQUIRED_PKG}. Would you like me to set up ${REQUIRED_PKG}. [y,n]"
		read answer
		if [[ ${answer} == "Y" || ${answer} == "y" ]]; then
			sudo apt-get --yes install ${REQUIRED_PKG}
		else
			echo "Without this package is is not possible to secure the registry. Exiting...."
			exit 1
		fi
	fi

    # checking the necessary dirs. If they are not existing, it tries to create them.
	for i in 'auth' 'data';
		do
			if [ ! -d "${LOCAL_REGISTRY_DIR}/${i}" ] ; then
				mkdir -p ${LOCAL_REGISTRY_DIR}/${i}
			fi
	done

    #checking if any registry.password file is existing. If not, it tries to create one and add a user.
	password_file="${LOCAL_REGISTRY_DIR}/auth/registry.password"
	if [ ! -f "$password_file" ]; then
		echo "It looks like there is no any password file (${password_file}) represented in the target directory. Do you want to create a user now? [y,n]"
		read answer
		if [[ ${answer} == "Y" || ${answer} == "y" ]]; then
		  echo "Give me a new user's name:"
			read username
			htpasswd -Bc ${password_file} ${username}
		else
			echo "In this case, please make sure that you will create a username-password in ${password_file} then re-run this script! Exiting..."
			exit 1		
		fi
	fi

	
    # create registry container unless it already exists
	running="$(docker inspect -f '{{.State.Running}}' "${LOCAL_REGISTRY_NAME}" 2>/dev/null || true)"
	if [ "${running}" != 'true' ]; then
	  docker run \
	    -d --restart=always \
	    -p "127.0.0.1:${LOCAL_REGISTRY_PORT}:5000" \
	    --name "${LOCAL_REGISTRY_NAME}" \
	    -v "${LOCAL_REGISTRY_DIR}/data:/data" \
	    -v "${LOCAL_REGISTRY_DIR}/auth:/auth" \
	    -e "REGISTRY_STORAGE_FILESYSTEM_ROOTDIRECTORY=/data" \
	    -e "REGISTRY_AUTH=htpasswd" \
	    -e "REGISTRY_AUTH_HTPASSWD_REALM=Registry" \
	    -e "REGISTRY_AUTH_HTPASSWD_PATH=/auth/registry.password" \
	    registry:2
	fi
}


create_workers (){
if [[ ! -z ${WORKERS} && "${WORKERS}" -gt "0" ]]; then
    for i in $(seq 1 ${WORKERS})
        do
            cat << EOF >> ${CONFIG_YAML}
- role: worker
  image: kindest/node:${VERSION}
  extraMounts:
    - hostPath: ${DOCKER_DIR}/${CLUSTERNAME}
      containerPath: /kube
EOF
        done
fi
}


create_controlplane (){
cat << EOF >> ${CONFIG_YAML}
- role: control-plane
  image: kindest/node:${VERSION}
  extraMounts:
    - hostPath: ${DOCKER_DIR}/${CLUSTERNAME}
      containerPath: /kube
EOF
if [ ! -z $PORTSMAPPING ]; then
cat << EOF >> ${CONFIG_YAML}
  kubeadmConfigPatches:
  - |
    kind: InitConfiguration
    nodeRegistration:
      kubeletExtraArgs:
        node-labels: "ingress-ready=true"
  extraPortMappings:
EOF

for i in ${PORTSMAPPING//,/ }
    do
    cat << EOF >> ${CONFIG_YAML}
  - containerPort: ${i}
    hostPort: ${i}
    protocol: TCP
EOF
done
fi


}

create_configyaml(){
cat << EOF > ${CONFIG_YAML}
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
EOF

if [ ! -z ${IFACE} ] || [ ! -z ${PORTNUMBER} ]; then
cat << EOF >> ${CONFIG_YAML}
networking:
EOF
if [ ! -z ${IFACE} ]; then
  cat << EOF >> ${CONFIG_YAML}
  apiServerAddress: "$(ifconfig ${IFACE} | grep -oP '(?<=inet\s)([0-9]{1,3}\.){3}[0-9]{1,3}(=?)')"
EOF
fi
if [ ! -z ${PORTNUMBER} ]; then
  cat << EOF >> ${CONFIG_YAML}
  apiServerPort: ${PORTNUMBER}
EOF
fi
fi

if [ ! -z ${REGISTRY} ]; then
    cat << EOF >> ${CONFIG_YAML}
containerdConfigPatches:
- |-
  [plugins."io.containerd.grpc.v1.cri".registry.mirrors."localhost:${LOCAL_REGISTRY_PORT}"]
    endpoint = ["http://${LOCAL_REGISTRY_NAME}:5000"]
EOF
    create_registry ${DOCKER_DIR}
fi

cat << EOF >> ${CONFIG_YAML}
nodes:
EOF

}


apply_registry_configmap(){

#connect the registry to the cluster network, if it needs to be done
if [ ! -z ${REGISTRY} ]; then

docker network connect "kind" "${LOCAL_REGISTRY_NAME}" || true

cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: local-registry-hosting
  namespace: kube-public
data:
  localRegistryHosting.v1: |
    host: "localhost:${LOCAL_REGISTRY_PORT}"
    help: "https://kind.sigs.k8s.io/docs/user/local-registry/"
EOF
fi

}
#=======================================================================================#
#===================================== MAIN PART========================================#
#=======================================================================================#

# checking the main components
DOCKER_DIR="/srv/docker"
VERSION="v1.21.1"
REQUIRED_PKG="apache2-utils"
LOCAL_REGISTRY_DIR="${DOCKER_DIR}/local_registry"
LOCAL_REGISTRY_NAME='kind-registry'
LOCAL_REGISTRY_PORT='5000'


while getopts e:n:w:i:p:hr flag
do
    case "${flag}" in
        n) CLUSTERNAME=${OPTARG};;
        i) IFACE=${OPTARG};;
        p) PORTNUMBER=${OPTARG};;
        w) WORKERS=${OPTARG} ;;
    	h) show_help ;;
	    r) REGISTRY=1 ;;
        e) PORTSMAPPING=${OPTARG} ;;
    esac
done



if [ -z ${CLUSTERNAME} ]; then
	CLUSTERNAME="kind"
fi

# checking if docker dir exists as it would be necessary for PV
check_dockerdir

if [ ! -d ${DOCKER_DIR}/${CLUSTERNAME} ]; then
  mkdir ${DOCKER_DIR}/${CLUSTERNAME}
fi


# creating the config file yaml
CONFIG_YAML=${CLUSTERNAME}'_config.yaml'
create_configyaml
create_controlplane
create_workers

# starting the cluster
kind create cluster --name ${CLUSTERNAME} --config=$CONFIG_YAML
if [ "$?" -ne "0" ]; then
    echo 
    UNICORN='\U1F984';
    echo -e "Oops, the ${UNICORN} is sad because something bad happened. Check the logs, fix the issue and try to rerun this script again... Exiting..."
    exit 1
fi
# adding the registry to the cluster
apply_registry_configmap


echo 
echo
echo 
echo "The kubeconfig's content for remote address"
echo "===================================================================="
cat ~/.kube/config 
echo "===================================================================="

for i in {1..5}; do
    echo
done

echo "Would you like to deploy Nginx-Ingress to the cluster? [y,n]"
read nginx
if [[ "${nginx}" == "Y" || "${nginx}" == "y" ]]; then
    ./components/ingress-nginx/setup-ingress.sh
fi
