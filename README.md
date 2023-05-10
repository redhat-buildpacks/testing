<p align="center">
 <a href="https://github.com/redhat-buildpacks/testing/actions/workflows/quarkus.yaml" alt="Test Quarkus Extension Status">
 <img src="https://github.com/redhat-buildpacks/testing/actions/workflows/quarkus.yaml/badge.svg"></a>
 <a href="https://github.com/redhat-buildpacks/testing/actions/workflows/pack.yaml" alt="Test Pack CLI Status">
 <img src="https://github.com/redhat-buildpacks/testing/actions/workflows/pack.yaml/badge.svg"></a>
 <a href="https://github.com/redhat-buildpacks/testing/pulse" alt="Activity">
 <img src="https://img.shields.io/github/commit-activity/m/redhat-buildpacks/testing"/></a>
</p>

## Table of Contents

* [How to build a runtime using buildpack](#how-to-build-a-runtime-using-buildpack)
* [0. Common steps](#0-common-steps)
* [1. Quarkus Buildpacks](#1-quarkus-buildpacks)
* [2. Pack client](#2-pack-client)
* [3. Tekton and Pipeline as a Code](#3-tekton-and-pipeline-as-a-code)
* [4. Shipwright and Buildpack](#4-shipwright-and-buildpack)
  * [All steps](#all-steps)


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

You can create a kubernetes `kind` cluster and an unsecure or secured HTTPS docker registry using this bash script:
```bash
curl -s -L "https://raw.githubusercontent.com/snowdrop/k8s-infra/main/kind/kind.sh" | bash -s install
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

To build properly the Quarkus container, we must pass some `BP_***` variables to configure [Java Buildpacks](https://github.com/paketo-buildpacks/java)
as you can hereafter:
```bash
REGISTRY_HOST="kind-registry.local:5000"
docker rmi ${REGISTRY_HOST}/quarkus-hello:1.0
pack build ${REGISTRY_HOST}/quarkus-hello:1.0 \
     --builder paketobuildpacks/builder:tiny \
     -e BP_NATIVE_IMAGE="false" \
     -e BP_MAVEN_BUILT_ARTIFACT="target/quarkus-app/lib/ target/quarkus-app/*.jar target/quarkus-app/app/ target/quarkus-app/quarkus/" \
     -e BP_MAVEN_BUILD_ARGUMENTS="package -DskipTests=true -Dmaven.javadoc.skip=true -Dquarkus.package.type=fast-jar" \
     --builder paketobuildpacks/builder:tiny \
     --path ./quarkus-quickstarts/getting-started
```

>**Trick**: You can discover the builder images available using the command `pack builder suggest` ;-)

Next, start the container and curl the endpoint `curl http://localhost:8080/hello/greeting/coder`
```bash
docker run -i --rm -p 8080:8080 kind-registry.local:5000/quarkus-hello:1.0
```

>**Tip**: If you plan to use a different version of the [lifecycle](https://hub.docker.com/r/buildpacksio/lifecycle/tags), append then the following parameter to th pack command:
```bash
    --lifecycle-image buildpacksio/lifecycle:<TAG>
```


## 3. Tekton and Pipeline as a Code

See the project documentation for more information: https://tekton.dev/

To use Tekton, it is needed to have a k8s cluster (>= 1.24) & local docker registry
```bash
curl -s -L "https://raw.githubusercontent.com/snowdrop/k8s-infra/main/kind/kind.sh" | bash -s install --registry-name kind-registry.local
```
>**Warning**: Append as suffix to the local registry name `*.local` otherwise buildpacks lifecycle will report this error during analyse phase `failed to get previous image: connect to repo store 'kind-registry:5000/buildpack/app': Get "https://kind-registry:5000/v2/": http: server gave HTTP response to HTTPS client`

to install the latest official release (or a specific release)
```bash
kubectl apply -f https://github.com/tektoncd/pipeline/releases/download/v0.47.0/release.yaml
```
and optionally, you can also install the Tekton dashboard
```bash
kubectl apply -f https://storage.googleapis.com/tekton-releases/dashboard/latest/release.yaml
```
Expose the dashboard service externally using an ingress route and open the url in your browser: `tekton-ui.127.0.0.1.nip.io`
```bash
VM_IP=127.0.0.1
kubectl create ingress tekton-ui -n tekton-pipelines --class=nginx --rule="tekton-ui.$VM_IP.nip.io/*=tekton-dashboard:9097"
```

When the platform is ready, you can install the Tekton `Tasks` to git clone, able to perform a buildpacks build adn to execute the phases individually
```bash
kubectl apply -f https://raw.githubusercontent.com/tektoncd/catalog/main/task/git-clone/0.9/git-clone.yaml
kubectl apply -f https://raw.githubusercontent.com/tektoncd/catalog/main/task/buildpacks-phases/0.2/buildpacks-phases.yaml
```

Set the following variable to define the container image to be used to build the application
```bash
IMAGE_NAME=<CONTAINER_REGISTRY>/<ORG>/app
```

It is time to create a `Pipelinerun` to build the Quarkus application
```bash
IMAGE_NAME=kind-registry:5000/buildpack/app
kubectl delete PipelineRun/buildpacks-phases
kubectl delete pvc/env-vars-ws-pvc
cat <<EOF | kubectl apply -f -
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: env-vars-ws-pvc
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 500Mi
---
apiVersion: tekton.dev/v1beta1
kind: PipelineRun
metadata:
  name: buildpacks-phases
  labels:
    app.kubernetes.io/description: "Buildpacks-PipelineRun"
spec:
  pipelineSpec:
    workspaces:
      - name: source-ws
      - name: cache-ws
    tasks:
      - name: fetch-repository
        taskRef:
          name: git-clone
        workspaces:
          - name: output
            workspace: source-ws
        params:
          - name: url
            value: https://github.com/buildpacks/samples
          - name: subdirectory
            value: ""
          - name: deleteExisting
            value: "true"
      - name: buildpacks
        taskRef:
          name: buildpacks-phases
        runAfter:
          - fetch-repository
        workspaces:
          - name: source
            workspace: source-ws
          - name: cache
            workspace: cache-ws
        params:
          - name: APP_IMAGE
            value: ${IMAGE_NAME}
          - name: SOURCE_SUBPATH
            value: apps
          - name: BUILDER_IMAGE
            value: docker.io/cnbs/sample-builder:alpine@sha256:b51367258b3b6fff1fe8f375ecca79dab4339b177efb791e131417a5a4357f42
          - name: ENV_VARS
            value:
              - "ENV_VAR_1=VALUE_1"
              - "ENV_VAR_2=VALUE 2"
          - name: PROCESS_TYPE
            value: ""
  workspaces:
    - name: source-ws
      subPath: source
      persistentVolumeClaim:
        claimName: env-vars-ws-pvc
    - name: cache-ws
      subPath: cache
      persistentVolumeClaim:
        claimName: env-vars-ws-pvc
EOF
```
Follow the execution the pipeline using the dashboard: 

## 4. Shipwright and Buildpack

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

Generate a docker-registry secret

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
Add the selfsigned certificate to a configMap. It will be mounted as a volume to set the env var `SSL_CERT_DIR` used by the go-containerregistry lib (of lifecycle)
to access the registry using the HTTPS/TLS protocol.
```bash
kubectl delete configmap certificate-registry -n demo
kubectl create configmap certificate-registry -n demo \
  --from-file=kind-registry.crt=$HOME/.registry/certs/kind-registry.local/client.crt 
```

Next, install the `Buildpacks BuildStrategy` using the following command:
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
Create the `Build` CR using as source the Quarkus Getting started repository:

```bash
kubectl delete -f k8s/shipwright/secured/build.yml
kubectl apply -f k8s/shipwright/secured/build.yml
```
To view the Build which you just created:

```bash
kubectl get build -n demo
NAME                      REGISTERED   REASON      BUILDSTRATEGYKIND      BUILDSTRATEGYNAME   CREATIONTIME
buildpack-quarkus-build   True         Succeeded   ClusterBuildStrategy   buildpacks          6s
```

Submit a `BuildRun`:

```bash
kubectl delete buildrun -lbuild.shipwright.io/name=buildpack-quarkus-build -n demo
kubectl create -f k8s/shipwright/secured/buildrun.yml
```
Wait until your BuildRun is completed, and then you can view it as follows:

```bash
kubectl get buildruns -n demo
NAME                              SUCCEEDED   REASON      STARTTIME   COMPLETIONTIME
buildpack-quarkus-buildrun-vp2gb   True        Succeeded   2m22s       9s
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
kubectl delete -n demo buildrun -lbuild.shipwright.io/name=buildpack-quarkus-build
kubectl delete -f k8s/shipwright/${DIR}/build.yml
kubectl delete -f k8s/shipwright/${DIR}/clusterbuildstrategy.yml
kubectl delete ns demo
```