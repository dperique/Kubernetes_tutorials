# Demo of Kubernetes service and load balancer

Below, I have a demo where I deploy a grpc demo server and client with multiple replicas in
a multi-node Kubernetes cluster.  I then create a Kubernetes service and run the client.  The service
dumps out the name of the pod that was used and the node it resides on.  The demo illustrates
that with the service, you automatically get a load balancer that sends forwards requests to
different instances of the server application running on different nodes.

First, clone this repo containing the grpc demo scripts and set context to a
multi-node Kubernetes cluster.  Mine is called dp-kub.  Creating and setting up your own multi-node
Kubernetes cluster is out of the scope of this demo (but you can look up "kubespray").

NOTE: the grpc demo scripts are used only as a sample container application.  You can use
(and are highly encouraged to use) your own application for a similar type of demo. 

```
$ git clone https://github.com/dperique/Kubernetes_tutorials.git
$ cd beginners/grpc_demo
$ kubectl config use-context dp-kub
$ kubectl cluster-info
```

Create a virtualenv so that you can run things.  In my case, I need the grpcio tools to create
my grpc demo application and grpc IDL compiler to process my .proto file.

```
$ virtualenv venv
$ source venv/bin/activate
$ python -m pip install --upgrade pip
$ python -m pip install grpcio
$ python -m pip install grpcio-tools
$ python -m grpc_tools.protoc -I=proto/  --python_out=. --grpc_python_out=. proto/checker.proto
```

Build the application.  Note that I
sleep for 2 seconds (to give the application plenty of time to startup) and then verify it's running via the
``docker ps -a`` command.  The goal in this step is to ensure that the container works before
deploying it on a the Kubernetes cluster.

```
$ docker build -t grpc_server/1.0 .
$ docker run -p 50099:50099 -d grpc_server/1.0 ; sleep 2 ; docker ps -a
```

Optional debugging: in my case, my container exited (meaning it was not working properly).  Here's what I
did to troubleshoot.  I put a long sleep at the end to ensure the container remained running.

```
$ cat Dockerfile 
FROM grpc/python:1.0-onbuild
ADD checker_client.py checker_server.py checker_pb2_grpc.py checker_pb2.py /
WORKDIR /
CMD ["sleep", "100000”]  <— put this
CMD ["python", "checker_server.py"]
```

I ran the container and confirmed it was running -- it should since all it does is sleep. I then ran a bash
shell in the container using ``docker exec`` to start the server manually to understand why it was exiting.

```
$ docker run -p 50099:50099 -d grpc_server/1.0 ; sleep 2 ; docker ps -a
$ docker exec -i -t d6efb1647a84 /bin/bash
root@d6efb1647a84:/# python checker_server.py  <- shows why exiting
Traceback (most recent call last):
  File "checker_server.py", line 7, in <module>
    import checker_pb2
  File "/checker_pb2.py", line 197, in <module>
    _sym_db.RegisterServiceDescriptor(_CHECKER)
AttributeError: 'SymbolDatabase' object has no attribute ‘RegisterServiceDescriptor'
```

In my case, there were old images laying around and I needed to remove them and do a rebuild. 
So I remove the sleep from my Dockerfile so that my grpc server application will run.

Now, I run the container without the sleep and it stays up.

```
$ docker run -p 50099:50099 -d grpc_server/1.0 ; sleep 2 ; docker ps -a
82f287b36b016959d5937ddaa8cfb3209b1ed2335615ac31253d865dedbfaf61
CONTAINER ID        IMAGE               COMMAND                  CREATED             STATUS              PORTS                      NAMES
82f287b36b01        grpc_server/1.0     "python checker_se..."   3 seconds ago       Up 2 seconds        0.0.0.0:50099->50099/tcp   practical_meninsky
```

I then run the client to ensure it runs properly.

```
$ python checker_client.py 0                <-- I pass in a 0 to indicate local docker container
checker client received: iPhone 8s, None, None
checker client received: 2
```

