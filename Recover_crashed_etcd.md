# Summary of how to recover a crashing etcd cluster node

We have a three pod etcd cluster running on Kubernetes.  Each etcd pod uses a
deployment so that it can restart automatically (e.g., when a Kubernetes
worker node dies and the pod is restarted on another working Kubernetes worker
node).  We use `--initial-cluster-state=new` on the etcd cli for each etcd
pod when initially creating the etcd cluster.

NOTE: if you need help generating a podspec for etcd, you can use several
methods including [etc-pod-gen](https://github.com/kelseyhightower/etcd-pod-gen).

I may use the terms "node" and "pod" together.  When discussing etcd, I
think of each etcd instance running as an "etcd node" and three etcd nodes make up
my three node etcd cluster.  When I run this on Kubernetes, each etcd node is a
Kubernetes "pod".  So my three node etcd cluster running on Kubernetes is a three
node/pod etcd cluster.  A "deployment" in Kubernetes is a construct that ensures
that a certain number of each pod is present at all times (in my case, I have
three deployments -- one for each of the three etcd pods.  In each deployment, I specify
the etcd cli (for when etcd starts up) for each etcd pod and the replicaCount=1
for each deployment.  If the Kubernetes node (hypervisor), that an etcd pod
was running on, crashes, that etcd pod is gone and is restarted on a different
Kubernetes node.

Unfortunately, when an etcd pod is recreated, it will not
start as it did initially, but will end up in a crash looping state.  To fix
this, we follow this procedure:

* From one of the other functional etcd pods, show the list of members to
  determine the id of the one that is crashing using the `etcdctl member list`
  command
* remove the broken etcd member
  from the etcd cluster using the `etcdctl member remove <id>` command.
* add a new etcd member to the etcd cluster using the `etcd member add ...`
  command.  This new member will replace the old crashed one.
* create a new etcd pod using `--initial-cluster-state=existing` on the
  etcd cli; to do this, edit deployment that creates the etcd pod using the
  Kubernetes `kubectl edit deployment ...` command.

Once the deployment uses the `--initial-cluster-state=existing` option, you can
leave it that way.  So, if that etcd pod dies and has to be re-created, to
recover it, you can just follow the first three steps above.  The last
step, at this point, is unnecessary because you already modified the deployment
and that state is retained by Kubernetes.

NOTE: when creating each of the etcd pods for the first time, you probably
started out with a Kubernetes deloyment yaml file and did
`kubectl apply -f myfile.yaml`; in that file, you specified
`initial-cluster-state=new`.  When you edit the deployment using
`kubectl edit deployment myfile.yaml`, you changed the state in Kubernetes.
This change causes Kubernetes to re-create the pod associated with that deployment;
this change is different than that reflected in myfile.yml.  If you
run `kubectl apply -f myfile.yaml` again, that pod will restart because you
made a state change -- so always check the state of your deployment before
applying your yaml file to avoid an unexpected pod re-create.

Here's transcript of what I did when I deleted one of the etcd pods in a three
node/pod etcd cluster:

```
# Delete one of the etc pods to simulate it going away or dying.
#
$ kubectl delete po etcd1-deployment-57f7d8c558-n4wxh 
pod "etcd1-deployment-57f7d8c558-n4wxh" deleted

$ kubectl get po
NAME                                READY     STATUS        RESTARTS   AGE
etcd0-deployment-5d84cf5f47-p8br4   1/1       Running       0          1m
etcd1-deployment-57f7d8c558-n4wxh   0/1       Terminating   0          3h
etcd1-deployment-57f7d8c558-n6fw9   0/1       Error         1          5s
etcd2-deployment-dd6444d5d-r76bp    1/1       Running       0          3h

# To recover, from a running etcd pod, remove the etcd1 member and add one back.
#
$ m1=$(kubectl get po | grep etcd2 | cut -d " " -f 1)
$ kubectl exec -ti $m1 -- sh
/ # etcdctl member list
ade526d28b1f92f7: name=etcd1 peerURLs=http://etcd1:2380 clientURLs=http://etcd1:2379 isLeader=false
d282ac2ce600c1ce: name=etcd2 peerURLs=http://etcd2:2380 clientURLs=http://etcd2:2379 isLeader=true
d5ec074b43d2deee: name=etcd0 peerURLs=http://etcd0:2380 clientURLs=http://etcd0:2379 isLeader=false

/ # etcdctl member remove ade526d28b1f92f7
Removed member ade526d28b1f92f7 from cluster

/ # etcdctl member add etcd1 http://etcd1:2380
Added member named etcd1 with ID 2107ad21fe0e48fb to cluster

ETCD_NAME="etcd1"
ETCD_INITIAL_CLUSTER="etcd1=http://etcd1:2380,etcd2=http://etcd2:2380,etcd0=http://etcd0:2380"
ETCD_INITIAL_CLUSTER_STATE="existing"

# Edit the etcd1 deployment, change initial-cluster-state=new to existing.
#
$ kubectl edit deployments etcd1-deployment
deployment "etcd1-deployment" edited

# The etcd1 deployment is creating a new etcd1 pod.
#
$ kubectl get po
NAME                                READY     STATUS        RESTARTS   AGE
etcd0-deployment-5d84cf5f47-p8br4   1/1       Running       0          3m
etcd1-deployment-57f7d8c558-n6fw9   0/1       Terminating   3          1m
etcd1-deployment-f4c5f47d7-w6hcz    1/1       Running       0          5s
etcd2-deployment-dd6444d5d-r76bp    1/1       Running       0          3h

# It's added to the cluster and the cluster size is back to 3.
#
$ m1=$(kubectl get po | grep etcd0 | cut -d " " -f 1)
$ 
$ kubectl exec $m1 -- etcdctl cluster-health
member 2107ad21fe0e48fb is healthy: got healthy result from http://etcd1:2379
member d282ac2ce600c1ce is healthy: got healthy result from http://etcd2:2379
member d5ec074b43d2deee is healthy: got healthy result from http://etcd0:2379
cluster is healthy

# It's not quite done starting.
#
$ m1=$(kubectl get po | grep etcd1 | cut -d " " -f 1)
$ kubectl exec $m1 -- etcdctl cluster-health
error: unable to upgrade connection: container not found ("etcd1")

# But the other etcd pod shows it as health.
#
$ m1=$(kubectl get po | grep etcd2 | cut -d " " -f 1)
$ kubectl exec $m1 -- etcdctl cluster-health
member 2107ad21fe0e48fb is healthy: got healthy result from http://etcd1:2379
member d282ac2ce600c1ce is healthy: got healthy result from http://etcd2:2379
member d5ec074b43d2deee is healthy: got healthy result from http://etcd0:2379
cluster is healthy

# Now the new etcd pod shows as healthy.
#
$ m1=$(kubectl get po | grep etcd1 | cut -d " " -f 1)
$ kubectl exec $m1 -- etcdctl cluster-health
member 2107ad21fe0e48fb is healthy: got healthy result from http://etcd1:2379
member d282ac2ce600c1ce is healthy: got healthy result from http://etcd2:2379
member d5ec074b43d2deee is healthy: got healthy result from http://etcd0:2379
cluster is healthy

# All pods look good.
#
$ kubectl get po
NAME                                READY     STATUS    RESTARTS   AGE
etcd0-deployment-5d84cf5f47-p8br4   1/1       Running   0          4m
etcd1-deployment-f4c5f47d7-w6hcz    1/1       Running   0          45s
etcd2-deployment-dd6444d5d-r76bp    1/1       Running   0          3h

# The state of the modified deployment is preserved.
#
$ kubectl describe deployments etcd1-deployment
Name:                   etcd1-deployment
Namespace:              default
...
Pod Template:
    Image:  quay.io/coreos/etcd:latest
    Ports:  2379/TCP, 2380/TCP
    Command:
      /usr/local/bin/etcd
      --name
      etcd1
      --initial-advertise-peer-urls
      http://etcd1:2380
      --listen-peer-urls
      http://0.0.0.0:2380
      --listen-client-urls
      http://0.0.0.0:2379
      --data-dir=/var/lib/etcd/data
      --wal-dir=/var/lib/etcd/wal
      --election-timeout=1000
      --heartbeat-interval=100
      --snapshot-count=10000
      --max-snapshots=5
      --max-wals=5
      --advertise-client-urls
      http://etcd1:2379
      --initial-cluster
      etcd0=http://etcd0:2380,etcd1=http://etcd1:2380,etcd2=http://etcd2:2380
      --initial-cluster-state
      existing                          <-- this is different from the original
...

# Let's try that again given that the deployment is already different
# from the deployment yaml file.  This simulates what to do if this
# pod dies again.
#
$ kubectl get po
NAME                                READY     STATUS    RESTARTS   AGE
etcd0-deployment-5d84cf5f47-p8br4   1/1       Running   0          12m
etcd1-deployment-f4c5f47d7-w6hcz    1/1       Running   0          9m
etcd2-deployment-dd6444d5d-r76bp    1/1       Running   0          3h

# Delete the existing etcd1 pod to simulate it dying the second time.
#
$ kubectl  delete po etcd1-deployment-f4c5f47d7-w6hcz 
pod "etcd1-deployment-f4c5f47d7-w6hcz" deleted

# Note a new pod is created for etcd1.
#
$ kubectl get po
NAME                                READY     STATUS    RESTARTS   AGE
etcd0-deployment-5d84cf5f47-p8br4   1/1       Running   0          12m
etcd1-deployment-f4c5f47d7-flxln    1/1       Running   1          4s
etcd2-deployment-dd6444d5d-r76bp    1/1       Running   0          3h

# But it goes into crash mode.
#
$ kubectl get po
NAME                                READY     STATUS             RESTARTS   AGE
etcd0-deployment-5d84cf5f47-p8br4   1/1       Running            0          12m
etcd1-deployment-f4c5f47d7-flxln    0/1       CrashLoopBackOff   1          8s
etcd2-deployment-dd6444d5d-r76bp    1/1       Running            0          3h

# Check its logs.
#
$ kubectl logs etcd1-deployment-f4c5f47d7-flxln
2018-04-29 19:58:43.651510 W | pkg/flags: unrecognized environment variable ETCD_CLIENT_SERVICE_PORT=2379
2018-04-29 19:58:43.651601 W | pkg/flags: unrecognized environment variable ETCD_CLIENT_PORT_2379_TCP_PROTO=tcp
2018-04-29 19:58:43.651611 W | pkg/flags: unrecognized environment variable ETCD_CLIENT_SERVICE_HOST=10.233.62.155
2018-04-29 19:58:43.651616 W | pkg/flags: unrecognized environment variable ETCD_CLIENT_PORT_2379_TCP_ADDR=10.233.62.155
2018-04-29 19:58:43.651624 W | pkg/flags: unrecognized environment variable ETCD_CLIENT_PORT=tcp://10.233.62.155:2379
2018-04-29 19:58:43.651631 W | pkg/flags: unrecognized environment variable ETCD_CLIENT_PORT_2379_TCP_PORT=2379
2018-04-29 19:58:43.651654 W | pkg/flags: unrecognized environment variable ETCD_CLIENT_PORT_2379_TCP=tcp://10.233.62.155:2379
2018-04-29 19:58:43.651660 W | pkg/flags: unrecognized environment variable ETCD_CLIENT_SERVICE_PORT_ETCD_CLIENT_PORT=2379
2018-04-29 19:58:43.651682 I | etcdmain: etcd Version: 3.3.4
2018-04-29 19:58:43.651688 I | etcdmain: Git SHA: fdde8705f
2018-04-29 19:58:43.651691 I | etcdmain: Go Version: go1.9.5
2018-04-29 19:58:43.651697 I | etcdmain: Go OS/Arch: linux/amd64
2018-04-29 19:58:43.651701 I | etcdmain: setting maximum number of CPUs to 32, total number of available CPUs is 32
2018-04-29 19:58:43.651710 W | etcdmain: no data-dir provided, using default data-dir ./etcd1.etcd
2018-04-29 19:58:43.651806 I | embed: listening for peers on http://0.0.0.0:2380
2018-04-29 19:58:43.651836 I | embed: listening for client requests on 0.0.0.0:2379
2018-04-29 19:58:43.655152 I | pkg/netutil: resolving etcd0:2380 to 10.233.21.50:2380
2018-04-29 19:58:43.655513 I | pkg/netutil: resolving etcd0:2380 to 10.233.21.50:2380
2018-04-29 19:58:43.655906 I | pkg/netutil: resolving etcd1:2380 to 10.233.2.237:2380
2018-04-29 19:58:43.656241 I | pkg/netutil: resolving etcd1:2380 to 10.233.2.237:2380
2018-04-29 19:58:43.656542 I | pkg/netutil: resolving etcd2:2380 to 10.233.52.18:2380
2018-04-29 19:58:43.656882 I | pkg/netutil: resolving etcd2:2380 to 10.233.52.18:2380
2018-04-29 19:58:43.658388 I | etcdserver: name = etcd1
2018-04-29 19:58:43.658401 I | etcdserver: data dir = etcd1.etcd
2018-04-29 19:58:43.658407 I | etcdserver: member dir = etcd1.etcd/member
2018-04-29 19:58:43.658411 I | etcdserver: heartbeat = 100ms
2018-04-29 19:58:43.658415 I | etcdserver: election = 1000ms
2018-04-29 19:58:43.658421 I | etcdserver: snapshot count = 100000
2018-04-29 19:58:43.658430 I | etcdserver: advertise client URLs = http://etcd1:2379
2018-04-29 19:58:43.659316 I | etcdserver: starting member 2107ad21fe0e48fb in cluster 8fd95ce30f013867
2018-04-29 19:58:43.659351 I | raft: 2107ad21fe0e48fb became follower at term 0
2018-04-29 19:58:43.659363 I | raft: newRaft 2107ad21fe0e48fb [peers: [], term: 0, commit: 0, applied: 0, lastindex: 0, lastterm: 0]
2018-04-29 19:58:43.659371 I | raft: 2107ad21fe0e48fb became follower at term 1
2018-04-29 19:58:43.661502 W | auth: simple token is not cryptographically signed
2018-04-29 19:58:43.662127 I | rafthttp: started HTTP pipelining with peer d282ac2ce600c1ce
2018-04-29 19:58:43.662151 I | rafthttp: started HTTP pipelining with peer d5ec074b43d2deee
2018-04-29 19:58:43.662164 I | rafthttp: starting peer d282ac2ce600c1ce...
2018-04-29 19:58:43.662183 I | rafthttp: started HTTP pipelining with peer d282ac2ce600c1ce
2018-04-29 19:58:43.662720 I | rafthttp: started streaming with peer d282ac2ce600c1ce (writer)
2018-04-29 19:58:43.663010 I | rafthttp: started streaming with peer d282ac2ce600c1ce (writer)
2018-04-29 19:58:43.663631 I | rafthttp: started peer d282ac2ce600c1ce
2018-04-29 19:58:43.663652 I | rafthttp: added peer d282ac2ce600c1ce
2018-04-29 19:58:43.663657 I | rafthttp: started streaming with peer d282ac2ce600c1ce (stream MsgApp v2 reader)
2018-04-29 19:58:43.663685 I | rafthttp: started streaming with peer d282ac2ce600c1ce (stream Message reader)
2018-04-29 19:58:43.663717 I | rafthttp: starting peer d5ec074b43d2deee...
2018-04-29 19:58:43.663747 I | rafthttp: started HTTP pipelining with peer d5ec074b43d2deee
2018-04-29 19:58:43.664006 I | rafthttp: started streaming with peer d5ec074b43d2deee (writer)
2018-04-29 19:58:43.664464 I | rafthttp: started streaming with peer d5ec074b43d2deee (writer)
2018-04-29 19:58:43.665592 I | rafthttp: started peer d5ec074b43d2deee
2018-04-29 19:58:43.665611 I | rafthttp: started streaming with peer d5ec074b43d2deee (stream MsgApp v2 reader)
2018-04-29 19:58:43.665638 I | rafthttp: peer d282ac2ce600c1ce became active
2018-04-29 19:58:43.665669 I | rafthttp: added peer d5ec074b43d2deee
2018-04-29 19:58:43.665693 I | rafthttp: established a TCP streaming connection with peer d282ac2ce600c1ce (stream MsgApp v2 reader)
2018-04-29 19:58:43.665700 I | etcdserver: starting server... [version: 3.3.4, cluster version: to_be_decided]
2018-04-29 19:58:43.665771 I | rafthttp: started streaming with peer d5ec074b43d2deee (stream Message reader)
2018-04-29 19:58:43.666146 I | rafthttp: established a TCP streaming connection with peer d282ac2ce600c1ce (stream Message reader)
2018-04-29 19:58:43.667336 I | rafthttp: peer d5ec074b43d2deee became active
2018-04-29 19:58:43.667359 I | rafthttp: established a TCP streaming connection with peer d5ec074b43d2deee (stream Message reader)
2018-04-29 19:58:43.667386 I | rafthttp: established a TCP streaming connection with peer d5ec074b43d2deee (stream MsgApp v2 reader)
2018-04-29 19:58:43.715918 I | etcdserver: 2107ad21fe0e48fb initialzed peer connection; fast-forwarding 8 ticks (election ticks 10) with 2 active peer(s)
2018-04-29 19:58:43.753581 I | raft: 2107ad21fe0e48fb [term: 1] received a MsgHeartbeat message with higher term from d282ac2ce600c1ce [term: 2]
2018-04-29 19:58:43.753612 I | raft: 2107ad21fe0e48fb became follower at term 2
2018-04-29 19:58:43.753629 C | raft: tocommit(54976) is out of range [lastIndex(0)]. Was the raft log corrupted, truncated, or lost?
panic: tocommit(54976) is out of range [lastIndex(0)]. Was the raft log corrupted, truncated, or lost?
...

# Now it's in Error state.
#
$ kubectl  get po
NAME                                READY     STATUS    RESTARTS   AGE
etcd0-deployment-5d84cf5f47-p8br4   1/1       Running   0          13m
etcd1-deployment-f4c5f47d7-flxln    0/1       Error     3          52s
etcd2-deployment-dd6444d5d-r76bp    1/1       Running   0          3h

# Let's repair it using the same procedure but skipping the last step
# where we have to edit the deployment.
#
# Remove the etcd1 member and add another called etcd1
#
$ kubectl exec -ti etcd2-deployment-dd6444d5d-r76bp -- sh
/ # etcdctl member list
2107ad21fe0e48fb: name=etcd1 peerURLs=http://etcd1:2380 clientURLs=http://etcd1:2379 isLeader=false
d282ac2ce600c1ce: name=etcd2 peerURLs=http://etcd2:2380 clientURLs=http://etcd2:2379 isLeader=true
d5ec074b43d2deee: name=etcd0 peerURLs=http://etcd0:2380 clientURLs=http://etcd0:2379 isLeader=false

/ # etcdctl member remove 2107ad21fe0e48fb
Removed member 2107ad21fe0e48fb from cluster

/ # etcdctl member add etcd1 http://etcd1:2380 
Added member named etcd1 with ID 41a1971906de513b to cluster

ETCD_NAME="etcd1"
ETCD_INITIAL_CLUSTER="etcd1=http://etcd1:2380,etcd2=http://etcd2:2380,etcd0=http://etcd0:2380"
ETCD_INITIAL_CLUSTER_STATE="existing"

# Delete the current one (which is in a bad state) so the deployment will
# create a new one.
#
$ kubectl delete po etcd1-deployment-f4c5f47d7-flxln
pod "etcd1-deployment-f4c5f47d7-flxln" deleted

# The new one is created; the old one is terminating.
#
$ kubectl get po
NAME                                READY     STATUS        RESTARTS   AGE
etcd0-deployment-5d84cf5f47-p8br4   1/1       Running       0          17m
etcd1-deployment-f4c5f47d7-8krvf    1/1       Running       0          5s
etcd1-deployment-f4c5f47d7-flxln    0/1       Terminating   5          4m
etcd2-deployment-dd6444d5d-r76bp    1/1       Running       0          3h

# The cluster is once again healthy.
#
$ m1=$(kubectl get po | grep etcd0 | cut -d " " -f 1)
$ kubectl exec $m1 -- etcdctl cluster-health
member 41a1971906de513b is healthy: got healthy result from http://etcd1:2379
member d282ac2ce600c1ce is healthy: got healthy result from http://etcd2:2379
member d5ec074b43d2deee is healthy: got healthy result from http://etcd0:2379
cluster is healthy

$ m1=$(kubectl get po | grep etcd1 | cut -d " " -f 1)
$ kubectl exec $m1 -- etcdctl cluster-health
member 41a1971906de513b is healthy: got healthy result from http://etcd1:2379
member d282ac2ce600c1ce is healthy: got healthy result from http://etcd2:2379
member d5ec074b43d2deee is healthy: got healthy result from http://etcd0:2379
cluster is healthy

$ m1=$(kubectl get po | grep etcd2 | cut -d " " -f 1)
$ kubectl exec $m1 -- etcdctl cluster-health
member 41a1971906de513b is healthy: got healthy result from http://etcd1:2379
member d282ac2ce600c1ce is healthy: got healthy result from http://etcd2:2379
member d5ec074b43d2deee is healthy: got healthy result from http://etcd0:2379
cluster is healthy
```
