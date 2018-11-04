# Image Preloading and Container Upgrades

## Introduction

One of the challenges of running Kubernetes is that once in a while
your containers will need an upgrade and you need to roll out that
upgrade in a graceful manner.  If your image is big or if your docker
registry is busy, loading new images may not be so straightforward.
For example, the image could take a long to time load or the image
load can fail (e.g., due to network connectivity or authentication issues).
During an upgrade cycle, you want to handle these conditions well.  Here are
two scenarios:

* Image does not load due to network connectivity
* Image takes a long time to load and times out

The first is something that needs to be addressed very soon as network
connectivity loss can have other bad side effects.  This can be due to
things like default gateway down, DNS down, etc.

The second may be mitigated by increasing the size of certain timeout
parameters (i.e., the kubelet `--image-pull-progress-deadline` option
set with an appropriate amount of time).

Either way, problems with loading images can make rolling out upgrades
in Kubernetes problematic.

## Suggestions

Separate out the image loading and the image upgrades.
This way, your upgrades will be more predictable.

One method is to manually (or via automation) go to each Kubernetes
worker node and run the `docker pull` command for the new image.  You
may have to enter a user/password in case you are using a private docker
registry.  Any image loading issues can be addressed at this time without
disturbing any upgrade cycle.

Another method (my preferred method) is to use a daemonset to create a
container that uses the upgraded image such that the container does nothing.
The idea is to get Kubernetes to do an image load (so that the image is
populated in the docker images area) but not do any other function.  As in
the previous method, any issues can be addressed at this time.  If you have
a large Kubernetes cluster and only want to run that container on certain
nodes, you can use a node selector so that only those nodes get the daemonset
pods.  This will avoid loading the container image onto nodes that won't
use it.

Once the images are successfully loaded, you can roll out your new
containers that reference the new image.  The difference will be that the
image is already loaded on each of your Kubernetes nodes and so rolling out
the new version will be a lot more predictable (e.g., faster and without
having to deal with image load problems.

NOTE: if you have time, it's probably a good idea to design your container
image so that it can load and do nothing.  This will ensure that by default
it will not disturb any existing deployment.

## Example Scripting

First label the Kubernetes nodes you want the image to load on.

```
for i in {1..10}; do
  kubectl label nodes my-cluster-node-$i load-image=1
done
```

Remove the label from Kubernetes nodes that you will never run your
container on.  My 10th worker node is used for other workloads so
I remove the label there.

```
kubectl label nodes my-cluster-node-10 load-image-
```

Here's the daemonsetup yaml -- adjust as needed.

```
apiVersion: apps/v1beta2
kind: DaemonSet
metadata:
  name: load-image
spec:
  selector:
    matchLabels:
      name: load-image
  template:
    metadata:
      labels:
        name: load-image
    spec:
      containers:
      - name: do-nothing
        image: my.docker.registry/project/dennis-project:IMAGE
        imagePullPolicy: IfNotPresent
      terminationGracePeriodSeconds: 5
      imagePullSecrets:
        - name: my-image-pull-secret
      restartPolicy: Always
```

The image `dennis-project` loads and sleeps by default when we pass no parameters.
I set the `terminationGracePeriodSeconds` to something low (5 seconds) so the
container will get deleted relatively quickly -- as there is no need to delay it
since it does nothing anyway.

Run this script for the first time; the variable `MY_TAG` will be the image
tag to use for subsequent upgrades.  But I start out with my initial rollout
of `1.0.0`.

```
# Load images into the local docker images are before we do any
# container upgrades.  We do this via a daemonset whose sole purpose
# is to startup and then do nothing.
# To load a new image, we update the version in the daemonset.

# Set the default (initial image).
#
MY_TAG=${MY_TAG:-"1.0.0"}

# Add the tag into the image part of the daemonset yaml and make
# a new yaml to load.
#
cat scripts/load_image.yaml | sed "s/IMAGE/$MY_TAG/g" > /tmp/new_image.yaml

# If you want to destroy the daemonset first, do this.  Destroying it will
# allow a clean create when you re-create the daemonset.  All image loads
# will happen at the same time.
#
theDS=$(kubectl get ds |grep load-image |awk '{print $1}')
if [ $theDS == "load-image" ]; then
  kubectl delete ds load-image
fi

# Apply the daemonset yaml and either see the daemonset pods for the
# first time.
# If the damonset already exists, this will update just the image and
# the pods will load and rollout one at a time.
#
kubectl apply -f /tmp/new_image.yaml

# Wait for the images to be loaded; this command will exit only
# if all images have loaded.
#
kubectl rollout status ds/load-image
```

## Performing an image upgrade using image preloading

Suppose you have a new image with tag 1.0.1 and you want to roll out an upgrade.
Set the `MY_TAG` variable to that version:

```
export MY_TAG=1.0.1
```

Run the script in the previous section.

There are two ways to run the script:

* Delete the daemonset first (if it exists): this will make it so that the images
  get loaded onto each Kubernetes node simultaneously.  This is faster but will
  put your docker registry under more load.
* Apply the new image tag to the yaml and `kubectl apply` the new yaml: this will
  run a rolling upgrade to the daemonset.  That is, the image will be pulled for
  each pod in the daemonset one at a time.  This will be slower (due to the fact
  that it is serial in nature); but the load on the docker registry will be lower.

After the script is successfully run and all pods in the daemonset are in Running
state, proceed with your container upgrade procedures.

## Troubleshoot image problems before container upgrades

If there is a problem loading the images on your Kubernetes nodes, address them before
doing any container upgrades.  This can include a number of activities including
mitigating any network connectivity, authentication, or image timeout problems.

When you are done mitigating the problems, rerun the script above and ensure
the daemonset pods are all created before running any container upgrades.
