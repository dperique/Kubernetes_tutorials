# Kubespray: Kubernetes Cluster Operations

## Introduction

We use kubespray for creating Kubernetes clusters and it has worked out quite well
for a while.  However, once a Kubernetes cluster is built, we will eventually want to
replace or increase the number of Kubernetes nodes for various reasons:

* A node died and we want to replace it
* A node needs to be upgraded to better hardware
* We want to upgrade Kubernetes one node at a time
  * this is so that we can upgrade the version of Kubernetes in the cluster without
    taking downtime of the running service the Kubernetes cluster provides
* We want to apply patches that were identified in a security scan to keep the node
  in compliance with security standards
  * this is so that we can upgrade the version of Kubernetes in the cluster without
    taking downtime of the running service the Kubernetes cluster provides
* We want to scale the cluster for more or less capacity

## Using kubespray release tags

We use kubespray by using a particular tag in the repo.  Certain tags equate to particular
Kubernetes versions as well as versions for the various components (e.g., calico, etcd, etc.).

## Recommendation: Save your certificates

I recommend saving the certificates from your Kubernetes nodes immeidately after it
goes into operation so that when you bootstrap
a replacement node, you put those certificates on the fresh machine before running
kubespray -- this will avoid any tls authentication issues.

I understand that kubespray may contain some tooling so that you really don't have
to save certificates but that is another area of research I have not gone through.

Here's roughly how I did it for my 6 node cluster and how I restored the certificates for
node 4:

```
## Copy the certificates and restore them.

for i in 1 2 3 4 5 6 ; do
  mkdir -p kube/node$i
  mkdir -p etcd/node$i
  mkdir -p share/node$i
done

j=1
for i in 236.111 236.206 236.229 236.133 236.220 237.34; do
  scp -i junk.rsa root@192.168.$i:/etc/kubernetes/ssl/* ./kube/node$j
  scp -i junk.rsa root@192.168.$i:/etc/ssl/etcd/ssl/* ./etcd/node$j
  scp -i junk.rsa root@192.168.$i:/usr/local/share/ca-certificates/* ./share/node$j
  j=$((j+1))
done

ssh node4
mkdir -p /etc/kubernetes/ssl/
mkdir -p /etc/ssl/etcd/ssl/
mkdir -p /usr/local/share/ca-certificates/

pushd kube/node4
scp -i ../../junk.rsa * root@192.168.236.133:/etc/kubernetes/ssl/
popd
pushd etcd/node4
scp -i ../../junk.rsa * root@192.168.236.133:/etc/ssl/etcd/ssl/
popd
pushd share/node4
scp -i ../../junk.rsa * root@192.168.236.133:/usr/local/share/ca-certificates
```

## Recommendation: backup your etcd database

