echo "Update /etc/hosts with IP of nodes"
cat >>/etc/hosts<<EOF
172.18.8.99 nfs-server
172.18.8.101 k8s-1
172.18.8.102 k8s-2
172.18.8.103 k8s-3
EOF

echo "Install NFS"
yes | sudo apt install nfs-kernel-server

echo "Create share directories to store data and db files"
mkdir -p /srv/nfs/data
mkdir -p /srv/nfs/data/config
mkdir -p /srv/nfs/db

echo "Update the shared folder access"
chmod -R 777 /srv/nfs
chown -R 1000:1000 /srv/nfs

echo "Make the kubedata directory available on the network"
cat >>/etc/exports<<EOF
/srv/nfs    *(rw,sync,no_subtree_check,no_root_squash)
EOF

echo "Export the updates"
sudo exportfs -a

echo "Restart NFS server"
sudo systemctl restart nfs-kernel-server