#!/bin/bash

OAI5G_CHARTS="$HOME"/oai-cn5g-fed/charts
OAI5G_CORE="$OAI5G_CHARTS"/oai-5g-core
OAI5G_BASIC="$OAI5G_CORE"/oai-5g-basic
OAI5G_RAN="$OAI5G_CHARTS"/oai-5g-ran

#Default namespace
#ns="oai5g"

function usage() {
    echo "USAGE: $(basename "$0") start namespace fit_amf fit_spgwu fit_gnb fit_ue | stop namespace"
    echo "This scripts launches/deletes the OAI5G pods on namespace $ns over the Sopnode platform"
    echo "Requirements: 4 R2lab FIT nodes already attached to the k8s cluster to run the following pods: "
    echo "  - oai-amf"
    echo "  - oai-spgwu-tiny"
    echo "  - oai-gnb"
    echo "  - oai-nr-ue"
    exit 1
}

function init() {
    # Following should be done once per demo.

    echo "init: ensure spray is installed and possibly create secret docker-registry"
    # Remove pulling limitations from docker-hub with anonymous account
    kubectl delete secret regcred || true
    kubectl create secret docker-registry regcred --docker-server=https://index.docker.io/v1/ --docker-username=DUMMY_name --docker-password=DUMMY_pwd --docker-email=DUMMY_email || true

    # Ensure that helm spray plugin is installed
    helm plugin install https://github.com/ThalesGroup/helm-spray || true
}

function start() {
    ns=$1
    shift
    fit_amf=$1
    shift
    fit_spgwu=$1
    shift
    fit_gnb=$1
    shift
    fit_ue=$1
    shift

    echo "Running start() with namespace: $ns, fit_amf:$fit_amf, fit_spgwu:$fit_spgwu, fit_gnb:$fit_gnb, fit_ue:$fit_ue"

    # Check if all FIT nodes are ready
    while :; do
        kubectl wait no --for=condition=Ready $fit_amf $fit_spgwu $fit_gnb $fit_ue && break
        clear
        echo "Wait until all FIT nodes are in READY state"
        kubectl get no
        sleep 5
    done
    kubectl get no

    echo "Run the OAI 5G Core pods"

    echo "cd $OAI5G_BASIC"
    cd "$OAI5G_BASIC"

    echo "helm dependency update"
    helm dependency update

    echo "helm --namespace=$ns spray ."
    helm --create-namespace --namespace=$ns spray .

    echo "Wait until all 5G Core pods are READY"
    kubectl wait pod -n$ns --for=condition=Ready --all

    echo "Run the oai-gnb pod on $fit_gnb"
    echo "cd $OAI5G_RAN"
    cd "$OAI5G_RAN"

    echo "helm --namespace=$ns install oai-gnb oai-gnb/"
    helm --namespace=$ns install oai-gnb oai-gnb/

    echo "Wait until the gNB pod is READY"
    kubectl wait pod -n$ns --for=condition=Ready --all

    echo "Run the oai-nr-ue pod on $fit_ue"

    # Retrieve the IP address of the gnb pod and set it
    GNB_POD_NAME=$(kubectl -n$ns get pods -l app.kubernetes.io/name=oai-gnb -o jsonpath="{.items[0].metadata.name}")
    GNB_POD_IP=$(kubectl -n$ns get pod $GNB_POD_NAME --template '{{.status.podIP}}')
    echo "gNB pod IP is $GNB_POD_IP"
    conf_ue_dir="$OAI5G_RAN/oai-nr-ue"
    cat >/tmp/gnb-values.sed <<EOF
s|  rfSimulator:.*|  rfSimulator: "${GNB_POD_IP}"|
EOF

    echo "(Over)writing oai-nr-ue chart $conf_ue_dir/values.yaml"
    cp $conf_ue_dir/values.yaml /tmp/values-orig.yaml
    sed -f /tmp/gnb-values.sed </tmp/values-orig.yaml >/tmp/values.yaml
    cp /tmp/values.yaml $conf_ue_dir/

    echo "helm --namespace=$ns install oai-nr-ue oai-nr-ue/"
    helm --namespace=$ns install oai-nr-ue oai-nr-ue/

    echo "Wait until oai-nr-ue pod is READY"
    kubectl wait pod -n$ns --for=condition=Ready --all

    UE_POD_NAME=$(kubectl -n$ns get pods -l app.kubernetes.io/name=oai-nr-ue -o jsonpath="{.items[0].metadata.name}")
    echo "Check UE logs"
    kubectl -n$ns logs $UE_POD_NAME -c nr-ue

    echo "RUN OK."
    echo "To clean up all pods, you can run the demo-oai.py --cleanup script. "
}

function stop() {
    ns=$1
    shift

    echo "Running stop() on namespace:$ns"

    res=$(helm -n $ns ls | wc -l)
    if test $res -gt 1; then
        echo "Remove all 5G OAI pods"
        echo "helm -n $ns ls --short --all | xargs -L1 helm --namespace $ns delete"
        helm -n $ns ls --short --all | xargs -L1 helm --namespace $ns delete
        kubectl wait -n $ns --for=delete pod mysql
        kubectl wait -n $ns --for=delete pod oai-amf
        kubectl wait -n $ns --for=delete pod oai-smf
        kubectl wait -n $ns --for=delete pod oai-ausf
        kubectl wait -n $ns --for=delete pod oai-udm
        kubectl wait -n $ns --for=delete pod oai-udr
        kubectl wait -n $ns --for=delete pod oai-nrf
        kubectl wait -n $ns --for=delete pod oai-spgwu-tiny
        kubectl wait -n $ns --for=delete pod oai-gnb
        kubectl wait -n $ns --for=delete pod oai-nr-ue
    else
        echo "OAI5G demo is not running, there is no pod on namespace $ns !"
    fi
    echo "Delete namespace $ns"
    kubectl delete ns $ns
}

if test $# -lt 1; then
    usage
else
    if [ "$1" == "init" ]; then
        if test $# -eq 1; then
            init
        else
            usage
        fi
    elif [ "$1" == "start" ]; then
        if test $# -eq 6; then
            start $2 $3 $4 $5 $6
        else
            usage
        fi
    elif [ "$1" == "stop" ]; then
        if test $# -eq 2; then
            stop $2
        else
            usage
        fi
    else
        usage
    fi
fi
