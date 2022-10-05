#!/bin/bash

# Default k8s namespace and FIT nodes running oai5g pods
DEF_NS="oai5g"
DEF_FIT_AMF="sopnode-w2.inria.fr"
DEF_FIT_SPGWU="sopnode-w2.inria.fr"
DEF_FIT_GNB='sopnode-w2.inria.fr'
DEF_FIT_UE="fit1"


OAI5G_CHARTS="$HOME"/oai-cn5g-fed/charts
OAI5G_CORE="$OAI5G_CHARTS"/oai-5g-core
OAI5G_BASIC="$OAI5G_CORE"/oai-5g-basic
OAI5G_RAN="$OAI5G_CHARTS"/oai-5g-ran


function usage() {
    echo "USAGE:"
    echo "demo-oai.sh init |"
    echo "            start [namespace fit_amf fit_spgwu fit_gnb fit_ue] |"
    echo "            stop [namespace] |"
    echo "            configure-all [fit_amf fit_spgwu fit_gnb fit_ue] |"
    echo "            reconfigure [fit_amf fit_spgwu fit_gnb fit_ue] |"
    echo "            run-ping [namespace] |"
    echo "            start-cn [namespace fit_amf fit_spgwu] |"
    echo "            start-gnb [namespace fit_gnb] |"
    echo "            start-ue [namespace fit_gnb fit_ue] |"
    echo "            stop-cn [namespace] |"
    echo "            stop-gnb [namespace] |"
    echo "            stop-ue [namespace] "
    echo "This script must be run on a FIT k8s worker node"
    echo "Prerequisites: 4 R2lab FIT nodes already running as k8s workers for pods: "
    echo "  - oai-amf"
    echo "  - oai-spgwu-tiny"
    echo "  - oai-gnb"
    echo "  - oai-nr-ue"
    exit 1
}


function configure-oai-5g-basic() {
    fit_amf=$1; shift
    fit_spgwu=$1; shift 

    echo "Configuring chart $OAI5G_BASIC/values.yaml for R2lab"
    cat > /tmp/basic-r2lab.sed <<EOF
s|create: false|create: false|
s|n1IPadd:.*|n1IPadd: "192.168.2.201"|
s|n1Netmask:.*|n1Netmask: "24"|
s|hostInterface:.*|hostInterface: "enp0s25"|
s|amfInterfaceNameForNGAP: "eth0" # If multus creation is true then net1 else eth0|amfInterfaceNameForNGAP: "eth0" # If multus creation is true then net1 else eth0|
s|mnc: "99"|mnc: "95"|
s|servedGuamiMnc0: "99"|servedGuamiMnc0: "95"|
s|plmnSupportMnc: "99"|plmnSupportMnc: "95"|
s|operatorKey:.*|operatorKey: "8e27b6af0e692e750f32667a3b14605d"  # should be same as in subscriber database|  
s|n3Ip:.*|n3Ip: "192.168.2.202"|
s|n3Netmask:.*|n3Netmask: "24"|
s|sgwS1uIf: "eth0"  # n3 interface, net1 if gNB is outside the cluster network and multus creation is true else eth0|sgwS1uIf: "net1"  # n3 interface, net1 if gNB is outside the cluster network and multus creation is true else eth0|
s|pgwSgiIf: "eth0"  # net1 if gNB is outside the cluster network and multus creation is true else eth0 (important because it sends the traffic towards internet)|pgwSgiIf: "eth0"  # net1 if gNB is outside the cluster network and multus creation is true else eth0 (important because it sends the traffic towards internet)|
s|dnsIpv4Address: "172.21.3.100" # configure the dns for UE don't use Kubernetes DNS|dnsIpv4Address: "138.96.0.210" # configure the dns for UE don't use Kubernetes DNS|
s|dnsSecIpv4Address: "172.21.3.100" # configure the dns for UE don't use Kubernetes DNS|dnsSecIpv4Address: "193.51.196.138" # configure the dns for UE don't use Kubernetes DNS|
EOF

    cp "$OAI5G_BASIC"/values.yaml /tmp/basic_values.yaml-orig
    echo "(Over)writing $OAI5G_BASIC/values.yaml"
    sed -f /tmp/basic-r2lab.sed < /tmp/basic_values.yaml-orig > "$OAI5G_BASIC"/values.yaml
    perl -i -p0e "s/nodeSelector: \{\}\noai-spgwu-tiny:/nodeName: \"$fit_amf\"\\n  nodeSelector: \{\}\noai-spgwu-tiny:/s" "$OAI5G_BASIC"/values.yaml
    perl -i -p0e "s/nodeSelector: \{\}\noai-smf:/nodeName: \"$fit_spgwu\"\n  nodeSelector: \{\}\noai-smf:/s" "$OAI5G_BASIC"/values.yaml

    diff /tmp/basic_values.yaml-orig "$OAI5G_BASIC"/values.yaml
    cd "$OAI5G_BASIC"
    echo "helm dependency update"
    helm dependency update
}

