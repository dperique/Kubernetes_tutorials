# Using kubectl output in scripts

## Introduction
The ``kubectl`` command supports json output.  This is handy because we can then use it
to get information about a construct (e.g., deployment) in a script.  I'm betting there
are python scripts that do this using some API (will look into that later).  But for now,
here are some examples using the actual ``kubectl`` command and bash.

You can do this to get the json output of a deployment.

```
$ kubectl get deployments dperique-grpc-demo --output json
```

You can also do this to get the number of replicas requested:

```
$ kubectl get deployments dperique-grpc-demo --output=jsonpath={.spec.replicas}
```

You can do this to see how many replicas are actually available.

```
kubectl get deployments dperique-grpc-demo --output=jsonpath={.status.availableReplicas}
```

Using the above, you can write a script to create a deployment and check on the deployment
to see if the available replicas match what is requested.

Such a script is available [here].
[here]: https://github.com/dperique/Kubernetes_tutorials/blob/master/kdeploy_check.sh

You can run it like this:
```
$ ./kdeploy_check.sh ./dperique-grpc-demo-deployment.yaml dperiquet-grpc-demo
deployment "dperiquet-grpc-demo" created

currentlyAvailable = '0' out of '5'
All replicas not present after 1 iterations

currently Available = '0' out of '5'
All replicas not present after 2 iterations

currently Available = '0' out of '5'
All replicas not present after 3 iterations

currently Available = '0' out of '5'
All replicas not present after 4 iterations

currently Available = '0' out of '5'
All replicas not present after 5 iterations

currently Available = '5' out of '5'
All replicas came up

```



