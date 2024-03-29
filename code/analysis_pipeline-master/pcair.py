#! /usr/bin/env python2.7

"""PC-AiR"""

import TopmedPipeline
import sys
import os
from argparse import ArgumentParser
from copy import deepcopy

description = """
PCA with the following steps:
1) Find unrelated sample set
2) Select SNPs with LD pruning using unrelated samples
3) PCA (using unrelated set, then project relatives)
"""

parser = ArgumentParser(description=description)
parser.add_argument("config_file", help="configuration file")
parser.add_argument("--ld_pruning", action="store_true", default=False,
                    help="run LD pruning of variants prior to PCA")
parser.add_argument("-c", "--chromosomes", default="1-22",
                    help="range of chromosomes [default %(default)s]")
parser.add_argument("--cluster_type", default="UW_Cluster",
                    help="type of compute cluster environment [default %(default)s]")
parser.add_argument("--cluster_file", default=None,
                    help="json file containing options to pass to the cluster")
parser.add_argument("--verbose", action="store_true", default=False,
                    help="enable verbose output to help debug")
parser.add_argument("-n", "--ncores", default="1-8",
                    help="number of cores to use; either a number (e.g, 1) or a range of numbers (e.g., 1-4) [default %(default)s]")
parser.add_argument("-e", "--email", default=None,
                    help="email address for job reporting")
parser.add_argument("--print_only", action="store_true", default=False,
                    help="print qsub commands without submitting")
parser.add_argument("--version", action="version",
                    version="TopmedPipeline "+TopmedPipeline.__version__,
                    help="show the version number and exit")
args = parser.parse_args()

configfile = args.config_file
ld = args.ld_pruning
chromosomes = args.chromosomes
cluster_file = args.cluster_file
cluster_type = args.cluster_type
ncores = args.ncores
email = args.email
print_only = args.print_only
verbose = args.verbose

version = "--version " + TopmedPipeline.__version__

cluster = TopmedPipeline.ClusterFactory.createCluster(cluster_type, cluster_file, verbose)

pipeline = cluster.getPipelinePath()
driver = os.path.join(pipeline, "runRscript.sh")

configdict = TopmedPipeline.readConfig(configfile)
configdict = TopmedPipeline.directorySetup(configdict, subdirs=["config", "data", "log", "plots"])


job = "find_unrelated"

rscript = os.path.join(pipeline, "R", job + ".R")

config = deepcopy(configdict)
config["out_related_file"] = configdict["data_prefix"] + "_related.RData"
config["out_unrelated_file"] = configdict["data_prefix"] + "_unrelated.RData"
configfile = configdict["config_prefix"] + "_" + job + ".config"
TopmedPipeline.writeConfig(config, configfile)

jobid = cluster.submitJob(job_name=job, cmd=driver, args=[rscript, configfile, version], email=email, print_only=print_only)


if ld:
    job = "ld_pruning"

    rscript = os.path.join(pipeline, "R", job + ".R")

    config = deepcopy(configdict)
    config["sample_include_file"] = configdict["data_prefix"] + "_unrelated.RData"
    config["out_file"] = configdict["data_prefix"] + "_pruned_variants_chr .RData"
    configfile = configdict["config_prefix"] + "_" + job + ".config"
    TopmedPipeline.writeConfig(config, configfile)

    jobid = cluster.submitJob(job_name=job, cmd=driver, args=["-c", rscript, configfile, version], holdid=[jobid], array_range=chromosomes, email=email, print_only=print_only)


    job = "combine_variants"

    rscript = os.path.join(pipeline, "R", job + ".R")

    config = dict()
    config["chromosomes"] = TopmedPipeline.parseChromosomes(chromosomes)
    config["in_file"] = configdict["data_prefix"] + "_pruned_variants_chr .RData"
    config["out_file"] = configdict["data_prefix"] + "_pruned_variants.RData"
    configfile = configdict["config_prefix"] + "_" + job + ".config"
    TopmedPipeline.writeConfig(config, configfile)

    jobid = cluster.submitJob(job_name=job, cmd=driver, args=[rscript, configfile, version], holdid=[jobid], email=email, print_only=print_only)


job = "pca_byrel"

rscript = os.path.join(pipeline, "R", job + ".R")

config = deepcopy(configdict)
config["related_file"] = configdict["data_prefix"] + "_related.RData"
config["unrelated_file"] = configdict["data_prefix"] + "_unrelated.RData"
if ld:
    config["variant_include_file"] = configdict["data_prefix"] + "_pruned_variants.RData"
config["out_file"] = configdict["data_prefix"] + "_pcair.RData"
config["out_file_unrel"] = configdict["data_prefix"] + "_pcair_unrel.RData"
configfile = configdict["config_prefix"] + "_" + job + ".config"
TopmedPipeline.writeConfig(config, configfile)

jobid_pca = cluster.submitJob(job_name=job, cmd=driver, args=[rscript, configfile, version], holdid=[jobid], request_cores=ncores, email=email, print_only=print_only)


job = "pca_plots"
jobsPlots = []
rscript = os.path.join(pipeline, "R", job + ".R")

config = deepcopy(configdict)
config["pca_file"] = configdict["data_prefix"] + "_pcair.RData"
config["out_file_scree"] = configdict["plots_prefix"] + "_pca_scree.pdf"
config["out_file_pc12"] = configdict["plots_prefix"] + "_pca_pc12.pdf"
config["out_file_parcoord"] = configdict["plots_prefix"] + "_pca_parcoord.pdf"
config["out_file_pairs"] = configdict["plots_prefix"] + "_pca_pairs.png"
configfile = configdict["config_prefix"] + "_" + job + ".config"
TopmedPipeline.writeConfig(config, configfile)

jobid = cluster.submitJob(job_name=job, cmd=driver, args=[rscript, configfile, version], holdid=[jobid_pca], email=email, print_only=print_only)
jobsPlots.append(jobid)


job = "pca_corr"

rscript = os.path.join(pipeline, "R", job + ".R")

config = deepcopy(configdict)
config["pca_file"] = configdict["data_prefix"] + "_pcair_unrel.RData"
config["out_file"] = configdict["data_prefix"] + "_pcair_corr_chr .gds"
configfile = configdict["config_prefix"] + "_" + job + ".config"
TopmedPipeline.writeConfig(config, configfile)

# single core only
jobid = cluster.submitJob(job_name=job, cmd=driver, args=["-c", rscript, configfile, version], holdid=[jobid_pca], array_range=chromosomes, email=email, print_only=print_only)


job = "pca_corr_plots"

rscript = os.path.join(pipeline, "R", job + ".R")

config = deepcopy(configdict)
config["chromosomes"] = TopmedPipeline.parseChromosomes(chromosomes)
config["corr_file"] = configdict["data_prefix"] + "_pcair_corr_chr .gds"
config["out_prefix"] = configdict["plots_prefix"] + "_pcair_corr"
configfile = configdict["config_prefix"] + "_" + job + ".config"
TopmedPipeline.writeConfig(config, configfile)

jobid = cluster.submitJob(job_name=job, cmd=driver, args=[rscript, configfile, version], holdid=[jobid], email=email, print_only=print_only)
jobsPlots.append(jobid)


cluster.submitJob(job_name="cleanup", cmd=os.path.join(pipeline, "cleanup.sh"), holdid=jobsPlots, print_only=print_only)