function configure-mysql() {

    FUNCTION="mysql"
    DIR="$OAI5G_CORE/$FUNCTION/initialization"
    ORIG_CHART="$OAI5G_CORE/$FUNCTION"/initialization/oai_db-basic.sql
    SED_FILE="/tmp/$FUNCTION-r2lab.sed"

    echo "Configuring chart $ORIG_CHART for R2lab"
    echo "Applying patch to add R2lab SIM info in AuthenticationSubscription table"
    rm -f /tmp/oai_db-basic-patch
    cat << \EOF >> /tmp/oai_db-basic-patch
--- oai_db-basic.sql	2022-09-16 17:18:26.491178530 +0200
+++ new.sql	2022-09-16 17:31:36.091401829 +0200
@@ -191,7 +191,40 @@
 ('208990100001139', '5G_AKA', 'fec86ba6eb707ed08905757b1bb44b8f', 'fec86ba6eb707ed08905757b1bb44b8f', '{\"sqn\": \"000000000020\", \"sqnScheme\": \"NON_TIME_BASED\", \"lastIndexes\": {\"ausf\": 0}}', '8000', 'milenage', 'c42449363bbad02b66d16bc975d77cc1', NULL, NULL, NULL, NULL, '208990100001139');
 INSERT INTO `AuthenticationSubscription` (`ueid`, `authenticationMethod`, `encPermanentKey`, `protectionParameterId`, `sequenceNumber`, `authenticationManagementField`, `algorithmId`, `encOpcKey`, `encTopcKey`, `vectorGenerationInHss`, `n5gcAuthMethod`, `rgAuthenticationInd`, `supi`) VALUES
 ('208990100001140', '5G_AKA', 'fec86ba6eb707ed08905757b1bb44b8f', 'fec86ba6eb707ed08905757b1bb44b8f', '{\"sqn\": \"000000000020\", \"sqnScheme\": \"NON_TIME_BASED\", \"lastIndexes\": {\"ausf\": 0}}', '8000', 'milenage', 'c42449363bbad02b66d16bc975d77cc1', NULL, NULL, NULL, NULL, '208990100001140');
-
+INSERT INTO `AuthenticationSubscription` (`ueid`, `authenticationMethod`, `encPermanentKey`, `protectionParameterId`, `sequenceNumber`, `authenticationManagementField`, `algorithmId`, `encOpcKey`, `encTopcKey`, `vectorGenerationInHss`, `n5gcAuthMethod`, `rgAuthenticationInd`, `supi`) VALUES
+('208950000000001', '5G_AKA', 'fec86ba6eb707ed08905757b1bb44b8f', 'fec86ba6eb707ed08905757b1bb44b8f', '{\"sqn\": \"000000000020\", \"sqnScheme\": \"NON_TIME_BASED\", \"lastIndexes\": {\"ausf\": 0}}', '8000', 'milenage', '8e27b6af0e692e750f32667a3b14605d', NULL, NULL, NULL, NULL, '208950000000001');
+INSERT INTO `AuthenticationSubscription` (`ueid`, `authenticationMethod`, `encPermanentKey`, `protectionParameterId`, `sequenceNumber`, `authenticationManagementField`, `algorithmId`, `encOpcKey`, `encTopcKey`, `vectorGenerationInHss`, `n5gcAuthMethod`, `rgAuthenticationInd`, `supi`) VALUES
+('208950000000002', '5G_AKA', 'fec86ba6eb707ed08905757b1bb44b8f', 'fec86ba6eb707ed08905757b1bb44b8f', '{\"sqn\": \"000000000020\", \"sqnScheme\": \"NON_TIME_BASED\", \"lastIndexes\": {\"ausf\": 0}}', '8000', 'milenage', '8e27b6af0e692e750f32667a3b14605d', NULL, NULL, NULL, NULL, '208950000000002');
+INSERT INTO `AuthenticationSubscription` (`ueid`, `authenticationMethod`, `encPermanentKey`, `protectionParameterId`, `sequenceNumber`, `authenticationManagementField`, `algorithmId`, `encOpcKey`, `encTopcKey`, `vectorGenerationInHss`, `n5gcAuthMethod`, `rgAuthenticationInd`, `supi`) VALUES
+('208950000000003', '5G_AKA', 'fec86ba6eb707ed08905757b1bb44b8f', 'fec86ba6eb707ed08905757b1bb44b8f', '{\"sqn\": \"000000000020\", \"sqnScheme\": \"NON_TIME_BASED\", \"lastIndexes\": {\"ausf\": 0}}', '8000', 'milenage', '8e27b6af0e692e750f32667a3b14605d', NULL, NULL, NULL, NULL, '208950000000003');
+INSERT INTO `AuthenticationSubscription` (`ueid`, `authenticationMethod`, `encPermanentKey`, `protectionParameterId`, `sequenceNumber`, `authenticationManagementField`, `algorithmId`, `encOpcKey`, `encTopcKey`, `vectorGenerationInHss`, `n5gcAuthMethod`, `rgAuthenticationInd`, `supi`) VALUES
+('208950000000004', '5G_AKA', 'fec86ba6eb707ed08905757b1bb44b8f', 'fec86ba6eb707ed08905757b1bb44b8f', '{\"sqn\": \"000000000020\", \"sqnScheme\": \"NON_TIME_BASED\", \"lastIndexes\": {\"ausf\": 0}}', '8000', 'milenage', '8e27b6af0e692e750f32667a3b14605d', NULL, NULL, NULL, NULL, '208950000000004');
+INSERT INTO `AuthenticationSubscription` (`ueid`, `authenticationMethod`, `encPermanentKey`, `protectionParameterId`, `sequenceNumber`, `authenticationManagementField`, `algorithmId`, `encOpcKey`, `encTopcKey`, `vectorGenerationInHss`, `n5gcAuthMethod`, `rgAuthenticationInd`, `supi`) VALUES
+('208950000000005', '5G_AKA', 'fec86ba6eb707ed08905757b1bb44b8f', 'fec86ba6eb707ed08905757b1bb44b8f', '{\"sqn\": \"000000000020\", \"sqnScheme\": \"NON_TIME_BASED\", \"lastIndexes\": {\"ausf\": 0}}', '8000', 'milenage', '8e27b6af0e692e750f32667a3b14605d', NULL, NULL, NULL, NULL, '208950000000005');
+INSERT INTO `AuthenticationSubscription` (`ueid`, `authenticationMethod`, `encPermanentKey`, `protectionParameterId`, `sequenceNumber`, `authenticationManagementField`, `algorithmId`, `encOpcKey`, `encTopcKey`, `vectorGenerationInHss`, `n5gcAuthMethod`, `rgAuthenticationInd`, `supi`) VALUES
+('208950000000006', '5G_AKA', 'fec86ba6eb707ed08905757b1bb44b8f', 'fec86ba6eb707ed08905757b1bb44b8f', '{\"sqn\": \"000000000020\", \"sqnScheme\": \"NON_TIME_BASED\", \"lastIndexes\": {\"ausf\": 0}}', '8000', 'milenage', '8e27b6af0e692e750f32667a3b14605d', NULL, NULL, NULL, NULL, '208950000000006');
+INSERT INTO `AuthenticationSubscription` (`ueid`, `authenticationMethod`, `encPermanentKey`, `protectionParameterId`, `sequenceNumber`, `authenticationManagementField`, `algorithmId`, `encOpcKey`, `encTopcKey`, `vectorGenerationInHss`, `n5gcAuthMethod`, `rgAuthenticationInd`, `supi`) VALUES
+('208950000000007', '5G_AKA', 'fec86ba6eb707ed08905757b1bb44b8f', 'fec86ba6eb707ed08905757b1bb44b8f', '{\"sqn\": \"000000000020\", \"sqnScheme\": \"NON_TIME_BASED\", \"lastIndexes\": {\"ausf\": 0}}', '8000', 'milenage', '8e27b6af0e692e750f32667a3b14605d', NULL, NULL, NULL, NULL, '208950000000007');
+INSERT INTO `AuthenticationSubscription` (`ueid`, `authenticationMethod`, `encPermanentKey`, `protectionParameterId`, `sequenceNumber`, `authenticationManagementField`, `algorithmId`, `encOpcKey`, `encTopcKey`, `vectorGenerationInHss`, `n5gcAuthMethod`, `rgAuthenticationInd`, `supi`) VALUES
+('208950000000008', '5G_AKA', 'fec86ba6eb707ed08905757b1bb44b8f', 'fec86ba6eb707ed08905757b1bb44b8f', '{\"sqn\": \"000000000020\", \"sqnScheme\": \"NON_TIME_BASED\", \"lastIndexes\": {\"ausf\": 0}}', '8000', 'milenage', '8e27b6af0e692e750f32667a3b14605d', NULL, NULL, NULL, NULL, '208950000000008');
+INSERT INTO `AuthenticationSubscription` (`ueid`, `authenticationMethod`, `encPermanentKey`, `protectionParameterId`, `sequenceNumber`, `authenticationManagementField`, `algorithmId`, `encOpcKey`, `encTopcKey`, `vectorGenerationInHss`, `n5gcAuthMethod`, `rgAuthenticationInd`, `supi`) VALUES
+('208950000000009', '5G_AKA', 'fec86ba6eb707ed08905757b1bb44b8f', 'fec86ba6eb707ed08905757b1bb44b8f', '{\"sqn\": \"000000000020\", \"sqnScheme\": \"NON_TIME_BASED\", \"lastIndexes\": {\"ausf\": 0}}', '8000', 'milenage', '8e27b6af0e692e750f32667a3b14605d', NULL, NULL, NULL, NULL, '208950000000009');
+INSERT INTO `AuthenticationSubscription` (`ueid`, `authenticationMethod`, `encPermanentKey`, `protectionParameterId`, `sequenceNumber`, `authenticationManagementField`, `algorithmId`, `encOpcKey`, `encTopcKey`, `vectorGenerationInHss`, `n5gcAuthMethod`, `rgAuthenticationInd`, `supi`) VALUES
+('208950000000010', '5G_AKA', 'fec86ba6eb707ed08905757b1bb44b8f', 'fec86ba6eb707ed08905757b1bb44b8f', '{\"sqn\": \"000000000020\", \"sqnScheme\": \"NON_TIME_BASED\", \"lastIndexes\": {\"ausf\": 0}}', '8000', 'milenage', '8e27b6af0e692e750f32667a3b14605d', NULL, NULL, NULL, NULL, '208950000000010');
+INSERT INTO `AuthenticationSubscription` (`ueid`, `authenticationMethod`, `encPermanentKey`, `protectionParameterId`, `sequenceNumber`, `authenticationManagementField`, `algorithmId`, `encOpcKey`, `encTopcKey`, `vectorGenerationInHss`, `n5gcAuthMethod`, `rgAuthenticationInd`, `supi`) VALUES
+('208950000000011', '5G_AKA', 'fec86ba6eb707ed08905757b1bb44b8f', 'fec86ba6eb707ed08905757b1bb44b8f', '{\"sqn\": \"000000000020\", \"sqnScheme\": \"NON_TIME_BASED\", \"lastIndexes\": {\"ausf\": 0}}', '8000', 'milenage', '8e27b6af0e692e750f32667a3b14605d', NULL, NULL, NULL, NULL, '208950000000011');
+INSERT INTO `AuthenticationSubscription` (`ueid`, `authenticationMethod`, `encPermanentKey`, `protectionParameterId`, `sequenceNumber`, `authenticationManagementField`, `algorithmId`, `encOpcKey`, `encTopcKey`, `vectorGenerationInHss`, `n5gcAuthMethod`, `rgAuthenticationInd`, `supi`) VALUES
+('208950000000012', '5G_AKA', 'fec86ba6eb707ed08905757b1bb44b8f', 'fec86ba6eb707ed08905757b1bb44b8f', '{\"sqn\": \"000000000020\", \"sqnScheme\": \"NON_TIME_BASED\", \"lastIndexes\": {\"ausf\": 0}}', '8000', 'milenage', '8e27b6af0e692e750f32667a3b14605d', NULL, NULL, NULL, NULL, '208950000000012');
+INSERT INTO `AuthenticationSubscription` (`ueid`, `authenticationMethod`, `encPermanentKey`, `protectionParameterId`, `sequenceNumber`, `authenticationManagementField`, `algorithmId`, `encOpcKey`, `encTopcKey`, `vectorGenerationInHss`, `n5gcAuthMethod`, `rgAuthenticationInd`, `supi`) VALUES
+('208950000000013', '5G_AKA', 'fec86ba6eb707ed08905757b1bb44b8f', 'fec86ba6eb707ed08905757b1bb44b8f', '{\"sqn\": \"000000000020\", \"sqnScheme\": \"NON_TIME_BASED\", \"lastIndexes\": {\"ausf\": 0}}', '8000', 'milenage', '8e27b6af0e692e750f32667a3b14605d', NULL, NULL, NULL, NULL, '208950000000013');
+INSERT INTO `AuthenticationSubscription` (`ueid`, `authenticationMethod`, `encPermanentKey`, `protectionParameterId`, `sequenceNumber`, `authenticationManagementField`, `algorithmId`, `encOpcKey`, `encTopcKey`, `vectorGenerationInHss`, `n5gcAuthMethod`, `rgAuthenticationInd`, `supi`) VALUES
+('208950000000014', '5G_AKA', 'fec86ba6eb707ed08905757b1bb44b8f', 'fec86ba6eb707ed08905757b1bb44b8f', '{\"sqn\": \"000000000020\", \"sqnScheme\": \"NON_TIME_BASED\", \"lastIndexes\": {\"ausf\": 0}}', '8000', 'milenage', '8e27b6af0e692e750f32667a3b14605d', NULL, NULL, NULL, NULL, '208950000000014');
+INSERT INTO `AuthenticationSubscription` (`ueid`, `authenticationMethod`, `encPermanentKey`, `protectionParameterId`, `sequenceNumber`, `authenticationManagementField`, `algorithmId`, `encOpcKey`, `encTopcKey`, `vectorGenerationInHss`, `n5gcAuthMethod`, `rgAuthenticationInd`, `supi`) VALUES
+('208950000000015', '5G_AKA', 'fec86ba6eb707ed08905757b1bb44b8f', 'fec86ba6eb707ed08905757b1bb44b8f', '{\"sqn\": \"000000000020\", \"sqnScheme\": \"NON_TIME_BASED\", \"lastIndexes\": {\"ausf\": 0}}', '8000', 'milenage', '8e27b6af0e692e750f32667a3b14605d', NULL, NULL, NULL, NULL, '208950000000015');
+INSERT INTO `AuthenticationSubscription` (`ueid`, `authenticationMethod`, `encPermanentKey`, `protectionParameterId`, `sequenceNumber`, `authenticationManagementField`, `algorithmId`, `encOpcKey`, `encTopcKey`, `vectorGenerationInHss`, `n5gcAuthMethod`, `rgAuthenticationInd`, `supi`) VALUES
+('208950000000016', '5G_AKA', 'fec86ba6eb707ed08905757b1bb44b8f', 'fec86ba6eb707ed08905757b1bb44b8f', '{\"sqn\": \"000000000020\", \"sqnScheme\": \"NON_TIME_BASED\", \"lastIndexes\": {\"ausf\": 0}}', '8000', 'milenage', '8e27b6af0e692e750f32667a3b14605d', NULL, NULL, NULL, NULL, '208950000000016');
+INSERT INTO `AuthenticationSubscription` (`ueid`, `authenticationMethod`, `encPermanentKey`, `protectionParameterId`, `sequenceNumber`, `authenticationManagementField`, `algorithmId`, `encOpcKey`, `encTopcKey`, `vectorGenerationInHss`, `n5gcAuthMethod`, `rgAuthenticationInd`, `supi`) VALUES
+('208950100001121', '5G_AKA', 'fec86ba6eb707ed08905757b1bb44b8f', 'fec86ba6eb707ed08905757b1bb44b8f', '{\"sqn\": \"000000000020\", \"sqnScheme\": \"NON_TIME_BASED\", \"lastIndexes\": {\"ausf\": 0}}', '8000', 'milenage', '8e27b6af0e692e750f32667a3b14605d', NULL, NULL, NULL, NULL, '208950100001121');
 
 
 
@@ -241,6 +274,9 @@
   `suggestedPacketNumDlList` json DEFAULT NULL,
   `3gppChargingCharacteristics` varchar(50) DEFAULT NULL
 ) ENGINE=InnoDB DEFAULT CHARSET=utf8;
