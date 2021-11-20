# Kinda' help to Kind

**NOTE**: This tool is still a work in progress. 

## What is it for
This tiny tool is nothing but a small helper tool to spin up kind based kubernetes clusters on *LINUX* operating system. With using this script you will be able to create the necessary `config.yaml` file for kind.

## Pre-requisites
:raised_back_of_hand: Before using this you need to have installed the followings:

- :point_right: [Docker](https://www.docker.com/)
- :point_right: [Kubectl](https://kubernetes.io/docs/tasks/tools/)
- :point_right: [Kind](https://kind.sigs.k8s.io) - Kubernetes in Docker

## How to use it

1. clone this repository
2. run the script

```console
git checkout https://github.com/frenkdefrog/kind.git 
./generate_and_startcluster.sh
```
:warning: Please mind that the user running this script has to have a **sudo** permission, since it will create and use some directories in **/srv**

Running the script without any arguments will create a config yaml file and will start a cluster with the name of **kind**. 
It will also create a new directory in **/srv** with the name of the cluster name. It is to have the possibility to create and use persistent volumes within the cluster. Every data is going to be stored in **/srv/_clustername_**


### Usable arguments
**-n**: passing this argument with a value can be used to name the new cluster
```console
./generate_and_startcluster.sh -n testcluster
```
**-w**: how many worker node should be created.
```console
./generate_and_startcluster.sh -w 3
```
**-p**: what port should be associated to apiServer to listen on
```console
./generate_and_startcluster.sh -p 6443
```
**-e**: what extra ports should be associated to the cluster. It must be a comma separated list without a whitespace
```console
./generate_and_startcluster.sh -e 80,443
```
**-r**: it will define if a local docker registry should be created and used with the cluster. If there is no registry existing, it will create one with the name you set up in the script as variable. Default is: kind-registry. It will use the default tcp port 5000. The relevant directories are going to be crated in **/srv** directory. Since it will use a default, basic authentication, therefore, **apache2-utils** should be used to create the necessary htpassword file. If there is no **registry.password** file represented in **/srv/__registrydirectory_/auth** directory, the script will create it.
```console
./generate_and_startcluster.sh -r
```
**-i**: if one would reach the kind cluster remotely (although it is strongly contraindicated), it can be done by passing the network interface's name of the system. In this case, the apiServer will listen on that IP address what this interface has.
:warning: Make sure, that the port set up with *-p* argument is opened in firewall.
```console
./generate_and_startcluster.sh -i eth0 -p 6443
```

To create a cluster with 3 worker nodes, *testcluster* name, listening on eth0 interface's ip address on 6443 TCP port, associating port 80 and 443 to cluster and adding a local docker registry can be done by the following command:

```console
./generate_and_startcluster.sh -n testcluster -w 3 -i eth0 -p 6443 -e 80,443 -r
```
This will produce the following output:
```console
./generate_and_startcluster.sh -n testcluster -w 3 -i eth0 -p 6443 -e 80,443 -r
eth0: error fetching interface information: Device not found
Checking for apache2-utils: install ok installed
It looks like there is no any password file (/srv/docker/local_registry/auth/registry.password) represented in the target directory. Do you want to create a user now? [y,n]
y
Give me a new user's name:
test
New password: 
Re-type new password: 
Adding password for user test
9434e72f53c1380f85bec975c89b4ccba3f613992a338bc3d62bdbfd25e2a7ea
Creating cluster "testcluster" ...
 ✓ Ensuring node image (kindest/node:v1.21.1) 🖼 
 ✓ Preparing nodes 📦 📦 📦 📦  
 ✓ Writing configuration 📜 
 ✓ Starting control-plane 🕹️ 
 ✓ Installing CNI 🔌 
 ✓ Installing StorageClass 💾 
 ✓ Joining worker nodes 🚜 
Set kubectl context to "kind-testcluster"
You can now use your cluster with:

kubectl cluster-info --context kind-testcluster

Not sure what to do next? 😅  Check out https://kind.sigs.k8s.io/docs/user/quick-start/
configmap/local-registry-hosting created



The kubeconfig's content for remote address
====================================================================
apiVersion: v1
clusters:
...

====================================================================

```
If you would like to access the cluster remotely, you need to copy the output starting **apiVersion: v1** til the last row before the double line, and paste the content into your local **~/.kube/config** file. :warning: Don't forget to make a backup before altering your config file.

Checking the running docker container you should see the following kind-cluster related containers:
```console
$ docker ps
CONTAINER ID   IMAGE                  COMMAND                  CREATED         STATUS         PORTS                                                                NAMES
e68e41c40da2   kindest/node:v1.21.1   "/usr/local/bin/entr…"   4 minutes ago   Up 4 minutes   0.0.0.0:80->80/tcp, 0.0.0.0:443->443/tcp, 127.0.0.1:6443->6443/tcp   testcluster-control-plane
f2c1a7d2a940   kindest/node:v1.21.1   "/usr/local/bin/entr…"   4 minutes ago   Up 4 minutes                                                                        testcluster-worker2
e1dea50714af   kindest/node:v1.21.1   "/usr/local/bin/entr…"   4 minutes ago   Up 4 minutes                                                                        testcluster-worker3
e8d28e6703a1   kindest/node:v1.21.1   "/usr/local/bin/entr…"   4 minutes ago   Up 4 minutes                                                                        testcluster-worker
9434e72f53c1   registry:2             "/entrypoint.sh /etc…"   4 minutes ago   Up 4 minutes   127.0.0.1:5000->5000/tcp                                             kind-registry
```

Checking the created kind cluster you should see the following output:
```console
$ kind get clusters
testcluster

```



### Default variables
These variable can be changed in the generate_and_startcluster.sh script.

**DOCKER_DIR="/srv/docker"**: this variable will define the directory where the cluster and local registry data will be stored. If the use running this script with no **sudo** permissions, this should be changed!

**VERSION="v1.21.1"**: what kubernetes image version should be use by kind

**LOCAL_REGISTRY_DIR="${DOCKER_DIR}/local_registry"**: the directory name where the local_registry related data will be stored

**LOCAL_REGISTRY_NAME='kind-registry'**: what name should be  used by the local_registry.

**LOCAL_REGISTRY_PORT='5000'**: what port should be used by the local_registry