Instructions on how to backup your etcd database are at: [etcd admin guide](https://coreos.com/etcd/docs/latest/v2/admin_guide.html)

More on this later.


## Replacing a Kubernetes etcd node

NOTE: We have been setting our kubespray inventory to use three masters and three etcd
nodes where the three masters are also etcd nodes.  Thus, replacing an etcd node equates
to also replacing a master node.

This link [Operating etcd clusters for Kubernetes](https://kubernetes.io/docs/tasks/administer-cluster/configure-upgrade-etcd/)
recommends having 5 etcd nodes in production.  Going forward, we intend to follow this
recommendation.

When we create Kubernetes clusters using kubespray, we set the inventory
to include three etcd nodes (in the `[etcd]` inventory group).

If one of them dies, we would like to replace it very soon because we know that
if another one dies, the etcd cluster will collapse.  The Kubernetes documentation
for etcd (see the link above) puts it like this:

```
If the majority of etcd members have permanently failed, the etcd cluster is
considered failed. In this scenario, Kubernetes cannot make any changes to its
current state. Although the scheduled pods might continue to run, no new pods
can be scheduled. In such cases, recover the etcd cluster and potentially
reconfigure Kubernetes API server to fix the issue.
```

NOTE: If your etcd cluster is down, `kubectl` will not work.

Replacing an etcd node, is the most complex scenario mostly because of the need for
some basic knowledge of etcd.  But after understanding some disaster recovery
steps for etcd clusters, it's really not that difficult.

This section [Replacing a failed etcd member](https://kubernetes.io/docs/tasks/administer-cluster/configure-upgrade-etcd/#replacing-a-failed-etcd-member) in the Kubernetes documentation
is really helpful.

Let's say you have a kubespray inventory with three etcd nodes and one of them dies.  Do this
to replace it:

* `kubectl delete node xx` where xx is the node to be replaced
  * If the node to be deleted is the master used for the kubectl command, you may have to
    tweak your ~/.kube/config to reference another working master
* get a new machine with same IP address
* restore the certificates from your backup
* remove ansible cache
  * rm /tmp/xx (where xx is any node name)
* run kubespray/cluster.yml with your original inventory
  * this will abort either by etcd not up or calico not up (probably due to etcd not up), etc.

To recover from the abort, 
do this on the new etcd node (example shows my etcd node 3):

* edit `/etc/etcd.env` and change `ETCD_INITIAL_CLUSTER_STATE=new` to `ETCD_INITIAL_CLUSTER_STATE=existing`
* `systemctl stop etcd`
* `systemctl disable etcd`
* `docker rm etcd3` ; use the correct container name -- in this case it's `etcd3`
  * use `docker ps -a` to find the correct name
* `rm -rf /var/lib/etcd/*`
* `etcdctl --peers x,x,x member remove xx` ; see below for how to run etcdctl
* `etcdctl --peers x,x,x member add etcd3 https://x.x.x.x:2380`; see below for how to run etcdctl
  * ensure your `/etc/etcd.env` file matches the values given in the output
* `systemctl enable etcd`
* `systemctl start etcd`

NOTE: For debugging, if your `/etc/etcd.env` file is already created, you can just run `/usr/local/bin/etcd`
and watch the output on the command line.

Check the etcd cluster health using the etcdctl command as described in the next section.  You should
see all members as healthy.  If not, repeat the above steps and possibly run etcd on the command
line to help debug.  Once done debugging, get etcd to run via the service.

Once the etcd cluster is fully functional, rerun kubespray/cluster.yml wth `--limit x` where x is the name
of the new node.  At this point, we only need to run the cluster.yml playbook on that one node so
that it can finish with the kubspray tasks that would've run if kubespray didn't abort.

The output of `kubectl get node` should show all nodes (including the new one).

NOTE: `kubectl get node` may show all nodes present but the etcd cluster may still only have two members.

### Running the etcdctl command

You can run any etcdctl command by using one of two methods (I use cluster-health below):

where:

* p1, p2, and p3 are the IP addresses of the members of the `[etcd-node]` group in the
  kubespray inventory.  I assume 3 etcd members.
* `num` is the ordinal of the etcd member in the `[etcd-node]` group.  You can find out what
  that value is by doing `docker ps | grep etcd`.  The number will be the number at the end of the
  etcd container.
* `val` is the number that lets the filename resolve to an existing certificate and
  key file.
* NOTE: my cluster is called "dp-test" -- you'll have to adjust the names to fit your
  and certificate names

```
/usr/local/bin/etcdctl --peers=https://${p1}:2379,https://${p2}:2379,https://${p3}:2379 \
                       --cert-file /etc/ssl/etcd/ssl/member-dp-test-k8s-node-${val}.pem \
                       --key-file /etc/ssl/etcd/ssl/member-dp-test-k8s-node-${val}-key.pem
                       --ca-file /etc/ssl/etcd/ssl/ca.pem cluster-health`
```
The other method is:

```
docker exec -ti etcd${num} etcdctl \
                    --cert-file /etc/ssl/etcd/ssl/member-dp-test-k8s-node-${val}.pem \
                    --key-file /etc/ssl/etcd/ssl/member-dp-test-k8s-node-${val}-key.pem \
                    --ca-file /etc/ssl/etcd/ssl/ca.pem
                    --endpoints https://127.0.0.1:2379 cluster-health
```

The first method runs etcdctl on the Kubernetes node.  The second method runs etcdctl on the container.
Both use the same etcd cluster.

## Adding a new worker node

In this case, you want to just add one more node to your Kubernetes cluster.  This will
be a pure "worker" node (i.e., it will not be a master or etcd node).  You can add the
new node using the cluster.yml or scale.yml playbooks.  I use cluster.yml in my instructions.

* add your new worker node into your inventory under the `[kube-node]` group
* run kubespray/cluster.yml `--limit x` where x is the new node.
  * Ensure you run with `--limit x` only after running it without `--limit x` because kubespray will
    abort due to undefined variables like this: `FAILED! => {"msg": "The field 'environment' has an
    invalid value, which includes an undefined variable.`
  * Running kubespray/cluster.yml on a working cluster that was built by kubespray should cause no harm.

Run `kubectl get node` and you will see the new node.

## Replacing a worker node

Do this if one of your existing worker nodes dies.  You will keep the same inventory.  You
will just replace the node and use the same IP address.

* `kubectl delete node ...`
* run kubespray/cluster.yml `--limit x`
  * see note above about running with `limit x` in the "Add a new worker node section"

## Upgrading a node

You can always use the kubespray cluster-upgrade.yml playbook to upgrade all nodes in your
Kubernetes cluster.  This playbook upgrades your Kubernetes cluster one node at a time; it
will drain/cordone nodes as it performs the upgrade.

Before running the cluster-upgrade.yml playbook, ensure that all nodes can be drained.  Draining
may result in error for certain types of deployments.  For example, if the etcd-operator
deployment resides on a node, the `kubectl drain` command fails.

NOTE: Before installing anything on your
Kubernetes nodes, it is imporant to understand the implications when it comes time to upgrade
Kubernetes using your preferred method.  For example, if etcd-operator will cause problems with
draining, ensure you uninstall it first before performing an upgrade or the cluster-upgrade.yml
playbook will fail.

I personally would rather upgrade one node at a time and see how it goes before proceeding to the
next node.  This allows me better control to ensure that my Kubernetes cluster continues to
provide service in a non-disruptive way (i.e., no downtime).

To upgrade one node at a time, I do this:

* drain/cordone the node to be updated
* `kubectl delete node ...` the node
* wipe that node clean with a fresh OS install and using the same IP address
* follow the same procedures above for replacing nodes except
  when you run the cluster.yml playbook, first set the git tag on the kubespray repo to the next higher
  tag which uses the next set of versions of software you want to use.
  Realize that upgrading this way will upgrade the versions but can be unsafe because there may be yaml
  incompatibilities.  Resolve the yaml incompatibilities first using a staging environment.
  * if you have no ansible cache, run cluster.yml once with no inventory changes and with
    the kubespray tag that was used to build that node; this should result in no changes.
  * run the cluster.yml playbook with the `--limit x` option where x is the name of the node
    to be upgraded.
  * Here is a set of variables and versions known to work for me on kubespray release v2.4.0; my purpose
    was to stick with the versions on kubespray v2.4.0 but upgrade a few things.  I was able to wipe
    my machines and run kubespray with these variables to get to these versions:

```
helm_enabled: true
helm_version: v2.8.2

# Bump to later Kubernetes.
kube_version: v1.10.9

# Required for kubespray v2.4.0 and kube_version: v1.10.6+
hyperkube_image_repo: "gcr.io/google-containers/hyperkube"
hyperkube_image_tag: v1.10.9

# updated kubedns
kubedns_version: 1.14.13

# upgrade calico
calico_version: "v2.6.8"
calico_ctl_version: "v1.6.3"
calico_cni_version: "v1.11.4"
calico_policy_version: "v1.0.3"
calico_rr_version: "v0.4.2"
```

## Upgrading components that won't apply in new versions of Kubernetes

Example, we use xyz yaml feature and it's not applicable for Kubernetes 1.10.3 and below.
Upgrade of Kubernetes will succeed but that's because the config is already there.
After doing the Kubernetes upgrade, you should, one node at a time, remove xyz yaml usage
(which may imply tearing down other things that depended on the xzy feature),
apply the new compatible version of xzy yaml, and then build things on top of it.

NOTE: once this is done, you will have to repeat the procedure when going down a
version.