+INSERT INTO `SessionManagementSubscriptionData` (`ueid`, `servingPlmnid`, `singleNssai`, `dnnConfigurations`) VALUES 
+('208950100001121', '20895', '{\"sst\": 1, \"sd\": \"10203\"}','{\"oai\":{\"pduSessionTypes\":{ \"defaultSessionType\": \"IPV4\"},\"sscModes\": {\"defaultSscMode\": \"SSC_MODE_1\"},\"5gQosProfile\": {\"5qi\": 6,\"arp\":{\"priorityLevel\": 1,\"preemptCap\": \"NOT_PREEMPT\",\"preemptVuln\":\"NOT_PREEMPTABLE\"},\"priorityLevel\":1},\"sessionAmbr\":{\"uplink\":\"100Mbps\", \"downlink\":\"100Mbps\"}}}');
+
 
 -- --------------------------------------------------------
EOF
    patch "$ORIG_CHART" < /tmp/oai_db-basic-patch
}

function configure-amf() {

    FUNCTION="oai-amf"
    DIR="$OAI5G_CORE/$FUNCTION"
    ORIG_CHART="$OAI5G_CORE/$FUNCTION"/templates/deployment.yaml
    echo "Configuring chart $ORIG_CHART for R2lab"

    cp "$ORIG_CHART" /tmp/"$FUNCTION"_deployment.yaml-orig
    perl -i -p0e 's/>-.*?\}]/"{{ .Chart.Name }}-n1-net1"/s' "$ORIG_CHART"
    diff /tmp/"$FUNCTION"_deployment.yaml-orig "$ORIG_CHART"
}

