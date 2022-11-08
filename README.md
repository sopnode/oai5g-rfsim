# OAI5G demo on SophiaNode

This example is based on [OAI5G-RFSIM](https://github.com/sopnode/oai5g-rfsim) script that aims to demonstrate how to automate a OAI5G deployment on the SophiaNode cluster using both FIT nodes on R2lab and classical k8s workers. It uses the USRP N300 as a 5G radio device.

In this demo, the **demo-oai.py** nepi-ng script is used to prepare a FIT node that will be used to run the 5G UE emulation while remaining core network and RAN functions are deployed on sopnode servers (sopnode-w2.inria.fr and sopnode-w3.inria.fr).

**Acknowledgments:** _Support regarding configuration of the OAI5G functions has been provided by
Sagar Arora at Eurecom <sagar.arora@eurecom.fr>._

### Software dependencies

Before you can run the script in this directory, you need to install its dependencies

    pip install -r requirements.txt

### Basic usage

all the forms of the script assume there is a deployed kubernetes cluster on the chosen master node, and that the provided slicename holds the current lease on FIT/R2lab.

The mental model is we are dealing with essentially three states:

* (0) initially, the k8s cluster is running and the FIT/R2lab nodes are down while sopnode servers are up;
* (1) after setup, the FIT/R2lab nodes are loaded with the proper image, and have joined the cluster;
* (2) at that point one can use the `--start` option to start the system, which amounts to deploying pods on the k8s cluster;
* (back to 1) it is point one can roll back and come back to the previous state, using the `--stop` option

with none of the `--start/--stop/--cleanup` option the script goes from state 0 to (2),
unless the `--no-auto-start` option is given.

run `demo-oai.py --help` for more details

### References

* [OAI 5G Core Network Deployment using Helm Charts](https://gitlab.eurecom.fr/oai/cn5g/oai-cn5g-fed/-/blob/master/docs/DEPLOY_SA5G_HC.md)
* [R2lab welcome page](https://r2lab.inria.fr/)
* [R2lab run page (requires login)](https://r2lab.inria.fr/run.md)
* [OAI5G-RFSIM](https://github.com/sopnode/oai5g-rfsim)


## The different steps...

### Metal provisioning

The **demo-oai.py** script optionally deploys a preconfigured Kubernetes (k8s) image on a R2lab FIT node, which by default are:

* *`fit01`* for oai-nr-ue

Note that all the other OAI5G pods, e.g., oai-smf or oai-spgwu, are launched on the regular k8s worker servers of the SophiaNode platform. 

### Joining the k8s cluster
Then the script will get all the nodes to join the k8s master (*`sopnode-l1.inria.fr`* by default), and configure [k8s Multus](https://github.com/k8snetworkplumbingwg/multus-cni) to use their `data` interface.

### Configuration
It follows the configuration setup as explained in [OAI5G-RFSIM](https://github.com/sopnode/oai5g-rfsim) except that "oai-nr-ue" pod is deployed on 
*`fit01`*. It also copies the modified values.yaml and deployment.yaml for oai-gnb pod directly at respective locations in oai-cn5g-fed directory. 

```bash
gnb.band66.tm1.106PRB.usrpn300.conf -> /root/oai-cn5g-fed/charts/oai-5g-ran/oai-gnb/conf/mounted.conf
configmap-gnbconf.yaml -> /root/oai-cn5g-fed/charts/oai-5g-ran/oai-gnb/templates/configmap-gnbconf.yaml
deployment.yaml -> /root/oai-cn5g-fed/charts/oai-5g-ran/oai-gnb/templates/deployment.yaml
values.yaml -> /root/oai-cn5g-fed/charts/oai-5g-ran/oai-gnb/values.yaml
```
These are temporary files needed till Eurecom delivers new helm charts.

### Deployment

Finally, the **demo-oai.py** script will deploy the OAI5G pods on the k8s cluster. However, if you prefer to do it manually, you will have to do the following directly on *fit01* (or on another k8s worker node or on the k8s master *sopnode-l1*):


```bash
# Wait until all fit nodes are in READY state
fit01$ kubectl wait node --for=condition=Ready fit01, sopnode-w2.inria.fr, sopnode-w3.inria.fr

# Run the OAI 5G Core pods
fit01$ cd /home/oai/oai-cn5g-fed/charts/oai-5g-core/oai-5g-basic

fit01$ helm --namespace=oai5g spray .

# Create p4 network macvlan network attachment
fit01$ kubectl -noai5g create -f p4-network.yaml

# Wait until all 5G Core pods are READY
fit01$ kubectl wait pod -noai5g --for=condition=Ready --all

# Remove previously deployed oai-gnb pod
fit01$ GNB_POD_NAME=$(kubectl -noai5g get pods -l app.kubernetes.io/name=oai-gnb -o jsonpath="{.items[0].metadata.name}")
fit01$ kubectl -noai5g delete pods ${GNB_POD_NAME}
fit01$ helm uninstall oai-gnb

# Run the oai-gnb pod on sopnode servers
fit01$ cd /home/oai/oai-cn5g-fed/charts/oai-5g-ran
fit01$ helm --namespace=oai5g install oai-gnb oai-gnb/

# Wait until the gNB pod is READY
fit01$ kubectl wait pod -noai5g --for=condition=Ready --all

# Run the oai-nr-ue pod on fit01
fit01$ helm --namespace=oai5g install oai-nr-ue oai-nr-ue/

# Wait until the NR-UE pod is READY
fit01$ kubectl wait pod -noai5g --for=condition=Ready --all

```


### Customization

The **demo-oai.py** nepi-ng script has various options to change default parameters, run ``./demo-oai.py --help`` on your laptop to see all of them.

The main options are:

  * `--no_auto_start` to not launch the OAI5G pods by default.
  * `-s slicename` to provide the slicename that you used to book the platform, which by default is *`inria_sopnode`*.
  * `-k` to not restart the k8s cluster when reconfiguring charts. This will avoid the time consuming leave-join steps for FIT worker nodes.
  * as well as `-i imagename` to use an alternative image name - default is *`kubernetes`*.

For instance, if your slicename is `inria_sc` and you have not yet loaded the k8s images on the FIT nodes, to run all the steps described above, you only have to run the following command on your laptop:

```bash
$ ./demo-oai.py -s inria_sc
```

We added the two following options to be used only when the demo-oai.py script has already run at least once, i.e., when FIT nodes have joined the k8s cluster and OAI5G setup is ready for R2lab:

* `--stop` to remove all OAI5G pods. 
* `--start` to launch again all OAI5G pods with same configuration as before.

The two above steps can also be done directly on *fit01* worker node:

```
root@fit01# ./demo-oai.sh stop
root@fit01# ./demo-oai.sh start
```

Note that the *demo-oai.sh* script allows to start/stop specific part of OAI5G pods using the options *start-cn, start-gnb, start-ue, stop-cn, stop-gnb* and *stop-ue*.

### Testing
TO be added later


### Cleanup

To clean up the demo, you should first remove all OAI5G pods.

For that, you can run on your laptop ``./demo-oai.py --stop`` or run the following command on the k8s cluster:

```bash
root@fit01# helm -n oai5g ls --short --all | xargs -L1 helm -n oai5g delete
```

Another possibility is to run on *fit01*:

```
root@fit01# ./demo-oai.sh stop
```

Then, to shutdown FIT/R2lab worker nodes and remove them from the k8s cluster, run on your laptop the following command:

``` bash
$ ./demo-oai.py --cleanup
```
