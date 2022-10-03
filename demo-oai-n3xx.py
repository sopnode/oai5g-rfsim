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

from apssh import YamlLoader, SshJob, Run, Push, Service

# make sure to pip install r2lab
from r2lab import r2lab_hostname, ListOfChoices, ListOfChoicesNullReset, find_local_embedded_script


# where to join; as of this writing:
# sopnode-l1.inria.fr runs a production cluster, and
# sopnode-w2.inria.fr runs an experimental/devel cluster

default_leader = 'sopnode-l1.inria.fr'
devel_leader = 'sopnode-w2.inria.fr'
default_image = 'kubernetes'
default_quectel_image = "quectel-wwan0"

default_amf = 1
default_spgwu = 2
default_gnb = 3
default_ue = 9
default_quectel_nodes = []

default_gateway  = 'faraday.inria.fr'
default_slicename  = 'inria_sopnode'
default_namespace = 'oai5g'

default_regcred_name = "r2labuser"
default_regcred_password = "r2labuser-pwd"
default_regcred_email = "r2labuser@turletti.com"


def run(*, mode, gateway, slicename,
        leader, namespace, auto_start, load_images,
        k8s_reset, amf, spgwu, gnb, ue, quectel_nodes,
        regcred_name, regcred_password, regcred_email,
        image, quectel_image, verbose, dry_run):
    """
    run the OAI5G demo on the k8s cluster

    Arguments:
        slicename: the Unix login name (slice name) to enter the gateway
        leader: k8s leader host
        amf: FIT node number in which oai-amf will be deployed
        spgwu: FIT node number in which spgwu-tiny will be deployed
        gnb: FIT node number in which oai-gnb will be deployed
        ue: FIT node number in which oai-nr-ue will be deployed
        quectel_nodes: list of indices of quectel UE nodes to use
        image: R2lab k8s image name
    """

    quectel_ids = quectel_nodes[:]
    quectel = len(quectel_ids) > 0

    INCLUDES = [find_local_embedded_script(x) for x in (
      "r2labutils.sh", "nodes.sh",
    )]

    quectelCM_service = Service(
        command="quectel-CM -s oai.ipv4 -4",
        service_id="QuectelCM",
        verbose=verbose,
    )

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
        quectel_nodes=dict((n, r2lab_hostname(n)) for n in quectel_nodes),
        regcred=dict(
            name=regcred_name,
            password=regcred_password,
            email=regcred_email,
        ),
        image=image,
        quectel_image=quectel_image,
        verbose=verbose,
        nodes_sh=find_local_embedded_script("nodes.sh"),
        INCLUDES=INCLUDES,
        quectel_service_start = quectelCM_service.start_command()
    )

    # (*) first compute the complete logic (but without check_lease)
    # (*) then simplify/prune according to the mode
    # (*) only then add check_lease in all modes

    loader = YamlLoader("demo-oai.yaml.j2")
    nodes_map, jobs_map, scheduler = loader.load_with_maps(jinja_variables, save_intermediate = verbose)
    scheduler.verbose = verbose
    # debug: to visually inspect the full scenario
    if verbose:
        complete_output = "demo-oai-complete"
        print(f"Verbose: storing full scenario (before mode processing) in {complete_output}.svg")
        scheduler.export_as_svgfile(complete_output)


    # retrieve jobs for the surgery part
    j_load_images = jobs_map['load-images']
    j_start_demo = jobs_map['start-demo']
    j_stop_demo = jobs_map['stop-demo']
    j_cleanups = jobs_map['cleanup1'], jobs_map['cleanup2']
    j_leave_joins = [jobs_map[k] for k in jobs_map if k.startswith('leave-join')]
    j_prepare_quectels = jobs_map['prepare-quectels']
    j_init_quectels = [jobs_map[k] for k in jobs_map if k.startswith('init-quectel-')]
    j_attach_quectels = [jobs_map[k] for k in jobs_map if k.startswith('attach-quectel-')]
    j_detach_quectels = [jobs_map[k] for k in jobs_map if k.startswith('detach-quectel-')]

    # run subparts as requested
    purpose = f"{mode} mode"
    ko_message = f"{purpose} KO"

    if mode == "cleanup":
        scheduler.keep_only_between(starts=j_cleanups)
        ko_message = f"Could not cleanup demo"
        ok_message = f"Thank you, the k8s {leader} cluster is now clean and FIT nodes have been switched off"
    elif mode == "stop":
        scheduler.keep_only_between(starts=[j_stop_demo], ends=j_cleanups, keep_ends=False)
        ko_message = f"Could not delete OAI5G pods"
        ok_message = f"""No more OAI5G pods on the {leader} cluster
Nota: If you are done with the demo, do not forget to clean up the k8s {leader} cluster by running:
\t ./demo-oai.py [--leader {leader}] --cleanup
"""
    elif mode == "start":
        scheduler.keep_only_between(starts=[j_start_demo], ends=[j_stop_demo], keep_ends=False)
        ok_message = f"OAI5G demo started, you can check kubectl logs on the {leader} cluster"
        ko_message = f"Could not launch OAI5G pods"
    else:
        scheduler.keep_only_between(ends=[j_stop_demo], keep_ends=False)
        if not load_images:
            scheduler.bypass_and_remove(j_load_images)
            purpose += f" (no image loaded)"
            scheduler.bypass_and_remove(j_prepare_quectels)
            purpose += f" (no quectel node prepared)"
        else:
            purpose += f" WITH rhubarbe imaging the FIT nodes"
            if not quectel:
                scheduler.bypass_and_remove(j_prepare_quectels)
                purpose += f" (no quectel node prepared)"
            else:
                purpose += f" (quectel node(s) prepared)"

        if not auto_start:
            scheduler.bypass_and_remove(j_start_demo)
            purpose += f" (NO auto start)"
            ok_message = f"RUN SetUp OK. You can now start the demo by running ./demo-oai.py --leader {leader} --start"
        else:
            ok_message = f"RUN SetUp and demo started OK. You can now check the kubectl logs on the k8s {leader} cluster."
        if not k8s_reset:
            for job in j_leave_joins:
                scheduler.bypass_and_remove(job)
            purpose += " (k8s reset SKIPPED)"
        else:
            purpose += " (k8s RESET)"


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
        "-k", "--no-k8s-reset", default=True,
	action='store_false', dest='k8s_reset',
	help="default is to reset k8s before setup")

    parser.add_argument(
        "-l", "--load-images", default=False, action='store_true',
        help="load the kubernetes image on the nodes before anything else")

    parser.add_argument(
        "-i", "--image", default=default_image,
        help="kubernetes image to load on nodes")

    parser.add_argument("--quectel-image", dest="quectel_image",
                        default=default_quectel_image)

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

    parser.add_argument(
        "--regcred_name", default=default_regcred_name,
        help=f"registry credential name for docker pull")

    parser.add_argument(
        "--regcred_password", default=default_regcred_password,
        help=f"registry credential password for docker pull")

    parser.add_argument(
        "--regcred_email", default=default_regcred_email,
        help=f"registry credential email for docker pull")

    parser.add_argument(
        "-Q", "--quectel-id", dest='quectel_nodes',
        default=default_quectel_nodes,
        choices=["9", "18", "32", "35"],
	action=ListOfChoices,
	help="specify as many node ids with Quectel UEs as you want.")

    parser.add_argument("-v", "--verbose", default=False,
                        action='store_true', dest='verbose',
                        help="run script in verbose mode")

    parser.add_argument("-n", "--dry-runmode", default=False,
                        action='store_true', dest='dry_run',
                        help="only pretend to run, don't do anything")


    args = parser.parse_args()
    if args.devel:
        args.leader = devel_leader

    if args.quectel_nodes:
        for quectel in args.quectel_nodes:
            print(f"Using Quectel UE on node {quectel}")
    else:
        print("No Quectel UE involved")

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
        print(f"FIT image loading:",
              f"YES with {args.image}" if args.load_images
              else "NO (use --load-images if needed)")
        if args.auto_start:
            print("Automatically start the demo after setup")
        else:
            print("Do not start the demo after setup")
        mode = "run"
    run(mode=mode, gateway=default_gateway, slicename=args.slicename,
        leader=args.leader, namespace=args.namespace,
        auto_start=args.auto_start, load_images=args.load_images,
        amf=args.amf, spgwu=args.spgwu, gnb=args.gnb, ue=args.ue,
        quectel_nodes=args.quectel_nodes,
        regcred_name=args.regcred_name,
        regcred_password=args.regcred_password,
        regcred_email=args.regcred_email,
        dry_run=args.dry_run, verbose=args.verbose, image=args.image,
        quectel_image=args.quectel_image, k8s_reset=args.k8s_reset)


if __name__ == '__main__':
    # return something useful to your OS
    exit(0 if main() else 1)