function configure-spgwu-tiny() {

    FUNCTION="oai-spgwu-tiny"
    DIR="$OAI5G_CORE/$FUNCTION"
    ORIG_CHART="$OAI5G_CORE/$FUNCTION"/templates/deployment.yaml
    echo "Configuring chart $ORIG_CHART for R2lab"

    cp "$ORIG_CHART" /tmp/"$FUNCTION"_deployment.yaml-orig
    perl -i -p0e 's/>-.*?\}]/"{{ .Chart.Name }}-n3-net1"/s' "$ORIG_CHART"
    diff /tmp/"$FUNCTION"_deployment.yaml-orig "$ORIG_CHART"
}

function configure-gnb() {
    fit_gnb=$1; shift
    
    FUNCTION="oai-gnb"
    DIR="$OAI5G_RAN/$FUNCTION"
    ORIG_CHART="$DIR"/values.yaml
    SED_FILE="/tmp/$FUNCTION-r2lab.sed"
    echo "Configuring chart $ORIG_CHART for R2lab"
    cat > "$SED_FILE" <<EOF
s|gnb: true|gnb: false|
s|create: false|create: true|
s|n2IPadd:.*|n2IPadd: "192.168.2.203"|
s|n2Netmask:.*|n2Netmask: "24"|
s|hostInterface:.*|hostInterface: "enp0s25" # data Interface of the fit machine on which this pod will be scheduled|
s|n3IPadd:.*|n3IPadd: "192.168.2.204"|
s|n3Netmask:.*|n3Netmask: "24"|
s|mnc:.*|mnc: "95"    # check the information with AMF, SMF, UPF/SPGWU|
s|useFqdn:.*|useFqdn: "false"|
s|amfIpAddress:.*|amfIpAddress: "192.168.2.201"  # amf ip-address or service-name|
s|gnbNgaIfName:.*|gnbNgaIfName: "net1"  # net1 in case multus create is true that means another interface is created for ngap interface, n2 to communicate with amf|
s|gnbNgaIpAddress:.*|gnbNgaIpAddress: "192.168.2.203" # n2IPadd in case multus create is true|
s|gnbNguIfName:.*|gnbNguIfName: "net2"   #net2 in case multus create is true gtu interface for upf/spgwu|
s|gnbNguIpAddress:.*|gnbNguIpAddress: "192.168.2.204" # n3IPadd in case multus create is true|
s|volumneName|volumeName|
s|nodeName:.*|nodeName: $fit_gnb|
EOF

    cp "$ORIG_CHART" /tmp/"$FUNCTION"_values.yaml-orig
    echo "(Over)writing $DIR/values.yaml"
    sed -f "$SED_FILE" < /tmp/"$FUNCTION"_values.yaml-orig > "$ORIG_CHART"
    diff /tmp/"$FUNCTION"_values.yaml-orig "$ORIG_CHART"

    ORIG_CHART="$DIR"/templates/deployment.yaml
    echo "Configuring chart $ORIG_CHART for R2lab"

    cp "$ORIG_CHART" /tmp/"$FUNCTION"_deployment.yaml-orig
    perl -i -p0e 's/>-.*?\}]/p4-network, p4-network/s' "$ORIG_CHART"
    #perl -i -p0e 's/>-.*?\}]/macvlan-data/s' "$ORIG_CHART"
    #perl -i -p0e 's/"name": "{{ .Chart.Name }}-net1",.*?"]/"name": "{{ .Chart.Name }}-net1"/s' "$ORIG_CHART"
    diff /tmp/"$FUNCTION"_deployment.yaml-orig "$ORIG_CHART"
}

