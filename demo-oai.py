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

from apssh import (LocalNode, SshNode, SshJob, Run, RunString, RunScript, Push,
                   TimeColonFormatter, Service, Deferred, Capture, Variables)

# make sure to pip install r2lab
from r2lab import r2lab_hostname, ListOfChoices, ListOfChoicesNullReset, find_local_embedded_script


# where to join; as of this writing:
# sopnode-l1.inria.fr runs a production cluster, and
# sopnode-w2.inria.fr runs an experimental/devel cluster

default_master = 'sopnode-l1.inria.fr'
devel_master = 'sopnode-w2.inria.fr'
default_image = 'kubernetes'

default_amf = 'sopnode-w2.inria.fr'
default_spgwu = 'sopnode-w2.inria.fr'
default_gnb = 'sopnode-w2.inria.fr'
default_ue = 1

default_gateway  = 'faraday.inria.fr'
default_slicename  = 'inria_sopnode'
default_namespace = 'oai5g'

default_regcred_name = "r2labuser"
default_regcred_password = "r2labuser-pwd"
default_regcred_email = "r2labuser@turletti.com"


def run(*, gateway, slicename,
        master, namespace, auto_start, load_images,
        reset_k8s, amf, spgwu, gnb, ue,
        regcred_name, regcred_password, regcred_email,
        image, verbose, dry_run ):
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
    """

    faraday = SshNode(hostname=gateway, username=slicename,
                      verbose=verbose,
                      formatter=TimeColonFormatter())


#    node_index = {
#        id: SshNode(gateway=faraday, hostname=r2lab_hostname(id),
#                    username="root",formatter=TimeColonFormatter(),
#                    verbose=verbose)
#        for id in (ue)
#    }
    node_index = { ue:SshNode(gateway=faraday, hostname=r2lab_hostname(default_ue),
            username="root",formatter=TimeColonFormatter(),
            verbose=verbose)}
    worker_ids = [ue]

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
    if reset_k8s:
        leave_joins = [
            SshJob(
                scheduler=scheduler,
                required=green_light,
                node=node,
                critical=False,
                verbose=verbose,
                label=f"Reset data interface, ipip tunnels of worker node {r2lab_hostname(id)} and possibly leave {master} k8s cluster",
                command=[
                    Run("kube-install.sh self-update"),
                    Run("nmcli con down data; nmcli dev status; leave-tunnel"),
                    Run(f"kube-install.sh leave-cluster"),
                    Run(f"sleep 60"),
                    Run("nmcli con up data; nmcli dev status; join-tunnel"),
                    Run(f"kube-install.sh join-cluster r2lab@{master}")
                ]
            ) for id, node in node_index.items()
        ]
        green_light = leave_joins

    # We launch the k8s demo from the FIT node used to run oai-amf
    run_setup = [
        SshJob(
            scheduler=scheduler,
            required=green_light,
            node=node_index[ue],
            critical=True,
            verbose=verbose,
            label=f"Push oai-demo-ai.sh script, clone oai-cn5g-fed, apply patches and run the k8s demo-oai script from {r2lab_hostname(amf)}",
            command=[
                Run("pwd;ls"),
                Push(localpaths="demo-oai.sh", remotepath="/root/"),
                Push(localpaths="p4-network.yaml", remotepath="/root/"),
                Run("chmod a+x /root/demo-oai.sh"),
                RunScript("configure-demo-oai.sh", "update",
                          namespace,amf,
                          spgwu, gnb,
                          r2lab_hostname(ue), regcred_name,
                          regcred_password, regcred_email),
                Run("rm -rf oai-cn5g-fed; git clone -b master https://gitlab.eurecom.fr/oai/cn5g/oai-cn5g-fed"),
                RunScript("demo-oai.sh", "init", namespace),
                Run("export NODE_NETIF=team0"),
                Run("export IFNAME=gnb"),
                Run("export SUBNET_PREFIX=192.168.100"),
                Run("envsubst < /root/p4-network.yaml | kubectl -noai5g create -f -"),
                RunScript("demo-oai.sh", "configure-all", amf,
                          spgwu, gnb,
                          r2lab_hostname(ue)),
            ]
        )
    ]
    if auto_start:
        start_demo = [
            SshJob(
                scheduler=scheduler,
                required=run_setup,
                node=node_index[ue],
                critical=True,
                verbose=verbose,
                label=f"Launch OAI5G pods by calling demo-oai.sh start from {r2lab_hostname(amf)}",
                command=[
                    RunScript("demo-oai.sh", "start", namespace, amf,
	                      spgwu, gnb, r2lab_hostname(ue)),
                ]
            )
        ]

    scheduler.check_cycles()
    output="demo-oai"
    if not auto_start:
        output += "-noauto"
    if load_images:
        output += "-load"
    print(10*'*', 'See main scheduler in', scheduler.export_as_pngfile(output))

    # orchestration scheduler jobs
    if verbose:
        scheduler.list()

    if dry_run:
        return True

    if not scheduler.orchestrate():
        print(f"RUN SetUp KO : {scheduler.why()}")
        scheduler.debrief()
        return False
    if not auto_start:
        print(f"RUN SetUp OK. You can now start the demo by running ./demo-oai.py -m {master} --start")
    else:
        print(f"RUN SetUp and demo started OK. You can now check the kubectl logs on the k8s {master} cluster.")

    print(80*'*')
    return True


def start_demo(*, gateway, slicename,
               master, amf, spgwu, gnb, ue,
               namespace, verbose, dry_run ):
    """
    Launch oai5g pods on the k8s cluster

    Arguments:
        slicename: the Unix login name (slice name) to enter the gateway
        master: k8s master name
        amf: FIT node number in which oai-amf will be deployed
        spgwu: FIT node number in which spgwu-tiny will be deployed
        gnb: FIT node number in which oai-gnb will be deployed
        ue: FIT node number in which oai-nr-ue will be deployed
    """

    faraday = SshNode(hostname=gateway, username=slicename,
                      verbose=verbose, formatter=TimeColonFormatter())

    k8s_worker = SshNode(gateway=faraday, hostname=r2lab_hostname(amf),
                         username="root", formatter=TimeColonFormatter(),
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

    start_demo = [
        SshJob(
            scheduler=scheduler,
            required=green_light,
            node=k8s_worker,
            critical=True,
            verbose=verbose,
            label=f"Launch OAI5G pods by calling demo-oai.sh start from {r2lab_hostname(amf)}",
            command=[
                RunScript("demo-oai.sh", "start", namespace, r2lab_hostname(amf),
                          r2lab_hostname(spgwu), r2lab_hostname(gnb), r2lab_hostname(ue)),
            ]
        )
    ]
    scheduler.check_cycles()
    print(10*'*', 'See main scheduler in',
          scheduler.export_as_pngfile("demo-oai-start"))

    # orchestration scheduler jobs
    if verbose:
        scheduler.list()

    if dry_run:
        return True

    if not scheduler.orchestrate():
        print(f"Could not launch OAI5G pods: {scheduler.why()}")
        scheduler.debrief()
        return False
    print(f"OAI5G demo started, you can check kubectl logs on the {master} cluster")
    print(80*'*')
    return True


def stop_demo(*, gateway, slicename,
              master, amf, spgwu, gnb, ue,
              namespace, verbose, dry_run ):
    """
    delete oai5g pods on the k8s cluster

    same arguments as start_demo - only amf is actually used
    """

    faraday = SshNode(hostname=gateway, username=slicename,
                      verbose=verbose, formatter=TimeColonFormatter())

    k8s_worker = SshNode(gateway=faraday, hostname=r2lab_hostname(amf),
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

    stop_demo = [
        SshJob(
            scheduler=scheduler,
            required=green_light,
            node=k8s_worker,
            critical=True,
            verbose=verbose,
            label=f"Delete OAI5G pods by calling demo-oai.sh stop from {k8s_worker.hostname}",
            command=[
                RunScript("demo-oai.sh", "stop", namespace),
            ]
        )
    ]
    scheduler.check_cycles()
    print(10*'*', 'See main scheduler in',
          scheduler.export_as_pngfile("demo-oai-stop"))

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
    print(f"Nota: If you are done with the demo, do not forget to clean up the k8s {master} cluster by running:")
    print(f"\t ./demo-oai.py [-m {master}] --cleanup")
    return True

def cleanup_demo(*, gateway, slicename, master,
                 amf, spgwu, gnb, ue, verbose, dry_run ):
    """
    drain and delete FIT nodes from the k8s cluster and switch them off

    Arguments:
        slicename: the Unix login name (slice name) to enter the gateway
        master: k8s master name
        amf: FIT node number in which oai-amf will be deployed
        spgwu: FIT node number in which spgwu-tiny will be deployed
        gnb: FIT node number in which oai-gnb will be deployed
        ue: FIT node number in which oai-nr-ue will be deployed
    """

    faraday = SshNode(hostname=gateway, username=slicename,
                      verbose=verbose, formatter=TimeColonFormatter())

    k8s_master = SshNode(gateway=faraday, hostname=master,
                         username="r2lab",formatter=TimeColonFormatter(),
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

    cleanup_k8s = [
        SshJob(
            scheduler=scheduler,
            required=green_light,
            node=k8s_master,
            critical=False,
            verbose=verbose,
            label=f"Drain and delete FIT nodes from the k8s {master} cluster",
            command=[
                Run("fit-drain-nodes; fit-delete-nodes"),
            ]
        )
    ]

    switchoff_fit_nodes = [
        SshJob(
            scheduler=scheduler,
            required=check_lease,
            node=faraday,
            critical=False,
            verbose=verbose,
            label="turning off unused nodes",
            command=[
                Run(f"rhubarbe off {amf} {spgwu} {gnb} {ue}")
            ]
        )
    ]
    scheduler.check_cycles()
    print(10*'*', 'See main scheduler in',
          scheduler.export_as_pngfile("demo-oai-cleanup"))

    # orchestration scheduler jobs
    if verbose:
        scheduler.list()

    if dry_run:
        return True

    if not scheduler.orchestrate():
        print(f"Could not cleanup demo: {scheduler.why()}")
        scheduler.debrief()
        return False
    print(80*'*')
    print(f"Thank you, the k8s {master} cluster is now clean and FIT nodes have been switched off")
    return True

HELP = """

