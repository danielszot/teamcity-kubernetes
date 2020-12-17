# TeamCity for Kuberenetes
Intention for this repository is to provide complete example how to properly setup Teamcity for Kubernetes, 
make it High Available and use Minio as a storage for generated build artefacts.

# Initial remarks
Repository includes examples how storage volumes could be setup. This is not the common practice
to include PersistentVolumes objects, since user that will use the files could not have an
access to create such (it is even recommended to do not in
[Kubernetes docs](https://kubernetes.io/docs/concepts/storage/persistent-volumes/#writing-portable-configuration)).
Anyway, this repo should be considered as exemplary so all needed files are provided.

There are no cloud related resources used anywhere in the repo because it is prepared to work with
on-premises infrastructure.

# Cluster setup
To run an example locally one can prepare the cluster using provided Vagrantfile together with Kubespray.
The Vagrantfile is modified version of one included in Kubespray repository. This one includes:
* an additional VM to work as the NFS server (shared data directory for TeamCity), 
* inline shell provisioner to create directories needed for Minio's PersistentVolumes,
* mount.nfs4 installed on cluster nodes to let them mount NFS shares.

## Steps to set up the cluster

```
# Clone Kubespray into ./kubespray
git clone https://github.com/kubernetes-sigs/kubespray.git`

# Copy ./Vagrantfile to ./kubespray/Vagrantfile
cp ./Vagrantfile ./kubespray/Vagrantfile

# Start cluster
cd ./kubespray
vagrant up
cd ..
```

During the cluster provisioning admin.conf was generated. The file is needed to connect to the cluster by `kubectl`.
Let's export an env variable used by `kubectl` to reference it:

```
# !! Run the command from this repository root directory
export KUBECONFIG=$(pwd)/kubespray/inventory/sample/artifacts/admin.conf
```

Then verify if it works. After executing `kubectl get nodes` it should look like on below listing:

```
$ kubectl get nodes
NAME    STATUS   ROLES    AGE   VERSION
k8s-1   Ready    master   6d    v1.19.4
k8s-2   Ready    master   6d    v1.19.4
k8s-3   Ready    <none>   6d    v1.19.4
```

# Prerequisites

Several prerequisites needs to be met before we will be able to start.

## Cluster prerequisites
When provided cluster setup will be used, all cluster related requirements will be fulfilled.
In other case cluster will need to have:
* mount.nfs4 installed on all cluster nodes 
  (or at least group of nodes where scheduling TeamCity StatefulSets is allowed),
* NFS share available to store shared data.

## Minio operator
To setup Minio, the official Minio operator will be used. It is required to install it first for 
`kubectl`. Krew is the plugin manager for `kubectl` that can be used for that.

Follow guidelines to install Krew: https://krew.sigs.k8s.io/docs/user-guide/setup/install/

Execute below command to initiate Minio operator in the cluster.

`kubectl krew install minio`

Minio operator will reside in `default` namespace. 
The Tenant and all other needed objects will reside in the "minio" namespace.

## Install k8s-handle

All objects templates and config are prepared to work with k8s-handle tool which 
is needed to be installed in the system.

Follow steps from documentation to install locally: 
https://github.com/2gis/k8s-handle/blob/master/README.md#installation-with-pip

# Stack deployment "how-to"

All needed secrets are not stored in the configuration file to do not store the values in the
repository. Exemplary values are provided in `.env.sample`. Please modify them and then source to
the terminar session from where k8s-handle will be then called.

`source .env.sample`

If dockerized version of k8s-handle tool will be used one can delete `export ` words from 
the line beginnings in the file and then use it as an env file.

Next step is to adjust values from [config.yaml](./config.yaml) file.

After adjustments were done, k8s-handle can be called to deploy the stack:

`k8s-handle deploy -s=vagrant --use-kubeconfig`

It could be also used with tags to deploy service by service:

```
k8s-handle deploy -s=vagrant --use-kubeconfig --tags=mysql
k8s-handle deploy -s=vagrant --use-kubeconfig --tags=minio
k8s-handle deploy -s=vagrant --use-kubeconfig --tags=teamcity
```

# Stack remarks

## Maintenance access

TeamCity doesn't have `/healthz` like style health check endpoint (https://youtrack.jetbrains.com/issue/TW-62305).
During the maintenance mode (before connectiong to database, or after upgrade which needs database to be migrated)
TeamCity responds with 5xx error codes, then readiness probe fails and sets Pod to NotReady
state. As a consequence, an endpoint with the Pods IP is removed from the service and TeamCity becomes unavailable
for a maintainer. The problem is addressed by introducing dedicated paths to Ingress controller
that allows maintainer to access each TeamCity node even when it's not ready from readiness probe perspective.

The primary node is available via: `http://{{ cluster-ip or fqdn }}/maintenance/primary`
The secondary nodes are available via: `http://{{ cluster-ip or fqdn }}/maintenance/secondary/{{ node-id }}`.

## Object storage for artefacts

Minio is being used to store build artefacts. It's project configuration setting in TeamCity so it needs to be
configured manually after TeamCity installation. 

Please use following address as minio server name: `http://minio.minio.svc`

Buckets are created during the deployment accordingly to list provided in [config.yaml](config.yaml).

### Production ready considerations
Minio is configured without any (even self signed) TLS certificates. To make TeamCity to work with self signed
certs the keystore needs to be generated with the self signed certificate and passed as a default keystore
to be used by TeamCity. When production installation of Minio will be used, certificates will probably be already
issued by trusted authority so will be able to be used in TeamCity without any additional steps.

## Agents

There are no objects defined for TeamCity agents. Instead Kubernetes plugin can be used to automatically spin up an Agent
when needed.

### Production ready considerations
Right now TeamCity can be authorised to Kubernetes API by using certificate from generated `admin.conf` file.
This is not a good solution for production installations. In the prodution case the ServiceAccount should
be created for TeamCity with proper ClusterRole bound to it.

## Ingress controller production considerations

There is no TLS certificate passed to IngressController to make it work as HTTPS. 

There are at least two solutions for production clusters available:
* external LB with TLS termination,
* internal TLS termination by ingress controller can be perormed after passing the generated cert.

For development purposes, Ingress controller can be forced to use fake ACME certificate.

Main service targets both primary and secondary nodes. Even if the primary node is healthy,
the round-robin algorithm is used to balance the traffic. As a consequence half of the requests targets
the secondary node, which is read only. More advanced method with services failover should be used, like:
* separated reverse proxy handling the problem running in another Pod,
* Istio or Skipper.

## Mysql

To maintain example simplicity MySQL works without any kind of replication.
There is just one master node. To make it easy to extend mysql installation with read only slaves, 
TeamCity is configured to use mysql-0.mysql service to connect to the MySQL database to be able to
execute writes on a database.

This approach can be used to set up MySQL with replication: 
https://kubernetes.io/docs/tasks/run-application/run-replicated-stateful-application/

## The secondary node dedicated storage

EmptyDir type of volume is used as a secondary node dedicated local storage. 
Documentation says that mostly the logs and caches are stored there, but it should be confirmed
before going to production.

# TODO:
- [x] Create bucket automatically
- [x] Separated Statefulset with secondary node and PVC for the node
- [ ] Add network security policies to limit in-cluster connections to only needed ones
- [ ] Add ServiceAccount and RBAC to access Kubernetes API by TeamCity to spin up Agents.
- [ ] Define resource limits for minio
- [ ] Use advanced service handling with eg. Istio or to handle failover of main Teamcity service.