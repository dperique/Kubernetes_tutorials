# Notes on Kubernetes upgrades/downgrades

I have been to serveral Kubernetes meetups and find that upgrades/downgrades
of nodes from one Kubernetes version to another is something we all worry
about especially if you have workloads that are providing a service to customers
with a particular SLA.

Also upgrades come well after we have learned to create a Kubernetes in the
first place and is often not added to the schedule.

Here is some knowledge I have gathered on the topic.

## Having CI (Continuous Integration), Staging, and Production Environments

In order to do upgrades/downgrades that are relatively safe and predictable,
we must have:

* Both a production and staging Kubernetes cluster that are as
  close to equivalent as possible (e.g., staging can be based on VMs)
* A Kubernetes cluster for CI testing that is as close to production as
  possible.  Minikube may not be enough.  This Kubernetes cluster can be
  based on VMs just as staging is.
* Sufficient testing to ensure that all Kubernetes functionality used is
  tested and works.  This testing should include scripting that
  does the deployments as well as testing that exercises the functionality
  (hopefully this is obvious).

## Procedure For Performing Upgrades

* Run a CI test using your workloads running on the Kubernetes CI cluster
  using the Kubernetes version you intend to upgrade to.  This will test
  that your yamls will work when you run `kubectl apply -f` and that your
  workloads, once deployed, will function as expected.
  * I insist on this step because although after a Kubernetes upgrade, already
    running workloads are guaranteed to continue to run, your yaml manifest
    files may not be compatible with the new Kubernetes version and may need
    updating.  Running and passing the CI test
    ensures that your yaml files are working and allows you to
    update them in a non-disruptive way if they are not.
  * If you do not perform this step, you may have running and functioning
    workloads post Kubernetes upgrade but when you go to deploy an upgrade
    using your existing yaml
    files, the `kubectl apply -f` may fail.
* Upgrade Kubernetes, one node at a time by migrating workloads off of the
  Kubernetes nodes you intend to upgrade, upgrading that node, and allowing
  workloads to use that upgraded node
  * Try upgrade activity on the staging cluster first, run tests,
    and if those tests pass, do the same upgrade activity on the
    production cluster.  This way we already know it works.
* Repeat this until the entire cluster is upgraded
* For kubespray users: Use the
  kubespray [upgrade playbook](https://github.com/kubernetes-incubator/kubespray/blob/master/upgrade-cluster.yml)
  by setting the git tag and
  running the playbook with an inventory of the nodes you wish to upgrade.
  You can set this inventory to one node, several nodes, or all nodes.
* Do not upgrade more than 2 releases (but it is safer to upgrade
  every 1 release.

## Notes on "graceful" upgrades:

"Graceful" upgrades are Kubernetes upgrades such that there is no service
interruption of the services provided by your workloads.  That is, your customers
don't notice anything.

* Upgrading "gracefully" (i.e., without service downtime) is a different topic
  but can be integrated as needed in the upgrade process.  
* Upgrading one Kubernetes node at a time narrows the scope of making graceful
  uprades to being able to move workloads to another Kubernetes node without
  any service disruption.  This can be done using more than one pod replica, tweaking
  your loadbalancer to stop using a service container that is to be migrated,
  gracefully shutting down services (i.e., allowing in-flight transactions to
  complete), and stopping the container.
  * After the upgrade is complete, you can add the pod back into the load
    balancer

## Procedure for Performing Downgrades

If upgrading Kubernetes goes wrong on the staging cluster and you need to downgrade,
destroy the node and re-build it using the Kubernetes version you want (this version will
be the original version you had on it before upgrading it).  

If you already had a service running on the upgraded, but problematic, Kubernetes node,
run your procedure for migrating your pods to another node if this is possible.

If something goes wrong in the production cluster, use the same procedure as
mentioned above to recover staging.  But, this time, check your tests to
figure out why you didn't catch the problem in staging.

In both cases, if workloads were migrated off of nodes to be upgraded,
there should be no service disruption.  If your problem occurred while your workloads
were on the newly upgraded Kubernetes node, you may have service disruption.
