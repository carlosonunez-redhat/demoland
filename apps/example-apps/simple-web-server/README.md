# Simple Web Server

A simple web server that tells you what kind of request you made of it.

## Running it Locally

Build the container image and create a container from it:

```sh
podman build -t simple-web-server apps/example-apps/simple-web-server/src
podman run --rm --name ws -p 8080:8080 simple-web-server
```

Then visit https://localhost:8080. You should see a screen telling you that
you made a `GET` request.

## Deploying with Kustomize

### Kubernetes

Build the container image and push it into your registry:

```sh
podman build -t registry.example/simple-web-server:v1.0.0 .
podman push registry.example/simple-web-server:v1.0.0
```

Then deploy!

```sh
kubectl apply -k apps/example-apps/simple-web-server/base
```

### OpenShift

Deploy the `ImageStream` that will create a container image for you
automatically:

```sh
oc apply -k apps/example-apps/simple-web-server/imagestream
```
