#!/bin/bash

OAI5G_CHARTS="$HOME"/oai-cn5g-fed/charts
OAI5G_CORE="$OAI5G_CHARTS"/oai-5g-core
OAI5G_BASIC="$OAI5G_CORE"/oai-5g-basic
OAI5G_RAN="$OAI5G_CHARTS"/oai-5g-ran


#Default namespace
ns="oai5g"

function usage() {
    echo "USAGE: `basename "$0"` start|stop"
    echo "This scripts launches the oai5g pods on namespace $ns over the Sopnode platform"
    echo "Requirements: 4 R2lab FIT nodes attached to the k8s cluster: "
    echo "  - oai-amf (fit01)"
    echo "  - oai-spgwu-tiny (fit02)"
    echo "  - oai-gnb (fit03)"
    echo "  - oai-nr-ue (fit09)"
    exit 1
}

function start() {

    # Ensure that helm spray plugin is installed
    helm plugin install https://github.com/ThalesGroup/helm-spray

    # Check if all FIT nodes are ready
    while : ; do
	kubectl wait no --for=condition=Ready fit01 fit02 fit03 fit09 && break
	clear;
	echo "Wait until all FIT nodes are in READY state"; kubectl get no
	sleep 5
    done
    kubectl get no

    echo "Run the OAI 5G Core pods"

    echo "cd $OAI5G_BASIC"
    cd "$OAI5G_BASIC"

    echo "helm dependency update"
    helm dependency update

    echo "helm --namespace=$ns spray ."
    helm --namespace=$ns spray .

    echo "Wait until all 5G Core pods are READY"
    kubectl wait pod -n$ns --for=condition=Ready --all

    echo "Run the oai-gnb pod on fit03"
    echo "cd $OAI5G_RAN"
    cd "$OAI5G_RAN"

    echo "helm --namespace=$ns install oai-gnb oai-gnb/"
    helm --namespace=$ns install oai-gnb oai-gnb/

    echo "Wait until the gNB pod is READY"
    kubectl wait pod -n$ns --for=condition=Ready --all

    echo "Run the oai-nr-ue pod on fit09"

    # Retrieve the IP address of the gnb pod and set it 
    GNB_POD_NAME=$(kubectl -n$ns get pods -l app.kubernetes.io/name=oai-gnb -o jsonpath="{.items[0].metadata.name}")
    GNB_POD_IP=$(kubectl -n$ns get pod $GNB_POD_NAME --template '{{.status.podIP}}')
    echo "gNB pod IP is $GNB_POD_IP"
    conf_ue_dir="$OAI5G_RAN/oai-nr-ue"
    cat > /tmp/gnb-values.sed <<EOF
s|  rfSimulator:.*|  rfSimulator: "${GNB_POD_IP}"|
EOF

    echo "(Over)writing oai-nr-ue chart $conf_ue_dir/values.yaml"
    cp $conf_ue_dir/values.yaml /tmp/values-orig.yaml
    sed -f /tmp/gnb-values.sed < /tmp/values-orig.yaml > /tmp/values.yaml
    cp /tmp/values.yaml $conf_ue_dir/

    echo "helm --namespace=$ns install oai-nr-ue oai-nr-ue/"
    helm --namespace=$ns install oai-nr-ue oai-nr-ue/

    echo "Wait until the NR-UE pod is READY"
    kubectl wait pod -n$ns --for=condition=Ready --all

    UE_POD_NAME=$(kubectl -n$ns get pods -l app.kubernetes.io/name=oai-nr-ue -o jsonpath="{.items[0].metadata.name}")
    echo "Check UE logs"
    kubectl -n$ns logs $UE_POD_NAME -c nr-ue

    echo "RUN OK."
    echo "To clean up all pods, you can run the demo-oai-clean script. "
}

function stop() {
    n=`helm -n $ns ls | wc -l`
    if test $n -gt 1
    then
	echo "Remove all 5G OAI pods"
	echo 'helm -n $ns ls --short --all | xargs -L1 helm --namespace $ns delete'
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
	echo "`basename "$0"` is not running, there is no pod on namespace $ns !"
    fi
}

if test $# -ne 1
then
    usage
else
    if [ "$1" == "start" ]
    then
	start
    elif [ "$1" == "stop" ]
    then
	stop
    else
	usage
    fi
fi