function configure-oai-nr-ue() {
    fit_ue=$1; shift
    
    FUNCTION="oai-nr-ue"
    DIR="$OAI5G_RAN/$FUNCTION"
    ORIG_CHART="$DIR"/values.yaml
    SED_FILE="/tmp/$FUNCTION-r2lab.sed"
    echo "Configuring chart $ORIG_CHART for R2lab"
    cat > "$SED_FILE" <<EOF
s|create: false|create: true|
s|ipadd:.*|ipadd: "192.168.2.209" # interface needed to connect with gnb|
s|netmask:.*|netmask: "24"|
s|hostInterface:.*|hostInterface: "enp0s25" # data Interface of the fit machine on which this pod will be scheduled|
s|nodeName:.*|nodeName: $fit_ue|
s|fullImsi:.*|fullImsi: "208950100001121"|
s|opc:.*|opc: "8E27B6AF0E692E750F32667A3B14605D"|
EOF

    cp "$ORIG_CHART" /tmp/"$FUNCTION"_values.yaml-orig
    echo "(Over)writing $DIR/values.yaml"
    sed -f "$SED_FILE" < /tmp/"$FUNCTION"_values.yaml-orig > "$ORIG_CHART"
    diff /tmp/"$FUNCTION"_values.yaml-orig "$ORIG_CHART"

    ORIG_CHART="$DIR"/templates/deployment.yaml
    echo "Configuring chart $ORIG_CHART for R2lab"

    cp "$ORIG_CHART" /tmp/"$FUNCTION"_deployment.yaml-orig
    perl -i -p0e 's/>-.*?\}]/"{{ .Chart.Name }}-net1"/s' "$ORIG_CHART"
    diff /tmp/"$FUNCTION"_deployment.yaml-orig "$ORIG_CHART"
}


