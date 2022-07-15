#!/usr/bin/env python3 -u

"""
This script prepares 4 fit R2lab nodes to join a sopnode k8s cluster for the oai5g demo.
Then, it clones the oai5g-rfsim git directory on one of the 4 fit nodes and applies
different patches on the various OAI5G charts to make them run on the SopNode platform.
Finally, it deploys the different OAI5G pods through the same fit node.

"""

from argparse import ArgumentParser, ArgumentDefaultsHelpFormatter
from pathlib import Path

# the default for asyncssh is to be rather verbose
import logging
from asyncssh.logging import set_log_level as asyncssh_set_log_level

from asynciojobs import Job, Scheduler, PrintJob

from apssh import (LocalNode, SshNode, SshJob, Run, RunString, RunScript,
                   TimeColonFormatter, Service, Deferred, Capture, Variables)

# make sure to pip install r2lab
from r2lab import r2lab_hostname, ListOfChoices, ListOfChoicesNullReset, find_local_embedded_script


# where to join; as of this writing:
# sopnode-l1.inria.fr runs a production cluster, and
# sopnode-w2.inria.fr runs an experimental/devel cluster

default_master = 'sopnode-l1.inria.fr'
default_image = 'kubernetes'

default_amf = 1
default_spgwu = 2
default_gnb = 3
default_ue = 9

default_gateway  = 'faraday.inria.fr'
default_slicename  = 'inria_sopnode'
default_namespace = 'oai5g'

def run(*, gateway, slicename,
        master, namespace,
        amf, spgwu, gnb, ue,
        image, load_images,
        verbose, dry_run ):
    """
    run the OAI5G demo on the k8s cluster

    Arguments:
        slicename: the Unix login name (slice name) to enter the gateway
        master: k8s master host
        amf: FIT node number in which oai-amf will be deployed
        spgwu: FIT node number in which spgwu-tiny will be deployed
        gnb: FIT node number in which oai-gnb will be deployed
        ue: FIT node number in which oai-nr-ue will be deployed
        image: R2lab k8s image name
        load_images: flag if k8s images will be loaded on FIT nodes
    """

    faraday = SshNode(hostname=gateway, username=slicename,
                      verbose=verbose,
                      formatter=TimeColonFormatter())
    
    hostnames = [r2lab_hostname(x) for x in (amf, spgwu, gnb, ue)]


    node_index = {
        id: SshNode(gateway=faraday, hostname=r2lab_hostname(id),
                    username="root",formatter=TimeColonFormatter(),
                    verbose=verbose)
        for id in (amf, spgwu, gnb, ue)
    }
    worker_ids = [amf, spgwu, gnb, ue]

    # the global scheduler
    scheduler = Scheduler(verbose=verbose)

    ##########
    check_lease = SshJob(
        scheduler=scheduler,
        node = faraday,
        critical = True,
        verbose=verbose,
        command = Run("rhubarbe leases --check"),
    )

    green_light = check_lease

    if load_images:
        green_light = [
            SshJob(
                scheduler=scheduler,
                required=check_lease,
                node=faraday,
                critical=True,
                verbose=verbose,
                label = f"Load image {image} on worker nodes",
                commands=[
                    Run("rhubarbe", "load", *worker_ids, "-i", image),
                    Run("rhubarbe", "wait", *worker_ids),
                ],
            ),
# for now, useless to switch off other nodes as we use RfSimulator            
#            SshJob(
#                scheduler=scheduler,
#                required=check_lease,
#                node=faraday,
#                critical=False,
#                verbose=verbose,
#                label="turning off unused nodes",
#                command=[
#                    Run("rhubarbe bye --all "
#                        + "".join(f"~{x} " for x in nodes))
#                    Run("sleep 1") 
#                ]
#            )
        ]

    prepares = [
        SshJob(
            scheduler=scheduler,
            required=green_light,
            node=node,
            critical=False,
            verbose=verbose,
            label=f"Reset data interface, ipip tunnels of worker node {r2lab_hostname(id)} and possibly leave {master} k8s cluster",
            command=[
                Run("nmcli con down data; nmcli dev status; leave-tunnel"),
                Run(f"kube-install.sh leave-cluster r2lab@{master}; sleep 60"),
            ]
        ) for id, node in node_index.items()
    ]

    joins = [
        SshJob(
            scheduler=scheduler,
            required=prepares,
            node=node,
            critical=True,
            verbose=verbose,
            label=f"Set data interface and ipip tunnels of worker node {r2lab_hostname(id)} and add it to {master} k8s cluster",
            command=[
                Run("nmcli con up data; nmcli dev status; join-tunnel"),
                Run(f"kube-install.sh join-cluster r2lab@{master}")
            ]
        ) for id, node in node_index.items()
    ]

    # We launch the k8s demo from the FIT node used to run oai-amf
    run_oai5g = [
        SshJob(
            scheduler=scheduler,
            required=joins,
            node=node_index[amf],
            critical=True,
            verbose=verbose,
            label=f"Clone oai-cn5g-fed, apply patches and run the k8s demo-oai script from {r2lab_hostname(amf)}",
            command=[
                Run("rm -rf oai-cn5g-fed; git clone -b master https://gitlab.eurecom.fr/oai/cn5g/oai-cn5g-fed"),
                RunScript("config-oai5g-sopnode.sh", r2lab_hostname(amf),
                          r2lab_hostname(spgwu), r2lab_hostname(gnb),
                          r2lab_hostname(ue)),
                RunScript("demo-oai.sh", "start", namespace, r2lab_hostname(amf),
                          r2lab_hostname(spgwu), r2lab_hostname(gnb), r2lab_hostname(ue)),
            ]
        )
    ]
    
    scheduler.check_cycles()
    print(10*'*', 'See main scheduler in',
          scheduler.export_as_pngfile("oai-demo"))

    # orchestration scheduler jobs
    if verbose:
        scheduler.list()

    if dry_run:
        return True

    if not scheduler.orchestrate():
        print(f"RUN KO : {scheduler.why()}")
        scheduler.debrief()
        return False
    print(f"RUN OK. You can now log on oai@{master} and check logs.")
    print(80*'*')
    return True


