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
s|n3IPadd:.*|n1IPadd: "192.168.2.202"|
s|n3Netmask:.*|n1Netmask: "24"|
s|sgwS1uIf: "eth0"  # n3 interface, net1 if gNB is outside the cluster network and multus creation is true else eth0|sgwS1uIf: "net1"  # n3 interface, net1 if gNB is outside the cluster network and multus creation is true else eth0|
s|pgwSgiIf: "eth0"  # net1 if gNB is outside the cluster network and multus creation is true else eth0 (important because it sends the traffic towards internet)|pgwSgiIf: "net1"  # net1 if gNB is outside the cluster network and multus creation is true else eth0 (important because it sends the traffic towards internet)|
s|dnsIpv4Address: "172.21.3.100" # configure the dns for UE don't use Kubernetes DNS|dnsIpv4Address: "138.96.0.210" # configure the dns for UE don't use Kubernetes DNS|
s|dnsSecIpv4Address: "172.21.3.100" # configure the dns for UE don't use Kubernetes DNS|dnsSecIpv4Address: "193.51.196.138" # configure the dns for UE don't use Kubernetes DNS|
/nodeSelector: {}$/ {
     N
     s/nodeSelector: {}\noai-spgwu-tiny:/nodeName: "fit01"\n  nodeSelector: {}\noai-spgwu-tiny:/
     s/nodeSelector: {}\noai-smf:/nodeName: "fit02"\n  nodeSelector: {}\noai-smf:/
}
EOF

    cp "$OAI5G_BASIC"/values.yaml /tmp/basic_values.yaml-orig
    echo "(Over)writing $OAI5G_BASIC/values.yaml"
    sed -f /tmp/basic-r2lab.sed < /tmp/basic_values.yaml-orig > "$OAI5G_BASIC"/values.yaml
    diff /tmp/basic_values.yaml-orig "$OAI5G_BASIC"/values.yaml
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
--- oai_db-basic.sql	2022-07-10 14:55:08.482559755 +0200
+++ oai_db-basic-patched.sql	2022-07-10 18:07:02.015271524 +0200
@@ -191,6 +191,38 @@
 ('208990100001139', '5G_AKA', 'fec86ba6eb707ed08905757b1bb44b8f', 'fec86ba6eb707ed08905757b1bb44b8f', '{\"sqn\": \"000000000020\", \"sqnScheme\": \"NON_TIME_BASED\", \"lastIndexes\": {\"ausf\": 0}}', '8000', 'milenage', 'c42449363bbad02b66d16bc975d77cc1', NULL, NULL, NULL, NULL, '208990100001139');
 INSERT INTO `AuthenticationSubscription` (`ueid`, `authenticationMethod`, `encPermanentKey`, `protectionParameterId`, `sequenceNumber`, `authenticationManagementField`, `algorithmId`, `encOpcKey`, `encTopcKey`, `vectorGenerationInHss`, `n5gcAuthMethod`, `rgAuthenticationInd`, `supi`) VALUES
 ('208990100001140', '5G_AKA', 'fec86ba6eb707ed08905757b1bb44b8f', 'fec86ba6eb707ed08905757b1bb44b8f', '{\"sqn\": \"000000000020\", \"sqnScheme\": \"NON_TIME_BASED\", \"lastIndexes\": {\"ausf\": 0}}', '8000', 'milenage', 'c42449363bbad02b66d16bc975d77cc1', NULL, NULL, NULL, NULL, '208990100001140');
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
s|amfIpAddress:.*|amfIpAddress: "192.168.2.201"  # amf ip-address or service-name|
s|gnbNgaIfName:.*|gnbNgaIfName: "net1"  # net1 in case multus create is true that means another interface is created for ngap interface, n2 to communicate with amf|
s|gnbNgaIpAddress:.*|gnbNgaIpAddress: "n2IPadd" # n2IPadd in case multus create is true|
s|gnbNguIfName:.*|gnbNguIfName: "net2"   #net2 in case multus create is true gtu interface for upf/spgwu|
s|gnbNguIpAddress:.*|gnbNguIpAddress: "n3IPadd" # n3IPadd in case multus create is true|
s|nodeName:.*|nodeName: fit03|
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
s|nodeName:.*|nodeName: fit09|
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
echo "Uncomment all the commands at the end of the script to configure the whole charts"
configure-oai-5g-basic
configure-mysql
configure-amf
configure-spgwu-tiny
configure-gnb
configure-oai-nr-ue
exit 0
