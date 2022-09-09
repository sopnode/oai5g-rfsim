#!/usr/bin/env python3 -u

"""
This script prepares 4 fit R2lab nodes to join a sopnode k8s cluster for the oai5g demo.
Then, it clones the oai5g-rfsim git directory on one of the 4 fit nodes and applies
different patches on the various OAI5G charts to make them run on the SopNode platform.
Finally, it deploys the different OAI5G pods through the same fit node.

This version requires asynciojobs-0.16.3 or higher; if needed, upgrade with
pip install -U asynciojobs

As opposed to a former version that created 4 different schedulers,
here we create a single one that describes the complete workflow from
the very beginning (all fit nodes off) to the end (all fit nodes off)
and then remove some parts as requested by the script options
"""

from argparse import ArgumentParser, ArgumentDefaultsHelpFormatter

# the default for asyncssh is to be rather verbose
from asyncssh.logging import set_log_level as asyncssh_set_log_level

from asynciojobs import Scheduler

from apssh import YamlLoader, SshJob, Run

# make sure to pip install r2lab
from r2lab import r2lab_hostname, ListOfChoices, ListOfChoicesNullReset, find_local_embedded_script


# where to join; as of this writing:
# sopnode-l1.inria.fr runs a production cluster, and
# sopnode-w2.inria.fr runs an experimental/devel cluster

default_leader = 'sopnode-l1.inria.fr'
devel_leader = 'sopnode-w2.inria.fr'
default_image = 'kubernetes'

default_amf = 1
default_spgwu = 2
default_gnb = 3
default_ue = 9

default_gateway  = 'faraday.inria.fr'
default_slicename  = 'inria_sopnode'
default_namespace = 'oai5g'


def run(*, mode, gateway, slicename,
        leader, namespace, auto_start, load_images,
        amf, spgwu, gnb, ue,
        image, verbose, dry_run):
    """
    run the OAI5G demo on the k8s cluster

    Arguments:
        slicename: the Unix login name (slice name) to enter the gateway
        leader: k8s leader host
        amf: FIT node number in which oai-amf will be deployed
        spgwu: FIT node number in which spgwu-tiny will be deployed
        gnb: FIT node number in which oai-gnb will be deployed
        ue: FIT node number in which oai-nr-ue will be deployed
        image: R2lab k8s image name
    """

    jinja_variables = dict(
        gateway=gateway,
        leader=leader,
        namespace=namespace,
        nodes=dict(
            amf=r2lab_hostname(amf),
            spgwu=r2lab_hostname(spgwu),
            gnb=r2lab_hostname(gnb),
            ue=r2lab_hostname(ue),
        ),
        image=image,
        verbose=verbose,
    )

    # (*) first compute the complete logic (but without check_lease)
    # (*) then simplify/prune according to the mode
    # (*) only then add check_lease in all modes

    loader = YamlLoader("demo-oai.yaml.j2")
    nodes_map, jobs_map, scheduler = loader.load_with_maps(jinja_variables, save_intermediate = verbose)
    scheduler.verbose = verbose
    # debug: to inspect the full scenario
    scheduler.export_as_svgfile("demo-oai-complete-v2")


    # retrieve jobs for the surgery part
    load_images = jobs_map['load_images']
    start_demo = jobs_map['start_demo']
    stop_demo = jobs_map['stop_demo']
    cleanups = jobs_map['cleanup1'], jobs_map['cleanup2']

    # run subparts as requested
    purpose = f"{mode} mode"
    ko_message = f"{purpose} KO"

    if mode == "cleanup":
        scheduler.keep_only_between(starts=cleanups)
        ko_message = f"Could not cleanup demo"
        ok_message = f"Thank you, the k8s {leader} cluster is now clean and FIT nodes have been switched off"
    elif mode == "stop":
        scheduler.keep_only_between(starts=[stop_demo], ends=cleanups, keep_ends=False)
        ko_message = f"Could not delete OAI5G pods"
        ok_message = f"""No more OAI5G pods on the {leader} cluster
Nota: If you are done with the demo, do not forget to clean up the k8s {leader} cluster by running:
\t ./demo-oai.py [--leader {leader}] --cleanup
"""
    elif mode == "start":
        scheduler.keep_only_between(starts=[start_demo], ends=[stop_demo], keep_ends=False)
        ok_message = f"OAI5G demo started, you can check kubectl logs on the {leader} cluster"
        ko_message = f"Could not launch OAI5G pods"
    else:
        scheduler.keep_only_between(ends=[stop_demo], keep_ends=False)
        if not load_images:
            scheduler.bypass_and_remove(load_images)
            purpose += f" (no image loaded)"
        else:
            purpose += f" WITH rhubarbe imaging the FIT nodes"
        if not auto_start:
            scheduler.bypass_and_remove(start_demo)
            purpose += f" (NO auto start)"
            ok_message = f"RUN SetUp OK. You can now start the demo by running ./demo-oai.py --leader {leader} --start"
        else:
            ok_message = f"RUN SetUp and demo started OK. You can now check the kubectl logs on the k8s {leader} cluster."


    # add this job as a requirement for all scenarios
    check_lease = SshJob(
        scheduler=scheduler,
        node = nodes_map['faraday'],
        critical = True,
        verbose=verbose,
        command = Run("rhubarbe leases --check"),
    )
    # this becomes a requirement for all entry jobs
    for entry in scheduler.entry_jobs():
        entry.requires(check_lease)


    scheduler.check_cycles()
    print(10*'*', purpose, "\n", 'See main scheduler in', scheduler.export_as_svgfile("demo-oai-graph"))

    if verbose:
        scheduler.list()

    if dry_run:
        return True

    if not scheduler.orchestrate():
        print(f"{ko_message}: {scheduler.why()}")
        scheduler.debrief()
        return False
    print(ok_message)

    print(80*'*')
    return True

