BUILDER_IMAGE=paketobuildpacks/builder:0.1.361-tiny
LIFECYCLE_IMAGE=buildpacksio/lifecycle:0.16.3
RUN_IMAGE=paketobuildpacks/run:tiny
IMAGE_NAME=image-registry.openshift-image-registry.svc:5000/quarkus-hello

function generatePipelineRun() {
    cat <<EOF | kubectl apply -f -
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: ws-pvc
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
            value: https://github.com/quarkusio/quarkus-quickstarts.git
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
            value: getting-started
          - name: CNB_BUILDER_IMAGE
            value: ${BUILDER_IMAGE}
          - name: CNB_LIFECYCLE_IMAGE
            value: ${LIFECYCLE_IMAGE}
          - name: RUN_IMAGE
            value: ${RUN_IMAGE}
          - name: ENV_VARS
            value:
              - BP_NATIVE_IMAGE=false
              - BP_MAVEN_BUILT_ARTIFACT=target/quarkus-app/lib/ target/quarkus-app/*.jar target/quarkus-app/app/ target/quarkus-app/quarkus/
              - BP_MAVEN_BUILD_ARGUMENTS=package -DskipTests=true -Dmaven.javadoc.skip=true -Dquarkus.package.type=fast-jar
  workspaces:
    - name: source-ws
      subPath: source
      persistentVolumeClaim:
        claimName: ws-pvc
    - name: cache-ws
      subPath: cache
      persistentVolumeClaim:
        claimName: ws-pvc
EOF
}
function basicAuth() {
  cat <<EOF > auth.json
{"image-registry.openshift-image-registry.svc:5000":"Basic $(echo "kubeadmin:$(oc whoami -t)" | tr -d '\n' | base64)"}
EOF
  kubectl delete cm registry-creds; kubectl create cm registry-creds --from-file=auth.json

  echo "############################################################################"
  echo "Test using Basic auth on ocp - https://github.com/buildpacks/spec/issues/277#issuecomment-992900561"
  echo "Registry: image-registry.openshift-image-registry.svc:5000"
  echo "Username: kubeadmin"
  echo "Password: $(oc whoami -t)"
  echo "ConfigMap auth.json decoded: $(kubectl get cm/registry-creds -ojson | jq -r '.data."auth.json" | .[59: (. | length - (3 | tonumber))]' | base64 -d)"
  echo "############################################################################"
}

function bearerAuth() {
  cat <<EOF > auth.json
{"image-registry.openshift-image-registry.svc:5000":"Bearer $(echo "$(oc whoami -t)")"}
EOF
  kubectl delete cm registry-creds; kubectl create cm registry-creds --from-file=auth.json

  echo "############################################################################"
  echo "Test using Bearer auth on ocp"
  echo "Registry: image-registry.openshift-image-registry.svc:5000"
  echo "Token: $(oc whoami -t)"
  echo "############################################################################"
}

function cleanUp() {
  #kubectl delete -f https://raw.githubusercontent.com/redhat-buildpacks/testing/7615593bf80940f8410335decc9eccf6d9eeca18/k8s/tekton/buildpacks-phases.yml
  #kubectl apply -f https://raw.githubusercontent.com/redhat-buildpacks/testing/7615593bf80940f8410335decc9eccf6d9eeca18/k8s/tekton/buildpacks-phases.yml
  kubectl delete -f ./tekton/buildpacks-phases.yml; kubectl apply -f ./tekton/buildpacks-phases.yml
  kubectl delete PipelineRun/buildpacks-phases
  kubectl delete pvc/ws-pvc
}
function checkResult() {
    # Loop until the TaskRun exists
    while [[ -z "$(kubectl get -n default taskrun buildpacks-phases-buildpacks -o json)" ]]; do
        echo "Waiting for TaskRun buildpacks-phases-buildpacks to exist..."
        sleep 10
    done

    # Loop until the status is not null
    while [[ -z "$(tkn taskrun describe buildpacks-phases-buildpacks -ojson | jq '.status.steps[] | select(.container == "step-analyze" and has("terminated"))')" ]]; do
        echo "Waiting for step analyze to start & exit..."
        sleep 5
    done

    echo "########################################################"
    echo "Taskrun status reason: "
    #tkn taskrun describe buildpacks-phases-buildpacks -ojson | jq '.status.steps[] | select(.container == "step-analyze") | .terminated.reason'
    kubectl -n default logs buildpacks-phases-buildpacks-pod -c step-analyze
    echo "########################################################"

    echo "#####################################################"
    echo "To get Tkn taskrun information, execute this command:"
    echo "tkn taskrun describe buildpacks-phases-buildpacks"
    echo "#####################################################"
}

cleanUp
generatePipelineRun
basicAuth
checkResult

#cleanUp
#generatePipelineRun
#bearerAuth
#checkResult
