# Use Kubspray (aka Kargo) to create a single node Kubernetes cluster

[Kargo] is a tool that can be used to bring up a Kubernetes cluster.  I found that you
can take a single machine, run Kargo on it, and bring up a single node Kubernetes cluster on that same
machine.  In short, that one machine can:
- Run Kargo
- Act as Kubernetes master
- Act as Kubernetes worker node
- Run kubectl 

[Kargo]: https://github.com/kubernetes-incubator/kubespray
This gives you functionality similar to [minikube] except you don't need a VM running as the minikube
worker.  This is convenient if you want to simplify things (e.g., for development purposes or for learning
purposes) and/or cannot run a VM inside your machine (e.g., because it too might be a VM running on a
hypervisor that does not support nested virtualization.

[minikube]: https://github.com/kubernetes/minikube
I'll refer to this as an all-in-one Kubernetes cluster.  This is what I did to create one:

Make a Unbuntu VM (I used Xenial 16.04) or get a physical Ubuntu machine.  I call the machine 'babykube'.
```
$ ssh ubuntu@192.168.99.134
vi /etc/hosts ;# add an entry for "192.168.99.143 babykube.dpnet.com babykube"
ping babykube
```
Set it up so that you can ssh to babykube as root from the host babykube and without any yes/no questions.
This means you will have to generate and add ssh keys for passwordless login:
```
sudo su
cd
ssh-keygen
cd .ssh
cp id_rsa.pub authorized_keys
```

You should also add this to your .ssh/config file to avoid the yes/no questions:
```
Host babykube*
   StrictHostKeyChecking no
   UserKnownHostsFile=/dev/null
   CheckHostIP=no
```
Clone the kubespray repo, make an inventory.ini file (mine is shown below).
```
root@babykube:~# mkdir mygit
root@babykube:~# cd mygit/
root@babykube:~/mygit# git clone https://github.com/kubernetes-incubator/kubespray
Cloning into 'kubespray'...
remote: Counting objects: 14268, done.
remote: Total 14268 (delta 0), reused 0 (delta 0), pack-reused 14268
Receiving objects: 100% (14268/14268), 5.65 MiB | 0 bytes/s, done.
Resolving deltas: 100% (7614/7614), done.
Checking connectivity... done.

root@babykube:~/mygit# cd kubespray/inventory/
root@babykube:~/mygit# vi kubespray/inventory/inventory.ini
...
root@babykube:~/mygit/kubespray/inventory# cat inventory.ini
babykube.dpnet.com ansible_host=192.168.99.134 ansible_user=root

[kube-master]
babykube.dpnet.com

[etcd]
babykube.dpnet.com

[kube-node]
babykube.dpnet.com

[k8s-cluster:children]
kube-node
kube-master
```

From your Ubuntu machine, ssh to itself (to ensure you can successfully) and then install ansible.
Kubespray requires Ansible 2.3.1 or later.
```
root@babykube:/home/ubuntu# ssh babykube
root@babykube:/home/ubuntu# sudo apt-add-repository ppa:ansible/ansible
root@babykube:/home/ubuntu# sudo apt-get update
root@babykube:/home/ubuntu# sudo apt-get install ansible
```

Install Jinja 2.9
```
root@babykube:/home/ubuntu# tar xzvf Jinja2-2.9.6.tar.gz 
root@babykube:/home/ubuntu# cd Jinja2-2.9.6
root@babykube:/home/ubuntu/Jinja2-2.9.6# python setup.py install
```

You will also have to install pip and python-netaddr (pip install netaddr) -- not shown.

Tweak the main.yaml including the networking method -- I used 'calico'.
```
root@babykube:~/mygit/kubespray# vi roles/kubespray-defaults/defaults/main.yaml
```
Run the ansible playbook called cluster.yml.  As you can see, mine took about 4 minutes.
```
root@babykube:~/mygit/kubespray# ansible-playbook -i ./inventory/inventory.ini cluster.yml -b -v --flush-cache
...
Saturday 22 July 2017  22:58:24 +0000 (0:00:00.012)       0:04:03.481 ********* 
=============================================================================== 
download : Download containers if pull is required or told to always pull -- 20.67s
docker : Docker | pause while Docker restarts -------------------------- 10.02s
download : Download containers if pull is required or told to always pull --- 8.32s
docker : ensure docker packages are installed --------------------------- 8.31s
kubernetes/master : Master | wait for the apiserver to be running ------- 6.26s
etcd : wait for etcd up ------------------------------------------------- 5.80s
kubernetes/preinstall : Install latest version of python-apt for Debian distribs --- 4.58s
download : Download containers if pull is required or told to always pull --- 4.46s
docker : ensure docker repository is enabled ---------------------------- 3.80s
download : Download containers if pull is required or told to always pull --- 3.59s
kubernetes/preinstall : Install packages requirements ------------------- 3.48s
download : Download containers if pull is required or told to always pull --- 3.21s
download : Download containers if pull is required or told to always pull --- 3.13s
docker : Docker | reload docker ----------------------------------------- 2.34s
download : Download containers if pull is required or told to always pull --- 2.12s
download : Download containers if pull is required or told to always pull --- 2.04s
download : Download containers if pull is required or told to always pull --- 2.03s
download : Download containers if pull is required or told to always pull --- 1.93s
kubernetes-apps/ansible : Kubernetes Apps | Start Resources ------------- 1.72s
download : Download containers if pull is required or told to always pull --- 1.69s
```

If kubectl config is not there, you will have to create one like this (in this example,
I named my cluster as 'babykube1' so adjust accordingly):

```
cd /etc/kubernetes/ssl

kubectl config set-cluster babykube1 --server=https://babykube1.dpnet.com.com:6443  \
    --certificate-authority=ca.pem

kubectl config set-credentials babykube1-admin \
    --certificate-authority=ca.pem \
    --client-key=admin-babykube1.dpnet.com-key.pem \
    --client-certificate=admin-babykube1.dpnet.com.pem

kubectl config set-context babykube1 --cluster=babykube1 --user=babykube1-admin

kubectl config use-context babykube1
```

Here's the actual output:
```
root@babykube1:~/mygit/kubespray# cd /etc/kubernetes/ssl

root@babykube1:/etc/kubernetes/ssl# kubectl config set-cluster babykube1 --server=https://babykube1.dpnet.com.com:6443  \
>     --certificate-authority=ca.pem
Cluster "babykube1" set.

root@babykube1:/etc/kubernetes/ssl# kubectl config set-credentials babykube1-admin \
>     --certificate-authority=ca.pem \
>     --client-key=admin-babykube1.dpnet.com-key.pem \
>     --client-certificate=admin-babykube1.dpnet.com.pem
User "babykube1-admin" set.

root@babykube1:/etc/kubernetes/ssl# kubectl config set-context babykube1 --cluster=babykube1 --user=babykube1-admin
Context "babykube1" set.

root@babykube1:/etc/kubernetes/ssl# kubectl config use-context babykube1
Switched to context "babykube1".
```

Run the usual Quickstart hello-minikube application to confirm your all-in-one Kubernetes cluster
is functional.

```
root@babykube:~/mygit/kubespray# kubectl get nodes
NAME       STATUS    AGE       VERSION
babykube   Ready     1m        v1.6.7+coreos.0

root@babykube:~/mygit/kubespray# kubectl run hello-minikube --image=gcr.io/google_containers/echoserver:1.4 --port=8080
deployment "hello-minikube" created

root@babykube:~/mygit/kubespray# kubectl get deployments
NAME             DESIRED   CURRENT   UP-TO-DATE   AVAILABLE   AGE
hello-minikube   1         1         1            1           11s

root@babykube:~/mygit/kubespray# kubectl get svc
NAME         CLUSTER-IP   EXTERNAL-IP   PORT(S)   AGE
kubernetes   10.233.0.1   <none>        443/TCP   3m

root@babykube:~/mygit/kubespray# kubectl get pod
NAME                             READY     STATUS    RESTARTS   AGE
hello-minikube-938614450-1ssjj   1/1       Running   0          19s

root@babykube:~/mygit/kubespray# kubectl expose deployment hello-minikube --type=NodePort
service "hello-minikube" exposed

root@babykube:~/mygit/kubespray# kubectl get pod
NAME                             READY     STATUS    RESTARTS   AGE
hello-minikube-938614450-1ssjj   1/1       Running   0          2m
```

Instead of using 'minikube service hello-minikube --url', just run ``kubectl get svc`` to see the
TCP port to use in the curl command later.
```
root@babykube:~/mygit/kubespray# kubectl get svc
NAME             CLUSTER-IP      EXTERNAL-IP   PORT(S)          AGE
hello-minikube   10.233.35.171   <nodes>       8080:31088/TCP   50s  <-- use this port
kubernetes       10.233.0.1      <none>        443/TCP          6m
```

Now that you have the url, use curl just like the in the minikube example.
```
root@babykube:~/mygit/kubespray# curl http://192.168.99.134:31088
CLIENT VALUES:
client_address=192.168.99.134
command=GET
real path=/
query=nil
request_version=1.1
request_uri=http://192.168.99.134:8080/

SERVER VALUES:
server_version=nginx: 1.10.0 - lua: 10001

HEADERS RECEIVED:
accept=*/*
host=192.168.99.134:31088
user-agent=curl/7.47.0
BODY:
```
