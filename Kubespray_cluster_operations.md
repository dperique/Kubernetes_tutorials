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
Kubernetes versions as well as versions for the various components (e.g., calico, etcd, kubedns, etc.).

## Setting up and/or saving ansible cache

Ansible cache is needed when you run ansible with `--limit option`.  This option is useful when
you want to limit operations to a single node and not disturb the others especially in a production
enviroment.

You can generate the ansible
cache just by running a playbook (e.g., cluster.yml) with no changes.  Kubespray puts the ansible
cache in /tmp (see `fact_caching_connection = /tmp` in ansible.cfg).

IMPORTANT: Understand that the `/etc/kubernetes/manifest` files on each Kubernetes node files are regenerated
(but should be the same)
      and the kube-controller, kube-scheduler, and kube-apiserver are restarted (resulting in about 44
      seconds of kube-apiserver downtime in my case).  However, workloads and the service they provide should
      remain intact and running.

It's a good idea to save your ansible cache in case you need to use the `-limit` option.
This will ensure you do not have to run kubespray when you don't need to.
Also, if one of your nodes is dead (e.g., not responding), you may not be able to generate the ansible cache.

I have yet to explore this idea but will soon.

## Recommendation: Save your certificates

I recommend saving the certificates from your Kubernetes nodes immeidately after it
goes into operation so that when you bootstrap
a replacement node, you put those certificates on the fresh machine before running
kubespray -- this will avoid any tls authentication issues (especially in the etcd
cluster used for Kubernetes bookkeeping).

I understand that kubespray may contain some tooling so that you really don't have
to save certificates but that is another area of research I have not gone through.

Here's roughly how I did it for my 6 node cluster and how I restored the certificates for
node 4 (where junk.rsa is the ssh key used to login to each host):