function configure-all() {
    fit_amf=$1
    shift
    fit_spgwu=$1
    shift
    fit_gnb=$1
    shift
    fit_ue=$1
    shift

    echo "Applying SopNode patches to OAI5G located on "$HOME"/oai-cn5g-fed"
    echo -e "\t with oai-amf running on $fit_amf"
    echo -e "\t with oai-spgwu-tiny running on $fit_spgwu"
    echo -e "\t with oai-gnb running on $fit_gnb"
    echo -e "\t with oai-nr-ue running on $fit_ue"

    configure-oai-5g-basic $fit_amf $fit_spgwu
    configure-mysql
    configure-amf
    configure-spgwu-tiny
    configure-gnb $fit_gnb
    configure-oai-nr-ue $fit_ue
}


function init() {
    ns=$1
    shift

    # init function should be run once per demo.
    echo "init: ensure spray is installed and possibly create secret docker-registry"
    # Remove pulling limitations from docker-hub with anonymous account
    kubectl create namespace $ns || true
    kubectl -n$ns delete secret regcred || true
    kubectl -n$ns create secret docker-registry regcred --docker-server=https://index.docker.io/v1/ --docker-username=r2labuser --docker-password=r2labuser-pwd --docker-email=r2labuser@turletti.com || true

    # Ensure that helm spray plugin is installed
    helm plugin install https://github.com/ThalesGroup/helm-spray || true

    # Install patch command...
    dnf -y install patch

    # Just in case the k8s cluster has been restarted without multus enabled..
    echo "kube-install.sh enable-multus"
    kube-install.sh enable-multus || true
    #echo "New : kube-install.sh $ns multus-network-attachments"
    #net_if=team0
    #kube-install.sh multus-network-attachments $ns $net_if || true
}

