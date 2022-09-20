#!/bin/bash

echo "`basename "$0"`: "
echo "This scripts applies patches to OAI5G charts in order to be used on the SopNode platform"
echo "Configuration includes 4 R2lab FIT nodes to run following pods:"
echo "  - oai-amf (fit01 by default)"
echo "  - oai-spgwu-tiny (fit02 by default)"
echo "  - oai-gnb (fit03 by default)"
echo "  - oai-nr-ue (fit09 by default)"
echo "This script has to be run once on the k8s master node, just after a clone of oai-cn5g-fed"
echo "see https://gitlab.eurecom.fr/oai/cn5g/oai-cn5g-fed/-/blob/master/docs/DEPLOY_SA5G_HC.md"
echo


OAI5G_CHARTS="$HOME"/oai-cn5g-fed/charts
OAI5G_CORE="$OAI5G_CHARTS"/oai-5g-core
OAI5G_BASIC="$OAI5G_CORE"/oai-5g-basic
OAI5G_RAN="$OAI5G_CHARTS"/oai-5g-ran

function configure-oai-5g-basic() {
    fit_amf=$1; shift
    fit_spgwu=$1; shift 

    echo "Configuring chart $OAI5G_BASIC/values.yaml for R2lab"
    cat > /tmp/basic-r2lab.sed <<EOF
s|create: false|create: true|
s|n1IPadd:.*|n1IPadd: "192.168.2.201"|
s|n1Netmask:.*|n1Netmask: "24"|
s|hostInterface:.*|hostInterface: "enp0s25"|
s|amfInterfaceNameForNGAP: "eth0" # If multus creation is true then net1 else eth0|amfInterfaceNameForNGAP: "net1" # If multus creation is true then net1 else eth0|
s|mnc: "99"|mnc: "95"|
s|servedGuamiMnc0: "99"|servedGuamiMnc0: "95"|
s|plmnSupportMnc: "99"|plmnSupportMnc: "95"|
s|operatorKey:.*|operatorKey: "8e27b6af0e692e750f32667a3b14605d"  # should be same as in subscriber database|  
s|n3Ip:.*|n3Ip: "192.168.2.202"|
s|n3Netmask:.*|n3Netmask: "24"|
s|sgwS1uIf: "eth0"  # n3 interface, net1 if gNB is outside the cluster network and multus creation is true else eth0|sgwS1uIf: "net1"  # n3 interface, net1 if gNB is outside the cluster network and multus creation is true else eth0|
s|pgwSgiIf: "eth0"  # net1 if gNB is outside the cluster network and multus creation is true else eth0 (important because it sends the traffic towards internet)|pgwSgiIf: "net1"  # net1 if gNB is outside the cluster network and multus creation is true else eth0 (important because it sends the traffic towards internet)|
s|dnsIpv4Address: "172.21.3.100" # configure the dns for UE don't use Kubernetes DNS|dnsIpv4Address: "138.96.0.210" # configure the dns for UE don't use Kubernetes DNS|
s|dnsSecIpv4Address: "172.21.3.100" # configure the dns for UE don't use Kubernetes DNS|dnsSecIpv4Address: "193.51.196.138" # configure the dns for UE don't use Kubernetes DNS|
EOF

    cp "$OAI5G_BASIC"/values.yaml /tmp/basic_values.yaml-orig
    echo "(Over)writing $OAI5G_BASIC/values.yaml"
    sed -f /tmp/basic-r2lab.sed < /tmp/basic_values.yaml-orig > "$OAI5G_BASIC"/values.yaml
    perl -i -p0e "s/nodeSelector: \{\}\noai-spgwu-tiny:/nodeName: \"$fit_amf\"\\n  nodeSelector: \{\}\noai-spgwu-tiny:/s" "$OAI5G_BASIC"/values.yaml
    perl -i -p0e "s/nodeSelector: \{\}\noai-smf:/nodeName: \"$fit_spgwu\"\n  nodeSelector: \{\}\noai-smf:/s" "$OAI5G_BASIC"/values.yaml

    diff /tmp/basic_values.yaml-orig "$OAI5G_BASIC"/values.yaml
    cd "OAI5G_BASIC"; helm dependency update
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
    perl -i -p0e 's/"name": "{{ .Chart.Name }}-net1",.*?"]/"name": "{{ .Chart.Name }}-net1"/s' "$ORIG_CHART"
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


########################################

function usage() {
    echo "USAGE: `basename "$0"` fit_amf fit_spgwu fit_gnb fit_ue"
    echo "Applying SopNode patches to OAI5G located on "$HOME"/oai-cn5g-fed"
    echo -e "\t with oai-amf running on fit_amf"
    echo -e "\t with oai-spgwu-tiny running on fit_spgwu"
    echo -e "\t with oai-gnb running on fit_gnb"
    echo -e "\t with oai-nr-ue running on fit_ue"
    exit 1
}

# main

if test $# -ne 4
then
    usage
else
    echo "`basename "$0"`: Applying SopNode patches to OAI5G located on "$HOME"/oai-cn5g-fed"
    echo -e "\t with oai-amf running on $1"
    echo -e "\t with oai-spgwu-tiny running on $2"
    echo -e "\t with oai-gnb running on $3"
    echo -e "\t with oai-nr-ue running on $4"

    configure-oai-5g-basic $1 $2
    configure-mysql
    configure-amf
    configure-spgwu-tiny
    configure-gnb $3
    configure-oai-nr-ue $4
    exit 0
fi
