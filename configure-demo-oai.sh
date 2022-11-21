#!/bin/bash

function update() {
    ns=$1; shift
    fit_amf=$1; shift
    fit_spgwu=$1; shift
    fit_gnb=$1; shift
    fit_ue=$1; shift
    regcred_name=$1; shift
    regcred_password=$1; shift
    regcred_email=$1; shift
    
    #fit_gnb='sopnode-w2.inria.fr'

    echo "Configuring chart $OAI5G_BASIC/values.yaml for R2lab"
    cat > /tmp/demo-oai.sed <<EOF
s|DEF_NS=.*|DEF_NS="${ns}"|
s|DEF_FIT_AMF=.*|DEF_FIT_AMF="${fit_amf}"|
s|DEF_FIT_SPGWU=.*|DEF_FIT_SPGWU="${fit_spgwu}"|
s|DEF_FIT_GNB=.*|DEF_FIT_GNB="${fit_gnb}"|
s|DEF_FIT_UE=.*|DEF_FIT_UE="${fit_ue}"|
s|username=r2labuser|username=${regcred_name}|
s|password=r2labuser-pwd|password=${regcred_password}|
s|email=r2labuser@turletti.com|email=${regcred_email}|
EOF

    cp demo-oai.sh /tmp/demo-oai-orig.sh
    echo "Configuring demo-oai.sh script with possible new R2lab FIT nodes and registry credentials"
    sed -f /tmp/demo-oai.sed < /tmp/demo-oai-orig.sh > /root/demo-oai.sh
    diff /tmp/demo-oai-orig.sh /root/demo-oai.sh
}

if test $# -ne 9; then
    echo "val = $#, val2= $@, val3= "
    echo "USAGE: configure-demo-oai namespace fit_amf fit_spgwu fit_gnb fit_ue regcred_name regcred_password regcred_email "
    exit 1
else
    shift
    echo "Running update with inputs: $@"
    update "$@"
    exit 0
fi