all the forms of the script assume there is a kubernetes cluster
up and running on the chosen master node,
and that the provided slicename holds the current lease on FIT/R2lab

In its simplest form (no option given), the script will
  * load images on board of the FIT nodes
  * get the nodes to join that cluster
  * and then deploy the k8s pods on that substrate (provided the --no-auto-start is not provided, in which case)

Thanks to the --stop and --start option, one can relaunch
the scenario without the need to re-image the selected FIT nodes;
a typical sequence of runs would then be

  * with no option
  * then with the --stop option to destroy the deployment
  * and then with the --start option to re-create the deployment a second time

Or,

  * with the --no-auto-start option to simply load images
  * then with the --start option to create the network
  * and then again any number of --stop / --start calls

At the end of your tests, please run the script with the --cleanup option to clean the k8s cluster and
switch off FIT nodes.
"""


def main():
    """
    CLI frontend
    """

    parser = ArgumentParser(usage=HELP, formatter_class=ArgumentDefaultsHelpFormatter)

    parser.add_argument(
        "--start", default=False,
        action='store_true', dest='start',
        help="start the oai-demo, i.e., launch OAI5G pods")

    parser.add_argument(
        "--stop", default=False,
        action='store_true', dest='stop',
        help="stop the oai-demo, i.e., delete OAI5G pods")

    parser.add_argument(
        "--cleanup", default=False,
        action='store_true', dest='cleanup',
        help="Remove smoothly FIT nodes from the k8s cluster and switch them off")

    parser.add_argument(
        "-a", "--no-auto-start", default=True,
        action='store_false', dest='auto_start',
        help="default is to start the oai-demo after setup")

    parser.add_argument(
        "-N", "--no-reset-k8s", default=True,
        action='store_false', dest='reset_k8s',
        help="default is to reset k8s before setup")

    parser.add_argument(
        "-l", "--load-images", default=False, action='store_true',
        help="load the kubernetes image on the nodes before anything else")

    parser.add_argument(
        "-i", "--image", default=default_image,
        help="kubernetes image to load on nodes")

    parser.add_argument(
        "-m", "--master", default=default_master,
        help="kubernetes master node")
    parser.add_argument(
        "--devel", action='store_true', default=False,
        help=f"equivalent to --master {devel_master}"
    )

    parser.add_argument("--amf", default=default_amf,
                        help="id of the node that runs oai-amf")

    parser.add_argument("--spgwu", default=default_spgwu,
                        help="id of the node that runs oai-spgwu")

    parser.add_argument("--gnb", default=default_gnb,
                        help="id of the node that runs oai-gnb")

    parser.add_argument("--ue", default=default_ue,
                        help="id of the node that runs oai-ue")

    parser.add_argument(
        "--namespace", default=default_namespace,
        help=f"k8s namespace in which OAI5G pods will run")

    parser.add_argument(
        "-s", "--slicename", default=default_slicename,
        help="slicename used to book FIT nodes")

    parser.add_argument(
        "--regcred_name", default=default_regcred_name,
        help=f"registry credential name for docker pull")

    parser.add_argument(
        "--regcred_password", default=default_regcred_password,
        help=f"registry credential password for docker pull")

    parser.add_argument(
        "--regcred_email", default=default_regcred_email,
        help=f"registry credential email for docker pull")

    parser.add_argument("-v", "--verbose", default=False,
                        action='store_true', dest='verbose',
                        help="run script in verbose mode")

    parser.add_argument("-n", "--dry-runmode", default=False,
                        action='store_true', dest='dry_run',
                        help="only pretend to run, don't do anything")


    args = parser.parse_args()
    if args.devel:
        args.master = devel_master

    if args.start:
        print(f"**** Launch all pods of the oai5g demo on the k8s {args.master} cluster")
        start_demo(gateway=default_gateway, slicename=args.slicename, master=args.master,
                   amf=args.amf, spgwu=args.spgwu, gnb=args.gnb, ue=args.ue,
                   namespace=args.namespace, dry_run=args.dry_run, verbose=args.verbose)
    elif args.stop:
        print(f"delete all pods in the {args.namespace} namespace")
        stop_demo(gateway=default_gateway, slicename=args.slicename, master=args.master,
                  amf=args.amf, spgwu=args.spgwu, gnb=args.gnb, ue=args.ue,
                  namespace=args.namespace, dry_run=args.dry_run, verbose=args.verbose)

    elif args.cleanup:
        print(f"**** Drain and remove FIT nodes from the {args.master} cluster, then swith off FIT nodes")
        cleanup_demo(gateway=default_gateway, slicename=args.slicename, master=args.master,
                     amf=args.amf, spgwu=args.spgwu, gnb=args.gnb, ue=args.ue,
                     dry_run=args.dry_run, verbose=args.verbose)
    else:
        print(f"**** Prepare oai5g demo setup on the k8s {args.master} cluster with {args.slicename} slicename")
        print(f"OAI5G pods will run on the {args.namespace} k8s namespace")
        print(f"Following FIT nodes will be used:")
        print(f"\t{r2lab_hostname(args.amf)} for oai-amf")
        print(f"\t{r2lab_hostname(args.spgwu)} for oai-spgwu-tiny")
        print(f"\t{r2lab_hostname(args.gnb)} for oai-gnb")
        print(f"\t{r2lab_hostname(args.ue)} for oai-nr-ue")
        if args.load_images:
            print(f"with k8s image {args.image} loaded")
        if args.auto_start:
            print("Automatically start the demo after setup")
        else:
            print("Do not start the demo after setup")

        run(gateway=default_gateway, slicename=args.slicename,
            master=args.master, namespace=args.namespace,
            auto_start=args.auto_start, load_images=args.load_images,
            reset_k8s=args.reset_k8s,
            amf=args.amf, spgwu=args.spgwu, gnb=args.gnb, ue=args.ue,
            regcred_name=args.regcred_name, regcred_password=args.regcred_password,
            regcred_email=args.regcred_email,
            dry_run=args.dry_run, verbose=args.verbose,
            image=args.image,
            )


if __name__ == '__main__':
    # return something useful to your OS
    exit(0 if main() else 1)
