## Table of Contents

* [How to build a runtime using buildpack](#how-to-build-a-runtime-using-buildpack)
* [0. Common steps](#0-common-steps)
* [1. Pack client](#1-pack-client)
* [2. Pod running the lifecycle creator](#2-pod-running-the-lifecycle-creator)
* [3. Tekton and Pipeline as a Code](#3-tekton-and-pipeline-as-a-code)
* [4. Shipwright and Buildpack](#4-shipwright-and-buildpack)

## How to build a runtime using buildpack

The goal of this project is to test/experiment different approaches to build a runtime using:

- [pack](#1-pack-client) build client
- [pod](#2-pod-running-the-lifecycle-creator) build
- [Tekton & Pipeline As a Code](#3-tekton-and-pipeline-as-a-code)

## 0. Common steps

To play with the different scenarios, a sample [runtime](https://github.com/snowdrop/quarkus-tap-petclinic/tree/main) project is available and can be cloned
```bash
git clone https://github.com/snowdrop/quarkus-tap-petclinic.git quarkus-petclinic && cd quarkus-petclinic
```

To use the builder image (packaging the `build` and `run` stacks) able to build a Quarkus project, then it is needed to use the `quarkus-buildpacks` project.
```bash
git clone https://github.com/quarkusio/quarkus-buildpacks.git && cd quarkus-buildpacks

# Generate the buildpack quarkus images (build, run and builder)
./create-buildpacks.sh
```

**NOTE**: If you plan to use a private container registry, then the images generated should be tagged/pushed to the registry (e.g. `local.registry:5000`)

```bash
# Tag and push the images to the private docker registry
export REGISTRY_HOST="registry.local:5000"
docker tag codejive/buildpacks-quarkus-builder:jvm ${REGISTRY_HOST}/buildpacks-quarkus-builder:jvm
docker tag codejive/buildpacks-quarkus-run:jvm ${REGISTRY_HOST}/buildpacks-quarkus-run:jvm
docker tag codejive/buildpacks-quarkus-build:jvm ${REGISTRY_HOST}/buildpacks-quarkus-build:jvm

docker push ${REGISTRY_HOST}/buildpacks-quarkus-builder:jvm
docker push ${REGISTRY_HOST}/buildpacks-quarkus-run:jvm
docker push ${REGISTRY_HOST}/buildpacks-quarkus-build:jvm
```
You can create a kubernetes cluster locally using `docker desktop` and [kind](https://kind.sigs.k8s.io/docs/user/quick-start/#installation) client and the following script
able to run a k8s cluster, a TLS/secured registry

```bash
git clone https://github.com/snowdrop/k8s-infra.git && cd k8s-infra/kind
./k8s/kind-tls-secured-reg.sh
```
**NOTE**: The certificate generated is copied within the file `$HOME/local-registry.crt` and the user, password to be used to be authenticated
with the registry are respectively `admin` and `snowdrop`

## 1. Pack client

The easiest way to build a `runtime` sample is to use the [pack client](https://buildpacks.io/docs/tools/pack/) with the builder runtime image

**NOTE**: The command should be executed within the sample runtime project or path should be calculated to point to the runtime sample project

```bash
REGISTRY_HOST="registry.local:5000"
pack build ${REGISTRY_HOST}/quarkus-petclinic \
     --path ./ \
     --builder ${REGISTRY_HOST}/buildpacks-builder-quarkus-jvm
```

If you plan to use a different version of the lifecycle, append then the following parameter with the image to be used:
```bash
    --lifecycle-image buildpacksio/lifecycle:919b8ad-linux-arm64
```
**WARNING**: Take care that the lifecycle-image parameter will only be used for `analyze/restore/export` and you would need to update the lifecycle in the builder image for it to be used for `detect/build`

**NOTE**: The `builder.toml` can include or not a section containing the version and/or uri of the lifecycle to be used (e.g version: 0.12.4 or uri: ).
If both are omitted, lifecycle defaults to the version that was last released at the time of pack’s release. In other words, for a particular version of `pack`, this default will not change despite new lifecycle versions being released.

## 2. Pod running the lifecycle creator

First, create a configMap containing the selfsigned certificate of the docker registry under the namespace `demo`
```bash
kubectl create ns demo
cp $HOME/.kind_registry/certs/localhost/client.crt $HOME/.kind_registry/certs/localhost/local-registry-cert.crt
kubectl create -n demo cm local-registry-cert --from-file $HOME/.kind_registry/certs/localhost/local-registry-cert.crt
```

Create a secret containing the `docker json cfg` file with `auths`
```bash
export REGISTRY_HOST="registry.local:5000"
kubectl create secret docker-registry registry-creds -n demo \
  --docker-server="${REGISTRY_HOST}" \
  --docker-username="admin" \
  --docker-password="snowdrop"
```
Next deploy the deployment resource able to perform a build using a runtime example (e.g. )
```bash
kubectl delete -f k8s/build-pod/manifest.yml
kubectl apply -f k8s/build-pod/manifest.yml
```
Watch the progression of the build
```bash
kubectl -n demo logs -lapp=quarkus-petclinic-image-build -c build -f
```

## 3. Tekton and Pipeline as a Code

TODO 

## 4. Shipwright and Buildpack

See project documentation for more information: https://github.com/shipwright-io/build

>**WARNING**: This scenario will not work for the moment due to several issues:
- [issue-838](https://github.com/shipwright-io/build/issues/838)
- [issue-896](https://github.com/shipwright-io/build/issues/896)

To use shipwright, it is needed to have a k8s cluster, local docker registry and tekton installed (v0.41.+)
```bash
curl -s -L "https://raw.githubusercontent.com/snowdrop/k8s-infra/main/kind/kind.sh" | bash -s install --secure-registry
kubectl apply -f https://storage.googleapis.com/tekton-releases/pipeline/previous/v0.44.0/release.yaml
```
Next, deploy the latest release of shipwright
```bash
kubectl apply -f https://github.com/shipwright-io/build/releases/download/v0.11.0/release.yaml
```

Generate a secret to access the container registry

>**Note**: This secret will be used by the serviceAccount of the build's pod to access the container registry

```bash
REGISTRY_HOST="kind-registry:5000" REGISTRY_USER=admin REGISTRY_PASSWORD=snowdrop
kubectl create ns demo
kubectl create secret docker-registry registry-creds -n demo \
  --docker-server="${REGISTRY_HOST}" \
  --docker-username="${REGISTRY_USER}" \
  --docker-password="${REGISTRY_PASSWORD}"
```

Create a serviceAccount that we will use to perform the build and able to be authenticated using the 
secret's credentials with the registry
```bash
kubectl delete -f k8s/shipwright/sa.yml
kubectl apply -f k8s/shipwright/sa.yml
```
Add the selsigned certificate of the private container registry to the Tekton Pipeline 
```bash
REGISTRY_CA_PATH=~/.registry/certs/kind-registry/client.crt
cat ${REGISTRY_CA_PATH} | jq -Rs '{data: {"cert":.}}' > tmp.json | kubectl patch configmap config-registry-cert -n tekton-pipelines --type merge --patch-file tmp.json

kubectl create configmap certificate-registry -n demo \
  --from-file=kind-registry.crt=./k8s/binding/ca-certificates/kind-registry.crt \
  --from-file=type=./k8s/binding/ca-certificates/type
```

Next, deploy some `ClusterBuildStrategy` (ko, kaniko, s2i, buildpacks) using the following command: 
```bash
kubectl delete -f k8s/shipwright/clusterbuildstrategy.yml
kubectl apply -f k8s/shipwright/clusterbuildstrategy.yml
```

As the Paketo builder images are quite big, we suggest to relocate them to the kind registry using the [imgpkg](https://carvel.dev/imgpkg/docs/v0.36.x/install/) tool:
```bash
imgpkg copy -i docker.io/paketobuildpacks/builder:full --to-tar ./k8s/builder-full.tar 
imgpkg copy -i docker.io/paketobuildpacks/builder:base --to-tar ./k8s/builder-base.tar

imgpkg copy --registry-ca-cert-path ~/.registry/certs/kind-registry/client.crt \
  --tar ./k8s/builder-full.tar \
  --to-repo kind-registry:5000/paketobuildpacks/builder
  
imgpkg copy --registry-ca-cert-path ~/.registry/certs/kind-registry/client.crt \
  --tar ./k8s/builder-base.tar \
  --to-repo kind-registry:5000/paketobuildpacks/builder
```
>**Tip**: Useful blog post to customize paketo build: https://blog.dahanne.net/2021/02/06/customizing-cloud-native-buildpacks-practical-examples/
> 
Create a Build object:

```bash
kubectl delete -f k8s/shipwright/build.yml
kubectl apply -f k8s/shipwright/build.yml
```
To view the Build which you just created:

```bash
kubectl get build -n demo                
NAME                     REGISTERED   REASON      BUILDSTRATEGYKIND      BUILDSTRATEGYNAME   CREATIONTIME
buildpack-nodejs-build   True         Succeeded   ClusterBuildStrategy   buildpacks-v3       22s
```

Submit a `BuildRun`:

```bash
kubectl delete buildrun -lbuild.shipwright.io/name=buildpack-nodejs-build -n demo
kubectl create -f k8s/shipwright/buildrun.yml
```
Wait until your BuildRun is completed, and then you can view it as follows:

```bash
kubectl get buildruns -n demo
NAME                           SUCCEEDED   REASON    STARTTIME   COMPLETIONTIME
buildpack-quarkus-buildrun-1   Unknown     Pending   11s  
```

### All steps

Setup first the kind cluster and docker registry
```bash
curl -s -L "https://raw.githubusercontent.com/snowdrop/k8s-infra/main/kind/kind.sh" | bash -s install --delete-kind-cluster
kubectl apply -f https://storage.googleapis.com/tekton-releases/pipeline/previous/v0.44.0/release.yaml
kubectl apply -f https://github.com/shipwright-io/build/releases/download/v0.11.0/release.yaml
```

Next, deploy the Shipwright resources using either an unsecured or secured container registry

1. Unsecured

Upload the paketo builder tar images
```bash
imgpkg copy --registry-insecure \
  --tar ./k8s/builder-base.tar \
  --to-repo kind-registry:5000/paketobuildpacks/builder
```

And deploy in a demo namespace the needed resources
```bash
kubectl create ns demo
kubectl apply  -f k8s/shipwright/unsecured/clusterbuildstrategy.yml
kubectl apply  -f k8s/shipwright/unsecured/build.yml
kubectl create -f k8s/shipwright/unsecured/buildrun.yml
```

2. Secured

Upload the paketo builder tar images
```bash
imgpkg copy --registry-ca-cert-path ~/.registry/certs/kind-registry/client.crt \
  --tar ./k8s/builder-base.tar \
  --to-repo kind-registry:5000/paketobuildpacks/builder
```

And deploy in a demo namespace the needed resources
```bash
kubectl create ns demo
kubectl create configmap certificate-registry -n demo \
  --from-file=kind-registry.crt=./k8s/binding/ca-certificates/kind-registry.crt \
  --from-file=type=./k8s/binding/ca-certificates/type
  
REGISTRY_HOST="kind-registry:5000" REGISTRY_USER=admin REGISTRY_PASSWORD=snowdrop
kubectl create secret docker-registry registry-creds -n demo \
  --docker-server="${REGISTRY_HOST}" \
  --docker-username="${REGISTRY_USER}" \
  --docker-password="${REGISTRY_PASSWORD}"

kubectl apply -f k8s/shipwright/sa.yml  
kubectl apply  -f k8s/shipwright/secured/clusterbuildstrategy.yml
kubectl apply  -f k8s/shipwright/secured/build.yml
kubectl create -f k8s/shipwright/secured/buildrun.yml
```

To clean up
```bash
DIR="unsecured"
kubectl delete secret registry-creds -n demo
kubectl delete -f k8s/shipwright/${DIR}/sa.yml
kubectl delete -f k8s/shipwright/${DIR}/buildrun.yml
kubectl delete -f k8s/shipwright/${DIR}/build.yml
kubectl delete -f k8s/shipwright/${DIR}/clusterbuildstrategy.yml
kubectl delete ns demo
```