function reconfigure() {
    fit_amf=$1
    shift
    fit_spgwu=$1
    shift
    fit_gnb=$1
    shift
    fit_ue=$1
    shift

    echo "setup: Reconfigure oai5g charts from original ones"
    cd "$HOME"
    rm -rf oai-cn5g-fed
    git clone -b master https://gitlab.eurecom.fr/oai/cn5g/oai-cn5g-fed
    configure $fit_amf $fit_spgwu $fit_gnb $fit_ue
}


function run-ping() {
    ns=$1
    shift

    UE_POD_NAME=$(kubectl -n$ns get pods -l app.kubernetes.io/name=oai-nr-ue -o jsonpath="{.items[0].metadata.name}")
    echo "kubectl -n$ns exec -it $UE_POD_NAME -c nr-ue -- /bin/ping --I oaitun_ue1 c4 google.fr"
    kubectl -n$ns exec -it $UE_POD_NAME -c nr-ue -- /bin/ping -I oaitun_ue1 -c4 google.fr
}


function start-cn() {
    ns=$1
    shift
    fit_amf=$1
    shift
    fit_spgwu=$1
    shift

    echo "Running start-cn() with namespace: $ns, fit_amf:$fit_amf, fit_spgwu:$fit_spgwu"

    echo "cd $OAI5G_BASIC"
    cd "$OAI5G_BASIC"

    echo "helm dependency update"
    helm dependency update

    echo "helm --namespace=$ns spray ."
    helm --create-namespace --namespace=$ns spray .

    echo "Wait until all 5G Core pods are READY"
    kubectl wait pod -n$ns --for=condition=Ready --all
}


function start-gnb() {
    ns=$1
    shift
    fit_gnb=$1
    shift

    echo "Running start-gnb() with namespace: $ns, fit_gnb:$fit_gnb"

    echo "cd $OAI5G_RAN"
    cd "$OAI5G_RAN"

    echo "Not starting : helm -n$ns install oai-gnb oai-gnb/"
    helm -n$ns install oai-gnb oai-gnb/

    echo "Wait until the gNB pod is READY"
    echo "kubectl -n$ns wait pod --for=condition=Ready --all"
    kubectl -n$ns wait pod --for=condition=Ready --all
}

function start-ue() {
    ns=$1
    shift
    fit_gnb=$1
    shift
    fit_ue=$1
    shift

    echo "Running start-ue() with namespace: $ns, fit_gnb:$fit_gnb, fit_ue:$fit_ue"

    echo "cd $OAI5G_RAN"
    cd "$OAI5G_RAN"

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

    echo "helm -n$ns install oai-nr-ue oai-nr-ue/"
    helm -n$ns install oai-nr-ue oai-nr-ue/

    echo "Wait until oai-nr-ue pod is READY"
    kubectl wait pod -n$ns --for=condition=Ready --all
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

    echo "start: run all oai5g pods on namespace: $ns"

    # Check if all FIT nodes are ready
    while :; do
        kubectl wait no --for=condition=Ready $fit_amf $fit_spgwu $fit_gnb $fit_ue && break
        clear
        echo "Wait until all FIT nodes are in READY state"
        kubectl get no
        sleep 5
    done

    start-cn $ns $fit_amf $fit_spgwu
    start-gnb $ns $fit_gnb
    #start-ue $ns $fit_gnb $fit_ue

    # Check UE logs
    #UE_POD_NAME=$(kubectl -n$ns get pods -l app.kubernetes.io/name=oai-nr-ue -o jsonpath="{.items[0].metadata.name}")
    #echo "Check UE logs"
    #echo "kubectl -n$ns logs $UE_POD_NAME -c nr-ue"
    #kubectl -n$ns logs $UE_POD_NAME -c nr-ue

    # Wait 10s and run ping test from UE to google.fr
    echo "sleep 10"
    sleep 10
    #run-ping $ns
    
    echo "****************************************************************************"
    echo "When you finish, to clean-up the k8s cluster, please run demo-oai.py --clean"
}