```
## Copy the certificates from my 6 hosts.

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

# Restore certificates onto node4.
#
ssh -i junk.rsa node4
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
* remove ansible cache (kubespray puts ansible cache in /tmp)
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

NOTE: If your `/etc/etcd.env` file is already created, you can just run `/usr/local/bin/etcd`
on the command line as it will use the parameters specified in `/etc/etcd.env`.  Running this way, you can
watch the output on the screen.  This is helpful for debugging so you can watch for errors and deal with them
as you see them.

Check the etcd cluster health using the etcdctl command as described in the next section.  You should
see all members as healthy.  If not, repeat the above steps and possibly run etcd on the command
line to help debug.  Once done debugging, get etcd to run via the service.

Once the etcd cluster is fully functional, rerun kubespray/cluster.yml wth `--limit x` where x is the name
of the new node since we only need to run the cluster.yml playbook on that one node so
that it can finish with the kubespray tasks that would've run had it not aborted.  If etcd is fully
up, then kubespray should get past the part where it aborted earlier.

The output of `kubectl get node` should show all nodes (including the new one).

NOTE: `kubectl get node` may show all nodes present but the etcd cluster may still only have two members.
Check etcd status via `kubectl get componentstatuses`.

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

Run either of the commands above as root on one of your Kubernetes nodes that is running etcd.
The first method runs etcdctl on the Kubernetes node.  The second method runs etcdctl on the etcd container.
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
* Restore the certificates onto this new node using the above sample scripting; this will
  ensure that you avoid any tls errors when etcd starts up.
* run kubespray/cluster.yml `--limit x`
  * see note above about running with `limit x` in the "Add a new worker node section"

## Upgrading a node

### Keep these in mind when doing upgrades

* Before running the cluster-upgrade.yml playbook, ensure that all nodes can be drained.  Draining
  may result in error for certain types of deployments.  For example, if the etcd-operator
  deployment resides on a node, the `kubectl drain` command fails.

* Before installing anything on your
  Kubernetes nodes, understand the implications when it comes time to upgrade
  Kubernetes using your preferred method.  For example, if etcd-operator will cause problems with
  draining, ensure you uninstall it first before performing an upgrade or the cluster-upgrade.yml
  playbook will fail.

* Resolve the yaml incompatibilities first using a staging environment.  Realize that upgrading may
  result in yaml incompatibilities.  For example, if you used x.yaml to
  add a PersistentVolume
  in Kubernetes 1.9.2 and then upgraded to Kubernetes 1.10.4, x.yaml may not be compatible and
  a `kubectl apply -f x.yaml` may fail.  You will have to upgrade x.yaml so that you can run it again
  on the new version.  On your staging environment, ensure that the upgraded yaml, when applied to
  an already existing PersistentVolume is idempotent.  If you don't do this, and upgrade anyway,
  you risk damaging a PersistentVolume that supports an important service.
  * Once this is done, you will have to repeat the procedure when going down a version

### Using kubespray cluster-upgrade.yml playbook

You can always use the kubespray cluster-upgrade.yml playbook to upgrade all nodes in your
Kubernetes cluster.  This playbook upgrades your Kubernetes cluster one master at a time and
20% of the workers at a time and will drain/cordone nodes as it performs the upgrade.

To upgrade using cluster-upgrade.yml, set the kubespray tag to the next release, study the new
versions in the release notes, and then run the cluster-upgrade.yml playbook.

But keep in mind that cluster-upgrade.yml, as written, pays no attention to anything specific
to your Kubernetes cluster.  It will download and upgrade blindly with no regard for your
Kubernetes workloads.  In many cases this is ok.  But there are cases where it is not.  Here
are a few:

* If docker is restarted, pods most like will restart.  This is usually ok especially when
  pods are inside a deployment or replication controller.  But if the pod does not handle
  restarts well, this will be problematic.  Two examples are:
  * mysql pods in a Galera cluster.  If you restart a mysql pod, it will start, see data
    and abort to avoid any possible data corruption
    [Know Limitation bullet 3](https://github.com/severalnines/galera-docker-mariadb#known-limitations)
  * etcd nodes that are part of an etcd cluster that uses only pod local storage.  If you
    restart an etcd node, it will not join the cluster because it is essentially a new member.
* The kube-controller, kube-scheduler, and kube-apiserver will be restarted and comes with
  their own implications.  For example, kube-apiserver downtime (I found to be about 44 seconds in my
  environments) results in kubectl not working.
  * Note that since one master at a time gets upgrade, you can always point kubectl to a different
    master and still use kubectl.

### Upgrade procedure for one node at a time

I personally would rather upgrade one node at a time and see how it goes before proceeding to the
next node.  This allows me better control to ensure that my Kubernetes cluster continues to
provide service in a non-disruptive way (i.e., no downtime).

To upgrade one node at a time, I do this:

* drain/cordone the node to be updated
* `kubectl delete node ...` the node
* Ensure the node to be upraded keeps the same IP address
* Do one of these:
  * wipe that node clean with a fresh OS install; this can include other patches and other upgrades
  * keep the node intact with currently running versions (i.e., don't wipe anything)
* follow the same procedures above for replacing nodes except
  when you run the cluster.yml playbook, do one of these:
  * set the git tag on the kubespray repo to the next higher
    tag which uses the next set of versions of software you want to use.
  * set kubespray variables to the versions you want to upgrade to
* run the cluster.yml playbook with the `--limit x` option where x is the name of the node
  to be upgraded.
* After successful run go through and check the versions were upgraded.

### Sample set of versions that worked for me

Here is a set of variables and versions known to work for me on kubespray release v2.4.0; my purpose
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

## Accessing the dashboard

We have found that the dashboard takes a bit of resource so we disable it by default especially
in minikube deployments we use in CI testing.  However, the dashboard is nice for demos. Here's
how I get to the dashboard.

* Turn on the dashboard using the `dashboard_enabled: true` variable in kubespray.
  * Look at [Dashboard repo](https://github.com/kubernetes/dashboard) for the actual source including
    releases
  * Optionally tweak the version of dashboard you want using `dashboard_image_tag` in kubespray
    `kubespray/roles/kubernetes-apps/ansible/defaults/main.yml`; I'm using v1.10.0 (latest as of
    this writing)
* Run `kubectl proxy --port=8001` to expose the ports to your local machine on `localhost`.
* Navigate to: [Kubernetes dashboard](http://localhost:8001/api/v1/namespaces/kube-system/services/https:kubernetes-dashboard:/proxy/#!/login)
  using your local browser.
  * It will give 2 choices -- pick the one for supplying the token.
* Read this for more information: [giantswarm reference](https://docs.giantswarm.io/guides/install-kubernetes-dashboard/) but
  the TL;DR of getting the token is here:

```
# Create a service account for dashboard
#
$ kubectl create serviceaccount cluster-admin-dashboard-sa

# Create a clusterrolebinding for dashboard and give it admin rights
#
$ kubectl create clusterrolebinding cluster-admin-dashboard-sa \
  --clusterrole=cluster-admin \
  --serviceaccount=default:cluster-admin-dashboard-sa

# Determine the secret that was generated.
#
$ kubectl get secret | grep cluster-admin-dashboard-sa
cluster-admin-dashboard-sa-token-...   kubernetes.io/service-account-token  ...

# Get the secret that shows following `token: ` in the output
#
$ kubectl describe secret cluster-admin-dashboard-sa-token-6xm8l
```
