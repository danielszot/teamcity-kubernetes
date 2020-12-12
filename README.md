Work in progress...

# teamcity-kubernetes
Set of yaml files to make TeamCity work in HA mode on Kubernetes.

# Prerequisities
* mount.nfs4 on host
* NFS share available

# How to
1. Define secrets in .env. There is a sample file avaliable .env.sample.
2. Load env vars to run environment.
3. Run k8s handle

# remarks
* mysql writes should always be done using mysql-0.mysql service to use master node
* For cache there is local volume created 

# TODO:
* Replicated MySQL, using folowing method: https://kubernetes.io/docs/tasks/run-application/run-replicated-stateful-application/
* Network security policies
* ServiceAccount and RBAC
* Secondary node
* Minio
* Configure to store artifacts in Minio