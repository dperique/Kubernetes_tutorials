# Running kubectl and minikube on two different machines

Sometimes you want to run minikube on some machine -- because it's simple, etc.

But, you want to be able to manage it via kubectl from another machine.

To do this, you just need to be able to authenticate kubectl with the minikube cluster.
Let's say I have minikube on my Mac.  I want to be able to control that minikube
cluster from a Ubuntu VM (for whatever reason) -- and not in the usual way by
running kubectl on my Mac where minikube is running.

Here's how I did it:

Get minikube installed on your Mac, or wherever — using vbox or VMware (maybe you already have this).
Ensure that ‘kubectl get nodes’ works.

Tar up your .minikube certs and .kube configurations.  The .minikube and .kube directories are where
these things reside.
```
$ cd ~
$ tar czvf /tmp/dot_mini.tgz ./.minikube/apiserver.* ./.minikube/ca.*
$ tar czvf /tmp/dot_kube.tgz ./.kube/*
```

scp the two files we just created above to your user on your ubuntu VM

get kubectl onto your ubuntu VM

login as your user onto your ubuntu VM

tar xzvf the above two files into your user’s home dir

On your ubuntu VM (which is NOT running minikube), ensure you can
kubectl to it.
```
$ kubectl get nodes
NAME       STATUS    AGE       VERSION
minikube   Ready     22d       v1.6.0
```

Try out the usual minikube helloworld sanity test with a few tiny tweaks
specifically to avoid dealing with the minikube command and just treating
the so-called "minikube" as just a Kubernetes cluster with 1 worker.
Original text here: https://github.com/kubernetes/minikube#quickstart

So you can tell where I'm running the commands, note that:
- My Ubuntu VM is called ‘spooner2’.
- My mac is called ‘Vicky'

These commands below are an example using the same text from the above link for the Minikube Quickstart
except, we are not running the 'minikube' command on my Ubuntu VM.  Everything else is identical.
```
dperiquet@spooner2:~$ kubectl run hello-minikube --image=gcr.io/google_containers/echoserver:1.4 --port=8080
deployment "hello-minikube" created

dperiquet@spooner2:~$ kubectl get deployments
NAME             DESIRED   CURRENT   UP-TO-DATE   AVAILABLE   AGE
hello-minikube   1         1         1            0           3s

dperiquet@spooner2:~$ kubectl expose deployment hello-minikube --type=NodePort
service "hello-minikube" exposed

dperiquet@spooner2:~$ kubectl get svc
NAME             CLUSTER-IP   EXTERNAL-IP   PORT(S)          AGE
hello-minikube   10.0.0.15    <nodes>       8080:31250/TCP   4s
kubernetes       10.0.0.1     <none>        443/TCP          22d

dperiquet@spooner2:~$ kubectl get pod
NAME                             READY     STATUS              RESTARTS   AGE
hello-minikube-938614450-xc7r9   0/1       ContainerCreating   0          24s
```

Note that I don’t have the minikube command on my VM so I run this separately on my Mac where
the minikube command is installed.
```
Vicky:~ dennis.periquet$ minikube service hello-minikube --url
http://192.168.99.100:31250
```

Now taking that result, we can see that the pod is working and service is working just like
in the original minikube example.
```
dperiquet@spooner2:~$ curl http://192.168.99.100:31250
CLIENT VALUES:
client_address=172.17.0.1
command=GET
real path=/
query=nil
request_version=1.1
request_uri=http://192.168.99.100:8080/

SERVER VALUES:
server_version=nginx: 1.10.0 - lua: 10001

HEADERS RECEIVED:
accept=*/*
host=192.168.99.100:31250
user-agent=curl/7.47.0
BODY:
-no body in request-
dperiquet@spooner2:~$
```
