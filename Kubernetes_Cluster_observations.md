# Some observations to help understand Kubernetes deployments

Here's my environment:

* We have three Kubernetes masters and 2 Kubernetes workers
* We use docker as the container runtime.
* We use calico for Kubernetes networking

## What Kubernetes does for us

At a highlevel:

* Kubernetes lets us start containers on the Kubernetes nodes.
* Calico sets up the networking for those containers.
* Once this containers are up and networking is running, the containers just run. In other words,
  your "workloads" are functioning.

This all obvious.  But what's not quite obvious is the following:

* If I stop kubelet on a node (or if kubelet dies for whatever reason), my workloads continue to run
  * `kubectl get node` will show the node as `NotReady`
  * Pods on that node will show with state of `Unknown`
  * If a pod is controlled by a deployment, that pod will eventually terminate and restart
    on another working node.
    * If the pod is not controlled by a deployment, that pod will remain intact and continue to run
* If I stop kube-apiserver on a master node, my workloads continue to run.  However, kubectl will not work.
  * But you can still point kubectl to another master (via tweaking of ~/.kube/config)
    * Measures can be taken to do this automatically to avoid any downtime on kubectl
* If I stop calico, my networking continues to run


## Galera scanario and wrong use of Kubernetes deployments

Let's say we have a three node Galera cluster using
[Severalnines](https://github.com/severalnines/galera-docker-mariadb) setup with three mysql pods
managed by their own deployment.  This means that if a mysql pod dies, the deployments will
retart them.  We have noticed that due to
[Known Limitations](https://github.com/severalnines/galera-docker-mariadb#known-limitations), if
one of those mysql pods goes down, recovery is not possible.  Specifically, if the deployment
restarts the mysql pod, that pod will refuse to restart (to avoid the possibility of data loss).

In this case, using a Kubernetes deployments is pointless.  Here are a few reasons:

* If restarting the mysql pod is not supported (see Known limitations above mentioning possible
  dataloss), then don't restart it and avoid restarting it.
* If kubelet dies, your mysql pod remains intact and running (i.e, no impact to the Galera
  cluster).  But eventually the deployment logic will restart the pod which is not supported and causes that
  pod to be down.  In a three mysql Galera cluster, you will end up with a two mysql Galeray cluster.