Tag the image for push to your docker registry (in the example, I use a fictitious server my.docker-reg.org):

```
$ docker tag grpc_server/1.0 my.docker-reg.org/dperique_grpc_demo:v1
$ docker images
REPOSITORY                           TAG                 IMAGE ID            CREATED             SIZE
grpc_server/1.0                      latest              c19938e1707c        7 minutes ago       801MB
my.docker-reg.org/dperique_grpc_demo   v1               c19938e1707c        7 minutes ago       801MB

$ docker push my.docker-reg.org/dperique_grpc_demo:v1
```

Take a look at the deployment yaml and note that it will creates 3 replicas.  The yaml also shows how
to add environment variable access to the containers, the image name, and imagePullPolicy.

```
$ cat grpc_demo_deployment.yaml 
apiVersion: extensions/v1beta1
kind: Deployment
metadata:
  name: dperique-grpc-demo
spec:
  replicas: 3       <-- using 3 replicas
  template:
    metadata:
      labels:
        app: dperique_grpc_demo
    spec:
      containers:
      - name: dperique-grpc-demo
        image: my.docker-reg.org/dperique_grpc_demo:v1  <-- using image I just pushed
        imagePullPolicy: Always  <-- using this policy
        ports:
        - containerPort: 50099
        env:
        - name: MY_NODE_NAME  <-- environment variable example
          valueFrom:
            fieldRef:
              fieldPath: spec.nodeName
        - name: MY_POD_NAME
          valueFrom:
            fieldRef:
              fieldPath: metadata.name
        ...
      imagePullSecrets:
        - name: regsecret
```

Now create the deployment on your Kubernetes cluster.

```
$ kubectl create -f grpc_demo_deployment_local.yaml 
```

Check to see that your 3 pods live on different nodes.

```
$ kubectl describe pod| grep Node:
Node:dp-kub-3/192.168.236.123
Node:dp-kub-4/192.168.236.102
Node:dp-kub-1/192.168.236.136
```

Create the service:

```
$ kubectl create -f grpc_demo_deployment_service.yaml 
$ kubectl get svc
NAME                     CLUSTER-IP     EXTERNAL-IP   PORT(S)           AGE
dperique-grpc-service   10.233.2.33    <nodes>       50099:30009/TCP   22h
```

Now, run this infinite loop that runs the client:

```
$ while [ 1 ] ; do python checker_client.py 1 ; echo ""; done

(venv) $ while [ 1 ] ; do python checker_client.py 1 ; echo ""; done

checker client received: Lobster Bisque
checker client received: 3
checker client received: iPhone 8s, dperique-grpc-demo-3234024441-ww0w3, dp-kub-3
checker client received: 2

checker client received: Lobster Bisque
checker client received: 3
checker client received: iPhone 8s, dperique-grpc-demo-3234024441-ww0w3, dp-kub-3
checker client received: 2

checker client received: Lobster Bisque
checker client received: 3
checker client received: iPhone 8s, dperique-grpc-demo-3234024441-rhgdz, dp-kub-1
checker client received: 2

checker client received: Lobster Bisque
checker client received: 3
checker client received: iPhone 8s, dperique-grpc-demo-3234024441-r33s6, dp-kub-4
checker client received: 2

checker client received: Lobster Bisque
checker client received: 3
checker client received: iPhone 8s, dperique-grpc-demo-3234024441-ww0w3, dp-kub-3
checker client received: 2

checker client received: Lobster Bisque
checker client received: 3
checker client received: iPhone 8s, dperique-grpc-demo-3234024441-r33s6, dp-kub-4
checker client received: 2

^Z
[1]+  Stopped                 python checker_client.py 1
(venv) $ kill %1
[1]+  Terminated: 15          python checker_client.py 1
```

You can see the check_server.py server responding on different pods on different nodes.
You can type control-c many times to exit the while loop.  Worst case, type control-z to
halt the process then kill it using something like ``kill %1``.
