# Dealing with large pod images

One of the challenges of running Kubernetes is that once in a while
your containers will need an upgrade and you need to roll out that
upgrade in a graceful manner.  If your image is big or if your docker
registry is busy, loading that image may not be so straightforward.
For example, the image could take a long to time load or the image
load can fail (e.g., due to network connectivity issue).  During an
upgrade cycle, you want to handle these conditions well.  Here are
two scenarios:

* Image does not load due to network connectivity
* Image takes a long time to load and times out

The first is something that needs to be addressed very soon as network
connectivity loss can have other bad side effects.

The second may be mitigated by increasing the size of certain timeout
parameters (i.e., the kubelet `--image-pull-progress-deadline` option
set with an appropriate amount of time).

Either way, problems with loading images can make rolling out upgrades
in Kubernetes problematic.

I suggest you separate out the image loading and the image upgrades.
This way, your upgrades will be more predictable.

One method is to manually (or via automation) go to each Kubernetes
worker node and run the `docker pull` command for the new image.  You
may have to enter a user/password in case you are using a private docker
registry.  Any image loading issues can be addressed at this time without
disturbing any upgrade cycle.

Another method (my preferred method) is to use a daemonset to create a
container that uses the upgraded image such that the container does nothing.
The idea is to get Kubernetes to do an image load so that the image is
populated in the docker images area but not do any other function.  As in
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


