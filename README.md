

# OAI5G demo on SophiaNode

This script aims to demonstrate how to automate a OAI5G deployment on the SophiaNode cluster
using both FIT nodes on R2lab and classical k8s workers.

In this demo, the **demo-oai.py** nepi-ng script is used to prepare 4 FIT nodes that will be used to run the following OAI5G functions developed at Eurecom:

* oai-amf (fit01 by default)
* oai-spgwu (fit02 by default)
* oai-gnb (fit03 by default)
* oai-nr-ue (fit04 by default)

This demo does not involve radio transmission, the OAI5G RF simulator will be used instead.


**Acknowledgments:** _Support regarding configuration of the OAI5G functions has been provided by
Sagar Arora at Eurecom <sagar.arora@eurecom.fr>._

**WARNING:** Currently, the k8s sopnode-l1 cluster has some issues related to DNS, which makes a few pods crash periodically. Hopefully, this will be fixed soon.

### Software dependencies

Before you can run the script in this directory, make user to install its dependencies

    pip install -r requirements.txt

### References

* [OAI 5G Core Network Deployment using Helm Charts](https://gitlab.eurecom.fr/oai/cn5g/oai-cn5g-fed/-/blob/master/docs/DEPLOY_SA5G_HC.md)
* [R2lab welcome page](https://r2lab.inria.fr/)
* [R2lab run page (requires login)](https://r2lab.inria.fr/run.md)
* [github repo for this page](https://github.com/fit-r2lab/r2lab-demos)


## The different steps...

### Metal provisioning

The **demo-oai.py** script optionally deploys a preconfigured Kubernetes (k8s) image on the following R2lab FIT nodes: 

* fit01 for oai-amf 
* fit02 for oai-spgwu 
* fit03 for oai-gnb 
* fit09 for oai-nr-ue 

Then the script will configure the nodes to use the data interface used by [k8s Multus](https://github.com/k8snetworkplumbingwg/multus-cni) and it will make all the nodes join the k8s master (sopnode-l1.inria.fr by default).


After that, the script will deploy OAI5G pods on the k8s cluster. To do that, it will use the k8s worker node in which the oai-amf pod will be deployed. 

In a nutshell, the script will clone the OAI5G oai-cn5g-fed git directory on the FIT node fit01. To do it manually, you will have to run:

```
root@fit01# git clone -b master https://gitlab.eurecom.fr/oai/cn5g/oai-cn5g-fed
``` 
Then it will apply different patches to configure the various OAI5G pods for the SopNode platform. To do it manually, you will have to run on fit01:

```
root@fit01# ./config-oai5g-sopnode.sh
```

Finally, the **demo-oai.py** script will deploy the OAI5G pods on the k8s cluster. However, if you prefer to do it manually, you will have to do the following directly on fit01 (or on another k8s worker node or on the k8s master):


```bash
# Wait until all fit nodes are in READY state
sopnode-l1$ kubectl wait no --for=condition=Ready kubectl wait no --for=condition=Ready fit01 fit02 fit03 fit09

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

The **demo-oai.py** nepi-ng script has various options to change default parameters, run ``./demo-oai.py --help`` on your laptop to see all of them.

The two main options are ``- l`` to load the k8s images on FIT nodes and ``-s slicename`` to change the default slicename used to book the platform, which is _inria\_sopnode_.

For instance, if your slicename is _inria\_sc_ and you did not load k8s images yet on FIT nodes, to run all the steps described above, you only have to run the following command on your laptop:

```bash
$ ./demo-oai.py -l -s inria_sc 
```


### Testing

To check logs of the different pods, you need first to log on one of the k8s workers or master nodes, e.g., *fit01* or *sopnode-l1.inria.fr*.

For instance, to check logs of the oai-gnb pod, run:

``` bash 

sopnode-l1$ GNB_POD_NAME=$(kubectl -noai5g get pods -l app.kubernetes.io/name=oai-gnb -o jsonpath="{.items[0].metadata.name}")

sopnode-l1$ kubectl -noai5g logs $GNB_POD_NAME -c gnb
```

Also, to check logs of the oai-nr-ue pod:

``` bash 

sopnode-l1$ UE_POD_NAME=$(kubectl -noai5g get pods -l app.kubernetes.io/name=oai-nr-ue -o jsonpath="{.items[0].metadata.name}")

sopnode-l1$ kubectl -noai5g logs $UE_POD_NAME -c nr-ue
```


### Cleanup

To clean up all OAI5G pods, you can run on your laptop ``./demo-oai.py --stop` or run the following command directly on the k8s cluster:

```bash 
sopnode-l1$ helm --namespace oai5g ls --short --all | xargs -L1 helm --namespace oai5g delete
```