HELP = """
all the forms of the script assume there is a kubernetes cluster
up and running on the chosen leader node,
and that the provided slicename holds the current lease on FIT/R2lab

In its simplest form (no option given), the script will
  * load images on board of the FIT nodes
  * get the nodes to join that cluster
  * and then deploy the k8s pods on that substrate (unless the --no-auto-start is not provided)

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
        "-l", "--load-images", default=False, action='store_true',
        help="load the kubernetes image on the nodes before anything else")

    parser.add_argument(
        "-i", "--image", default=default_image,
        help="kubernetes image to load on nodes")

    parser.add_argument(
        "--leader", default=default_leader,
        help="kubernetes leader node")
    parser.add_argument(
        "--devel", action='store_true', default=False,
        help=f"equivalent to --leader {devel_leader}"
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

    parser.add_argument("-v", "--verbose", default=False,
                        action='store_true', dest='verbose',
                        help="run script in verbose mode")

    parser.add_argument("-n", "--dry-runmode", default=False,
                        action='store_true', dest='dry_run',
                        help="only pretend to run, don't do anything")


    args = parser.parse_args()
    if args.devel:
        args.leader = devel_leader

    if args.start:
        print(f"**** Launch all pods of the oai5g demo on the k8s {args.leader} cluster")
        mode = "start"
    elif args.stop:
        print(f"delete all pods in the {args.namespace} namespace")
        mode = "stop"
    elif args.cleanup:
        print(f"**** Drain and remove FIT nodes from the {args.leader} cluster, then swith off FIT nodes")
        mode = "cleanup"
    else:
        print(f"**** Prepare oai5g demo setup on the k8s {args.leader} cluster with {args.slicename} slicename")
        print(f"OAI5G pods will run on the {args.namespace} k8s namespace")
        print(f"the following FIT nodes will be used:")
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
        mode = "run"
    run(mode=mode, gateway=default_gateway, slicename=args.slicename,
        leader=args.leader, namespace=args.namespace,
        auto_start=args.auto_start, load_images=args.load_images,
        amf=args.amf, spgwu=args.spgwu, gnb=args.gnb, ue=args.ue,
        dry_run=args.dry_run, verbose=args.verbose, image=args.image)


if __name__ == '__main__':
    # return something useful to your OS
    exit(0 if main() else 1)