function stop-cn(){
    ns=$1
    shift

    echo "helm -n$ns uninstall oai-spgwu-tiny oai-nrf oai-udr oai-udm oai-ausf oai-smf oai-amf mysql"
    helm -n$ns uninstall mysql
    helm -n$ns uninstall oai-ausf
    helm -n$ns uninstall oai-udm
    helm -n$ns uninstall oai-udr
    helm -n$ns uninstall oai-amf
    helm -n$ns uninstall oai-smf
    helm -n$ns uninstall oai-nrf
}


function stop-gnb(){
    ns=$1
    shift

    echo "helm -n$ns uninstall oai-gnb"
    helm -n$ns uninstall oai-gnb
}


function stop-ue(){
    ns=$1
    shift

    echo "helm -n$ns uninstall oai-nr-ue"
    helm -n$ns uninstall oai-nr-ue
}


function stop() {
    ns=$1
    shift

    echo "Running stop() on namespace:$ns"

    res=$(helm -n $ns ls | wc -l)
    if test $res -gt 1; then
        echo "Remove all 5G OAI pods"
	stop-cn $ns
	stop-gnb $ns
	stop-ue $ns
    else
        echo "OAI5G demo is not running, there is no pod on namespace $ns !"
    fi
    echo "Delete namespace $ns"
    echo "kubectl delete ns $ns"
    kubectl delete ns $ns
}


#Handle the different function calls with or without input parameters
if test $# -lt 1; then
    usage
else
    if [ "$1" == "init" ]; then
        if test $# -eq 2; then
            init $2
        else
            usage
        fi
    elif [ "$1" == "start" ]; then
        if test $# -eq 6; then
            start $2 $3 $4 $5 $6
        elif test $# -eq 1; then
	    start $DEF_NS $DEF_FIT_AMF $DEF_FIT_SPGWU $DEF_FIT_GNB $DEF_FIT_UE
	else
            usage
        fi
    elif [ "$1" == "stop" ]; then
        if test $# -eq 2; then
            stop $2
        elif test $# -eq 1; then
	    stop $DEF_NS
	else
            usage
        fi
    elif [ "$1" == "configure-all" ]; then
        if test $# -eq 5; then
            configure-all $2 $3 $4 $5
	    exit 0
        elif test $# -eq 1; then
	    configure-all $DEF_FIT_AMF $DEF_FIT_SPGWU $DEF_FIT_GNB $DEF_FIT_UE
	else
            usage
        fi
    elif [ "$1" == "reconfigure" ]; then
        if test $# -eq 5; then
            reconfigure $2 $3 $4 $5
        elif test $# -eq 1; then
	    reconfigure $DEF_FIT_AMF $DEF_FIT_SPGWU $DEF_FIT_GNB $DEF_FIT_UE
	else
            usage
        fi
    elif [ "$1" == "run-ping" ]; then
        if test $# -eq 2; then
            run-ping $2
        elif test $# -eq 1; then
	    run-ping $DEF_NS
	else
            usage
        fi
    elif [ "$1" == "start-cn" ]; then
        if test $# -eq 4; then
            start-cn $2 $3 $4
        elif test $# -eq 1; then
	    start-cn $DEF_NS $DEF_FIT_AMF $DEF_FIT_SPGWU
	else
            usage
        fi
    elif [ "$1" == "start-gnb" ]; then
        if test $# -eq 3; then
            start-gnb $2 $3
        elif test $# -eq 1; then
	    start-gnb $DEF_NS $DEF_FIT_GNB
	else
            usage
        fi
    elif [ "$1" == "start-ue" ]; then
        if test $# -eq 4; then
            start-ue $2 $3 $4
        elif test $# -eq 1; then
	    start-ue $DEF_NS $DEF_FIT_GNB $DEF_FIT_UE
	else
            usage
        fi
    elif [ "$1" == "stop-cn" ]; then
        if test $# -eq 2; then
            stop-cn $2
        elif test $# -eq 1; then
	    stop-cn $DEF_NS
	else
            usage
        fi
    elif [ "$1" == "stop-gnb" ]; then
        if test $# -eq 2; then
            stop-gnb $2
        elif test $# -eq 1; then
	    stop-gnb $DEF_NS
	else
            usage
        fi
    elif [ "$1" == "stop-ue" ]; then
        if test $# -eq 2; then
            stop-ue $2
        elif test $# -eq 1; then
	    stop-ue $DEF_NS
	else
            usage
        fi
    else
        usage
    fi
fi
