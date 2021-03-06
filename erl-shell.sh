#!/bin/bash
# This script provides easy way to debug remote Erlang nodes that is running in a Kubernetes cluster.
#
# Application on remote node should include `:runtime_tools` in it's applications dependencies, otherwise
# you will receive `rpc:handle_call` error.
set -e

function show_help {
  echo "
  ktl erl:shell -lSELECTOR [-nNAMESPACE -cCOOKIE -h]

  Connect to a shell of running Erlang/OTP node. Shell is executed wihin the pod.

  If there are multuple pods that match the selector - random one is choosen.

  Examples:
    ktl erl:shell -lapp=hammer-web           Connect to one of the pods of hammer-web application in default namespace.
    ktl erl:shell -lapp=hammer-web -nweb     Connect to one of the pods of hammer-web application in web namespace.
    ktl erl:shell -lapp=hammer-web -cfoo     Connect to one of the pods of hammer-web application with cookie foo.
"
}

# Read configuration from CLI
while getopts "n:l:c:h" opt; do
  case "$opt" in
    n)  K8S_NAMESPACE=${OPTARG}
        ;;
    l)  K8S_SELECTOR=${OPTARG}
        ;;
    c)  ERL_COOKIE=${OPTARG}
        ;;
    h)  show_help
        exit 0
        ;;
  esac
done

K8S_NAMESPACE=${K8S_NAMESPACE:-default}

# Required part of config
if [ ! $K8S_SELECTOR ]; then
  echo "[E] You need to specify Kubernetes selector with '-l' option."
  exit 1
fi

echo " - Selecting pod with '-l ${K8S_SELECTOR} --namespace=${K8S_NAMESPACE}' selector."
POD_NAME=$(
  kubectl get pods --namespace=${K8S_NAMESPACE} \
    -l ${K8S_SELECTOR} \
    -o jsonpath='{.items[0].metadata.name}' \
    --field-selector=status.phase=Running
)

echo " - Resolving pod ip from pod '${POD_NAME}' environment variables."
POD_IP=$(
  kubectl get pod ${POD_NAME} \
    --namespace=${K8S_NAMESPACE} \
    -o jsonpath='{$.status.podIP}'
)
POD_DNS=$(echo $POD_IP | sed 's/\./-/g')."${K8S_NAMESPACE}.pod.cluster.local"

echo " - Entering shell on remote Erlang/OTP node."
set -x
kubectl exec ${POD_NAME} --namespace=${K8S_NAMESPACE} \
  -it \
  -- /bin/sh -c 'erl -name debug_cli_'$(whoami)'@'${POD_DNS}' -setcookie ${ERLANG_COOKIE} -hidden -remsh $(epmd -names | tail -n 1 | awk '"'"'{print $2}'"'"')@'${POD_DNS}
set +x