def delete_oai5g_pods(*, gateway, slicename,
                      master, namespace, fitnode, 
                      verbose, dry_run ):
    """
    delete oai5g pods on the k8s cluster

    Arguments:
        slicename: the Unix login name (slice name) to enter the gateway
        master: k8s master name
        fitnode: FIT node used to run k8s commands
    """

    faraday = SshNode(hostname=gateway, username=slicename,
                      verbose=verbose, formatter=TimeColonFormatter())

    k8s_worker = SshNode(gateway=faraday, hostname=r2lab_hostname(fitnode),
                         username="root",formatter=TimeColonFormatter(),
                         verbose=verbose)

    # the global scheduler
    scheduler = Scheduler(verbose=verbose)

    ##########
    check_lease = SshJob(
        scheduler=scheduler,
        node = faraday,
        critical = True,
        verbose=verbose,
        command = Run("rhubarbe leases --check"),
    )

    green_light = check_lease
    
    run_oai5g = [
        SshJob(
            scheduler=scheduler,
            required=green_light,
            node=k8s_worker,
            critical=True,
            verbose=verbose,
            label=f"Delete OAI5G pods by calling demo-oai.sh stop from {r2lab_hostname(fitnode)}",
            command=[
                RunScript("demo-oai.sh", "stop", namespace),
            ]
        )
    ]
    scheduler.check_cycles()
    print(10*'*', 'See main scheduler in',
          scheduler.export_as_pngfile("oai-demo-stop"))

    # orchestration scheduler jobs
    if verbose:
        scheduler.list()

    if dry_run:
        return True

    if not scheduler.orchestrate():
        print(f"Could not delete OAI5G pods: {scheduler.why()}")
        scheduler.debrief()
        return False
    print(f"No more OAI5G pods on the {master} cluster")
    print(80*'*')
    return True



def main():
    """
    CLI frontend
    """
        
    parser = ArgumentParser(formatter_class=ArgumentDefaultsHelpFormatter)

    parser.add_argument("--amf", default=default_amf,
                        help="id of the node that runs oai-amf")

    parser.add_argument("--spgwu", default=default_spgwu,
                        help="id of the node that runs oai-spgwu")

    parser.add_argument("--gnb", default=default_gnb,
                        help="id of the node that runs oai-gnb")

    parser.add_argument("--ue", default=default_ue,
                        help="id of the node that runs oai-ue")

    parser.add_argument(
        "-i", "--image", default=default_image,
        help="kubernetes image to load on nodes")
    
    parser.add_argument(
        "-m", "--master", default=default_master,
        help=f"kubernetes master node, default is {default_master}")
    
    parser.add_argument(
        "--namespace", default=default_namespace,
        help=f"k8s namespace in whcih AOI5G pods will run, default is {default_namespace}")
    
    parser.add_argument(
        "-s", "--slicename", default=default_slicename,
        help="slicename used to book FIT nodes, default is {default_slicename}")

    parser.add_argument("-l", "--load", dest='load_images',
                        action='store_true', default=False,
                        help='load images as well')
    
    parser.add_argument("-v", "--verbose", default=False,
                        action='store_true', dest='verbose',
                        help="run script in verbose mode")
    
    parser.add_argument("-n", "--dry-runmode", default=False,
                        action='store_true', dest='dry_run',
                        help="only pretend to run, don't do anything")
    
    parser.add_argument("--stop", default=False,
                        action='store_true', dest='stop',
                        help="stop the oai-demo")


    args = parser.parse_args()

    if args.stop:
        print(f"**** Running oai5g demo on k8s master {args.master}")
        delete_oai5g_pods(gateway=default_gateway, slicename=args.slicename, master=args.master,
                          namespace=args.namespace, fitnode=args.amf,
                          dry_run=args.dry_run, verbose=args.verbose)
    else:
        print(f"**** Running oai5g demo on k8s master {args.master} with {args.slicename} slicename")
        print(f"OAI5G pods will run on the {args.namespace} k8s namespace")
        print(f"Following FIT nodes will be used:")
        print(f"\t{r2lab_hostname(args.amf)} for oai-amf")
        print(f"\t{r2lab_hostname(args.spgwu)} for oai-spgwu-tiny")
        print(f"\t{r2lab_hostname(args.gnb)} for oai-gnb")
        print(f"\t{r2lab_hostname(args.ue)} for oai-nr-ue")
        if args.load_images:
            print(f"with k8s image {args.image} loaded")
    
    
        run(gateway=default_gateway, slicename=args.slicename,
            master=args.master, namespace=args.namespace,
            amf=args.amf, spgwu=args.spgwu, gnb=args.gnb, ue=args.ue,
            dry_run=args.dry_run,verbose=args.verbose,
            load_images=args.load_images, image=args.image
            )


if __name__ == '__main__':
    # return something useful to your OS
    exit(0 if main() else 1)
