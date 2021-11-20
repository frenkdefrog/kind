#!/bin/bash

# This script is a small tool for making easier to spin up kind kubernetes cluster with docker in your local.
# Please mind, that having a Docker installed is a prerequisity.
# It can handle the following arguments and options:
# -n test: what should be the name of the newly created cluster
# -i eth0: what is the network interface that's IP address should be used for apiServer. It should be ONLY used, when you would like to provide remote access to this cluster for TESTING purposes. Otherwise don't provide it, the local lo interface and address will be used.
# -p 6443: what is the port number the apiServer should listen on. It can be useful if you would like to let remote access to this kind cluster. Otherwise don't provide it, therefore, a random port number will be used.
# -r: by passing this parameter a local docker-registry can be created and attached to the local kind cluster.


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
   echo "h     Print this Help."
   echo "i     Interface name of your local. The kind cluster serverApi will listen on its ip address"
   echo "p     The port number the serverApi will listen on."
   echo "n     The name of your cluster."
   echo "r     Create/connect to a docker registry for the cluster. It will be created with the name of kind-registry and will listen on port 5000."
   echo "      If you would like to create a registry, plese make sure that the prerequisites are presented:"
   echo "      1. apache2-utils is installed"
   echo "      2. you created a directory for the registry data in /srv/docker/local_registry/{data,auth}"
   echo "      3. you created at least on username and password using apache2-utils, and the .htpasswd file is located in /srv/docker/local_registry/auth"
   echo "         htpasswd -Bc /srv/docker/local_registry/auth/registry.password [username]"
   echo
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

    # setting local variables
	reg_name='kind-registry'
	reg_port='5000'

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


#=======================================================================================#
#===================================== MAIN PART========================================#
#=======================================================================================#

#checking the main components
DOCKER_DIR="/srv/docker"
VERSION="v1.20.2"
REQUIRED_PKG="apache2-utils"
LOCAL_REGISTRY_DIR="${DOCKER_DIR}/local_registry"
LOCAL_REGISTRY_NAME='kind-registry'
LOCAL_REGISTRY_PORT='5000'


check_dockerdir

while getopts n:i:p:hr flag
do
    case "${flag}" in
        n) clustername=${OPTARG};;
        i) iface=${OPTARG};;
        p) portnumber=${OPTARG};;
	h) help ;;
	r) registry=1 ;;
    esac
done

if [ -z ${clustername} ]; then
	clustername="kind"
fi

#creating the config file yaml
var=${clustername}'_config.yaml'

cat << EOF > ${var}
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
EOF

if [ ! -z ${iface} ] || [ ! -z ${portnumber} ]; then
cat << EOF >> ${var}
networking:
EOF
if [ ! -z ${iface} ]; then
  cat << EOF >> ${var}
  apiServerAddress: "$(ifconfig ${iface} | grep -oP '(?<=inet\s)([0-9]{1,3}\.){3}[0-9]{1,3}(=?)')"
EOF
fi
if [ ! -z ${portnumber} ]; then
  cat << EOF >> ${var}
  apiServerPort: ${portnumber}
EOF
fi
fi

if [ ! -z $registry ]; then
    cat << EOF >> ${var}
containerdConfigPatches:
- |-
  [plugins."io.containerd.grpc.v1.cri".registry.mirrors."localhost:${LOCAL_REGISTRY_PORT}"]
    endpoint = ["http://${LOCAL_REGISTRY_NAME}:5000"]
EOF
    create_registry ${DOCKER_DIR}
fi

cat << EOF >> ${var}
nodes:
- role: control-plane
  image: kindest/node:${VERSION}
  kubeadmConfigPatches:
  - |
    kind: InitConfiguration
    nodeRegistration:
      kubeletExtraArgs:
        node-labels: "ingress-ready=true"
  extraPortMappings:
  - containerPort: 80
    hostPort: 80
    protocol: TCP
  - containerPort: 443
    hostPort: 443
    protocol: TCP
EOF

if [ ! -d ${DOCKER_DIR}/${clustername} ]; then
  mkdir ${DOCKER_DIR}/${clustername}
fi

cat << EOF >> ${var}
  extraMounts:
    - hostPath: ${DOCKER_DIR}/${clustername}
      containerPath: /kube
EOF

#starting the cluster
kind create cluster --name ${clustername} --config=$var

#connect the registry to the cluster network, if it needs to be done
if [ ! -z ${registry} ]; then

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


echo 
echo
echo 
echo "The kubeconfig's content for remote address"
echo "===================================================================="
cat ~/.kube/config 
echo "===================================================================="

