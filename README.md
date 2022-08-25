# OAI5G demo on SophiaNode

This script aims to demonstrate how to automate a OAI5G deployment on the SophiaNode cluster
using both FIT nodes on R2lab and classical k8s workers.

In this demo, the **demo-oai.py** nepi-ng script is used to prepare 4 FIT nodes that will be used to run the following OAI5G functions developed at Eurecom:

* oai-amf (*`fit01`* by default)
* oai-spgwu (*`fit02`* by default)
* oai-gnb (*`fit03`* by default)
* oai-nr-ue (*`fit04`* by default)

This demo does not involve actual radio transmission, all radio traffic is emulated thanks to the OAI5G RF simulator.


**Acknowledgments:** _Support regarding configuration of the OAI5G functions has been provided by
Sagar Arora at Eurecom <sagar.arora@eurecom.fr>._

### Software dependencies

Before you can run the script in this directory, you need to install its dependencies

    pip install -r requirements.txt

### References

* [OAI 5G Core Network Deployment using Helm Charts](https://gitlab.eurecom.fr/oai/cn5g/oai-cn5g-fed/-/blob/master/docs/DEPLOY_SA5G_HC.md)
* [R2lab welcome page](https://r2lab.inria.fr/)
* [R2lab run page (requires login)](https://r2lab.inria.fr/run.md)
* [github repo for this page](https://github.com/sopnode/oai5g-rfsim)


## The different steps...

### Metal provisioning

The **demo-oai.py** script optionally deploys a preconfigured Kubernetes (k8s) image on 4 R2lab FIT nodes, which by default are:

* *`fit01`* for oai-amf
* *`fit02`* for oai-spgwu
* *`fit03`* for oai-gnb
* *`fit09`* for oai-nr-ue

### Joining the k8s cluster
Then the script will get all the nodes to join the k8s master (*`sopnode-l1.inria.fr`* by default), and configure [k8s Multus](https://github.com/k8snetworkplumbingwg/multus-cni) to use their `data` interface.

### Configuration
After that, the script will deploy OAI5G pods on the k8s cluster. To do that, it will use the k8s worker node that hosts the `oai-amf` pod, which again is *`fit01`* by default.

In a nutshell, the script will clone the OAI5G `oai-cn5g-fed` git repository on the FIT node *fit01*. To do it manually, you will have to run:

```
root@fit01# git clone -b master https://gitlab.eurecom.fr/oai/cn5g/oai-cn5g-fed
```
Then it will apply different patches to configure the various OAI5G pods for the SopNode platform. To do it manually, you will have to run on *fit01* :

```
root@fit01# ./config-oai5g-sopnode.sh
```

These patches include configuration of Multus CNI interfaces specific to the SophiaNode platform. See the IP address configuration in the following figure modified from the [OAI 5G Core Network Deployment using Helm Charts](https://gitlab.eurecom.fr/oai/cn5g/oai-cn5g-fed/-/blob/master/docs/DEPLOY_SA5G_HC.md) tutorial.

![Multus CNI Configuration](./helm-chart-basic-cni.png)

### Deployment

Finally, the **demo-oai.py** script will deploy the OAI5G pods on the k8s cluster. However, if you prefer to do it manually, you will have to do the following directly on *fit01* (or on another k8s worker node or on the k8s master *sopnode-l1*):


```bash
# Wait until all fit nodes are in READY state
sopnode-l1$ kubectl wait node --for=condition=Ready fit01 fit02 fit03 fit09

# Run the OAI 5G Core pods
sopnode-l1$ cd /home/oai/oai-cn5g-fed/charts/oai-5g-core/oai-5g-basic

sopnode-l1$ helm --namespace=oai5g spray .

# Wait until all 5G Core pods are READY
sopnode-l1$ kubectl wait pod -noai5g --for=condition=Ready --all

# Run the oai-gnb pod on fit03
sopnode-l1$ cd /home/oai/oai-cn5g-fed/charts/oai-5g-ran
sopnode-l1$ helm --namespace=oai5g install oai-gnb oai-gnb/

# Wait until the gNB pod is READY
sopnode-l1$ kubectl wait pod -noai5g --for=condition=Ready --all

# Run the oai-nr-ue pod on fit09

# Retrieve the IP address of the gnb pod and set it in chart
#  /home/oai/oai-cn5g-fed/charts/oai-5g-ran/oai-nr-ue/values.yaml

sopnode-l1$ GNB_POD_NAME=$(kubectl -noai5g get pods -l app.kubernetes.io/name=oai-gnb -o jsonpath="{.items[0].metadata.name}")

sopnode-l1$ GNB_POD_IP=$(kubectl -noai5g get pod $GNB_POD_NAME --template '{{.status.podIP}}')

sopnode-l1$ conf_ue_dir="/home/oai/oai-cn5g-fed/charts/oai-5g-ran/oai-nr-ue"
sopnode-l1$ cat > /tmp/gnb-values.sed <<EOF
s|  rfSimulator:.*|  rfSimulator: "${GNB_POD_IP}"|
EOF

# (Over)writing oai-nr-ue chart $conf_ue_dir/values.yaml
sopnode-l1$ cp $conf_ue_dir/values.yaml /tmp/values-orig.yaml
sopnode-l1$ sed -f /tmp/gnb-values.sed < /tmp/values-orig.yaml > /tmp/values.yaml
sopnode-l1$ cp /tmp/values.yaml $conf_ue_dir/

sopnode-l1$ helm --namespace=oai5g install oai-nr-ue oai-nr-ue/

# Wait until the NR-UE pod is READY
sopnode-l1$ kubectl wait pod -noai5g --for=condition=Ready --all

```

### Customization

The **demo-oai.py** nepi-ng script has various options to change default parameters, run ``./demo-oai.py --help`` on your laptop to see all of them.

The main options are:

  * `-l` to load the k8s images on FIT nodes
  * `-s slicename` to provide the slicename that you used to book the platform, which$$ by default is *`inria_sopnode`*.
  * as well as `-i imagename` to use an alternative image name - default is *`kubernetes`*

For instance, if your slicename is `inria_sc` and you have not yet loaded the k8s images on the FIT nodes, to run all the steps described above, you only have to run the following command on your laptop:

```bash
$ ./demo-oai.py -l -s inria_sc
```


### Testing

At the end of the demo, few logs of the oai-nr-ue pod should be visible on the terminal and you can verify that the connection is fine with the gNB.

To check logs of the different pods, you need first to log on one of the k8s workers or master nodes, e.g., *fit01* or *sopnode-l1.inria.fr*.

For instance, to check the logs of the `oai-gnb` pod, run:

``` bash

sopnode-l1$ GNB_POD_NAME=$(kubectl -noai5g get pods -l app.kubernetes.io/name=oai-gnb -o jsonpath="{.items[0].metadata.name}")

sopnode-l1$ kubectl -noai5g logs $GNB_POD_NAME -c gnb
```

Also, to check logs of the `oai-nr-ue` pod:

``` bash

sopnode-l1$ UE_POD_NAME=$(kubectl -noai5g get pods -l app.kubernetes.io/name=oai-nr-ue -o jsonpath="{.items[0].metadata.name}")

sopnode-l1$ kubectl -noai5g logs $UE_POD_NAME -c nr-ue
```

### Cleanup

To clean up all OAI5G pods, you can run on your laptop ``./demo-oai.py --stop`` or to run the following command directly on the k8s cluster:

```bash
sopnode-l1$ helm --namespace oai5g ls --short --all | xargs -L1 helm --namespace oai5g delete
```
