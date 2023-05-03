## Table of Contents

* [How to build a runtime using buildpack](#how-to-build-a-runtime-using-buildpack)
* [0. Common steps](#0-common-steps)
* [1. Quarkus Buildpacks](#1-quarkus-buildpacks)
* [2. Pack client](#2-pack-client)
* [3. Shipwright and Buildpack](#3-shipwright-and-buildpack)
  * [All steps](#all-steps)
* [4. Tekton and Pipeline as a Code](#4-tekton-and-pipeline-as-a-code)

## How to build a runtime using buildpack

The goal of this project is to test/experiment different approaches to build a runtime using:

- [Quarkus buildpacks](#1-quarkus-buildpacks)
- [pack](#2-pack-client) build client
- [Shipwright](#3-shipwright-and-buildpack)
- [Tekton & Pipeline As a Code](#4-tekton-and-pipeline-as-a-code)

## 0. Common steps

To play with the different scenarios, git clone this Quarkus [runtime](https://github.com/snowdrop/quarkus-tap-petclinic/tree/main) project.
```bash
git clone https://github.com/quarkusio/quarkus-quickstarts.git
cd quarkus-quickstarts/getting-started
mvn quarkus:dev
```
In a separate terminal, curl the HTTP endpoint
```bash
curl http://localhost:8080/hello/greeting/coder
hello coder
```

You can create locally a kubernetes `kind` cluster and a secured HTTPS docker registry using this bash script:
```bash
curl -s -L "https://raw.githubusercontent.com/snowdrop/k8s-infra/main/kind/kind.sh" | bash -s install --secure-registry
```

>**Note**: Use the command `... | bash -s -h` to see the usage and notice end of the execution of the script where you can find the selfsigned certificate

## 1. Quarkus Buildpacks

Add first the following Quarkus extension to the Quarkus Getting started example able to build the quarkus example using the [Java Buildpacks client](https://github.com/snowdrop/java-buildpack-client).
```bash
quarkus extension add 'container-image-buildpack'
```
Do the build using as builder image `paketobuildpacks/builder:tiny` and where you pass the needed `BP_***` env variables in order to configure 
properly the Quarkus mavn build:
```bash
mvn package \
 -Dquarkus.container-image.image=kind-registry.local:5000/quarkus-hello:1.0 \
 -Dquarkus.buildpack.jvm-builder-image=paketobuildpacks/builder:tiny \
 -Dquarkus.buildpack.builder-env.BP_NATIVE_IMAGE="false" \
 -Dquarkus.buildpack.builder-env.BP_MAVEN_BUILT_ARTIFACT="target/quarkus-app/lib/ target/quarkus-app/*.jar target/quarkus-app/app/ target/quarkus-app/quarkus/" \
 -Dquarkus.buildpack.builder-env.BP_MAVEN_BUILD_ARGUMENTS="package -DskipTests=true -Dmaven.javadoc.skip=true -Dquarkus.package.type=fast-jar" \
 -Dquarkus.container-image.build=true \
 -Dquarkus.container-image.push=true
```
Next, start the container and curl the endpoint
```bash
docker run -i --rm -p 8080:8080 kind-registry.local:5000/quarkus-hello:1.0
```

## 2. Pack client

To validate this scenario we will use the [pack client](https://buildpacks.io/docs/tools/pack/).

>>**NOTE**: The pack client uses by default the Paketo builder `tiny` [image](https://github.com/paketo-buildpacks/tiny-builder). So it is then not needed to specify it as parameter !

To build properly the Quarkus container, we must pass some `BP_***` variables to configure [Java Buildpacks](https://github.com/paketo-buildpacks/java)
as you can hereafter:
```bash
REGISTRY_HOST="kind-registry.local:5000"
docker rmi ${REGISTRY_HOST}/quarkus-hello:1.0
pack build ${REGISTRY_HOST}/quarkus-hello:1.0 \
     -e BP_NATIVE_IMAGE="false" \
     -e BP_MAVEN_BUILT_ARTIFACT="target/quarkus-app/lib/ target/quarkus-app/*.jar target/quarkus-app/app/ target/quarkus-app/quarkus/" \
     -e BP_MAVEN_BUILD_ARGUMENTS="package -DskipTests=true -Dmaven.javadoc.skip=true -Dquarkus.package.type=fast-jar" \
     --path ./quarkus-quickstarts/getting-started
```
Next, start the container and curl the endpoint `curl http://localhost:8080/hello/greeting/coder`
```bash
docker run -i --rm -p 8080:8080 kind-registry.local:5000/quarkus-hello
```

>**Tip**: If you plan to use a different version of the [lifecycle](https://hub.docker.com/r/buildpacksio/lifecycle/tags), append then the following parameter to th pack command:
```bash
    --lifecycle-image buildpacksio/lifecycle:<TAG>
```

## 3. Shipwright and Buildpack

See the project documentation for more information: https://github.com/shipwright-io/build

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
REGISTRY_HOST="kind-registry.local:5000" REGISTRY_USER=admin REGISTRY_PASSWORD=snowdrop
kubectl create ns demo
kubectl create secret docker-registry registry-creds -n demo \
  --docker-server="${REGISTRY_HOST}" \
  --docker-username="${REGISTRY_USER}" \
  --docker-password="${REGISTRY_PASSWORD}"
```

Create a serviceAccount that the platform will use to perform the build and able to be authenticated using the
secret's credentials with the registry
```bash
kubectl delete -f k8s/shipwright/secured/sa.yml
kubectl apply -f k8s/shipwright/secured/sa.yml
```
Add the selfsigned certificate of the private container registry to the Tekton Pipeline
```bash
REGISTRY_CA_PATH=~/.registry/certs/kind-registry.local/client.crt
cat ${REGISTRY_CA_PATH} | jq -Rs '{data: {"cert":.}}' > tmp.json | kubectl patch configmap config-registry-cert -n tekton-pipelines --type merge --patch-file tmp.json

kubectl delete  configmap certificate-registry -n demo
kubectl create configmap certificate-registry -n demo \
  --from-file=kind-registry.crt=./k8s/shipwright/secured/binding/ca-certificates/kind-registry.local.crt
```

Next, deploy some `ClusterBuildStrategy` (ko, kaniko, s2i, buildpacks) using the following command:
```bash
kubectl delete -f k8s/shipwright/secured/clusterbuildstrategy.yml
kubectl apply -f k8s/shipwright/secured/clusterbuildstrategy.yml
```

As the Paketo builder images are quite big, we suggest to relocate them to the kind registry using the [imgpkg](https://carvel.dev/imgpkg/docs/v0.36.x/install/) tool:
```bash
imgpkg copy -i docker.io/paketobuildpacks/builder:full --to-tar ./k8s/builder-full.tar 
imgpkg copy -i docker.io/paketobuildpacks/builder:base --to-tar ./k8s/builder-base.tar

imgpkg copy --registry-ca-cert-path ~/.registry/certs/kind-registry.local/client.crt \
  --registry-username admin --registry-password snowdrop \
  --tar ./k8s/builder-full.tar \
  --to-repo kind-registry.local:5000/paketobuildpacks/builder
  
imgpkg copy --registry-ca-cert-path ~/.registry/certs/kind-registry.local/client.crt \
  --registry-username admin --registry-password snowdrop \
  --tar ./k8s/builder-base.tar \
  --to-repo kind-registry.local:5000/paketobuildpacks/builder
```
>**Tip**: Useful blog post to customize paketo build: https://blog.dahanne.net/2021/02/06/customizing-cloud-native-buildpacks-practical-examples/
>
Create a Build object:

```bash
kubectl delete -f k8s/shipwright/secured/build.yml
kubectl apply -f k8s/shipwright/secured/build.yml
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
kubectl create -f k8s/shipwright/secured/buildrun.yml
```
Wait until your BuildRun is completed, and then you can view it as follows:

```bash
kubectl get buildruns -n demo
NAME                              SUCCEEDED   REASON      STARTTIME   COMPLETIONTIME
buildpack-nodejs-buildrun-vp2gb   True        Succeeded   2m22s       9s
```

### All steps

Setup first the kind cluster and docker registry
```bash
curl -s -L "https://raw.githubusercontent.com/snowdrop/k8s-infra/main/kind/kind.sh" | bash -s install --delete-kind-cluster
```
>**Note**: To install a secured (HTTPS and authentication) docker registry, pass the parameter: --secure-registry

Next, install Tekton and Shipwright
```bash
kubectl apply -f https://storage.googleapis.com/tekton-releases/pipeline/previous/v0.44.0/release.yaml
kubectl apply -f https://github.com/shipwright-io/build/releases/download/v0.11.0/release.yaml
```

And finally, deploy the resources using either an `unsecured` or `secured` container registry

1. Unsecured

Upload the paketo builder tar image `builder-base.tar` or `builder-full.tar`
```bash
imgpkg copy --registry-insecure \
  --tar ./k8s/builder-base.tar \
  --to-repo kind-registry.local:5000/paketobuildpacks/builder
```

And deploy in a demo namespace the needed resources
```bash
kubectl create ns demo
kubectl apply  -f k8s/shipwright/unsecured/clusterbuildstrategy.yml
kubectl apply  -f k8s/shipwright/unsecured/build.yml
kubectl create -f k8s/shipwright/unsecured/buildrun.yml
```

2. Secured

Upload the paketo builder tar image `builder-base.tar` or `builder-full.tar`
```bash
imgpkg copy --registry-ca-cert-path ~/.registry/certs/kind-registry.local/client.crt \
  --registry-username admin --registry-password snowdrop \
  --tar ./k8s/builder-base.tar \
  --to-repo kind-registry.local:5000/paketobuildpacks/builder
```

And deploy in a demo namespace the needed resources
```bash
kubectl create ns demo
kubectl create configmap certificate-registry -n demo \
  --from-file=kind-registry.crt=./k8s/shipwright/secured/binding/ca-certificates/kind-registry.local.crt
  
REGISTRY_HOST="kind-registry.local:5000" REGISTRY_USER=admin REGISTRY_PASSWORD=snowdrop
kubectl create secret docker-registry registry-creds -n demo \
  --docker-server="${REGISTRY_HOST}" \
  --docker-username="${REGISTRY_USER}" \
  --docker-password="${REGISTRY_PASSWORD}"

kubectl apply  -f k8s/shipwright/secured/sa.yml  
kubectl apply  -f k8s/shipwright/secured/clusterbuildstrategy.yml
kubectl apply  -f k8s/shipwright/secured/build.yml
kubectl create -f k8s/shipwright/secured/buildrun.yml
```

To clean up
```bash
DIR="unsecured"
kubectl delete secret registry-creds -n demo
kubectl delete -f k8s/shipwright/${DIR}/sa.yml
kubectl delete -n demo buildrun -lbuild.shipwright.io/name=buildpack-nodejs-build
kubectl delete -f k8s/shipwright/${DIR}/build.yml
kubectl delete -f k8s/shipwright/${DIR}/clusterbuildstrategy.yml
kubectl delete ns demo
```

## 4. Tekton and Pipeline as a Code

TODO