# Tips for Kubernetes setup

## How to setup Kubernetes docker registry keys

Inspired by [docker secrets doc].
[docker secrets doc]: https://kubernetes.io/docs/concepts/configuration/secret/

If you are going to deploy from your local docker registry, you can create your docker registry
and then tell Kubernetes to pull images from there.  The default is to pull them from hub.docker.com.
In the example below, we assume that I already created my own docker registry docker.dennis.com.

The first thing you need to do is setup the docker-registry secret like in this example:
```
$ kubectl create secret docker-registry myregsecret \
                 --docker-server=docker.dennis.com \
                 --docker-username=dperique --docker-password=aPassword \
                 --docker-email=dperique@gmail.com
```

Then modify your deployment yaml file to use that secret in the imagePullSecrets entry like in
this example:

```
$ cat sample_deployment.yaml 
apiVersion: extensions/v1beta1
kind: Deployment
metadata:
  name: dperique-demo
spec:
  replicas: 1
  template:
    metadata:
      labels:
        app: dperique_demo
    spec:
      containers:
      - name: dperique-demo
        image: docker.dennis.com/dperique_demo:v1   <-- note the location of the image
        ports:
        - containerPort: 30099
      imagePullSecrets:
        - name: myregsecret       <-- note the use of the myregsecret secret
```

Now when you create the above deployment, your image will come from docker.dennis.com/dperique_demo:v1.

To see the secret (and to illustrate why you should not allow just anyone to have access to your
Kubernetes cluster via giving them the certificates for kubectl), do this:
```
$ kubectl get secret/myregsecret -o yaml
apiVersion: v1
data:
  .dockercfg: eyJkb2NrZXIuZGVubmlzLmNvbSI6eyJ1c2VybmFtZSI6ImRwZXJpcXVlIiwicGFzc3dvcmQiOiJhUGFzc3dvcmQiLCJlbWFpbCI6ImRwZXJpcXVlQGdtYWlsLmNvbSIsImF1dGgiOiJaSEJsY21seGRXVTZZVkJoYzNOM2IzSmsifX0=
kind: Secret
metadata:
  creationTimestamp: 2017-08-08T19:55:48Z
  name: myregsecret
  namespace: default
  resourceVersion: "5215728"
  selfLink: /api/v1/namespaces/default/secrets/myregsecret
  uid: 92d111a2-7c73-11e7-8016-fa163ebc52de
type: kubernetes.io/dockercfg
```

Now that you have the hex string, do this to see the decoded version (including my password which is revealeed as "aPassword"):
```
$ echo eyJkb2NrZXIuZGVubmlzLmNvbSI6eyJ1c2VybmFtZSI6ImRwZXJpcXVlIiwicGFzc3dvcmQiOiJhUGFzc3dvcmQiLCJlbWFpbCI6ImRwZXJpcXVlQGdtYWlsLmNvbSIsImF1dGgiOiJaSEJsY21seGRXVTZZVkJoYzNOM2IzSmsifX0= | base64 --decode
{"docker.dennis.com":{"username":"dperique","password":"aPassword","email":"dperique@gmail.com","auth":"ZHBlcmlxdWU6YVBhc3N3b3Jk"}}`
```

If you want to get rid of that secret, you can just do:
```
$ kubectl delete secret myregsecret
```

