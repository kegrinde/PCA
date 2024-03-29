library(argparser)
library(TopmedPipeline)
library(SeqVarTools)
library(SNPRelate)
sessionInfo()

argp <- arg_parser("LD pruning")
argp <- add_argument(argp, "config", help="path to config file")
argp <- add_argument(argp, "--chromosome", help="chromosome (1-24 or X,Y)", type="character")
argp <- add_argument(argp, "--version", help="pipeline version number")
argv <- parse_args(argp)
cat(">>> TopmedPipeline version ", argv$version, "\n")
config <- readConfig(argv$config)
chr <- intToChr(argv$chromosome)

required <- c("gds_file")
optional <- c("exclude_pca_corr"=TRUE,
              "genome_build"="hg38",
              "ld_r_threshold"=0.32,
              "ld_win_size"=10,
              "maf_threshold"=0.01,
              "out_file"="pruned_variants.RData",
              "sample_include_file"=NA,
              "variant_include_file"=NA)
config <- setConfigDefaults(config, required, optional)
print(config)

## gds file can have two parts split by chromosome identifier
gdsfile <- config["gds_file"]
outfile <- config["out_file"]
varfile <- config["variant_include_file"]
if (!is.na(chr)) {
    message("Running on chromosome ", chr)
    bychrfile <- grepl(" ", gdsfile) # do we have one file per chromosome?
    gdsfile <- insertChromString(gdsfile, chr)
    outfile <- insertChromString(outfile, chr, err="out_file")
    varfile <- insertChromString(varfile, chr)
}

gds <- seqOpen(gdsfile)

if (!is.na(config["sample_include_file"])) {
    sample.id <- getobj(config["sample_include_file"])
    message("Using ", length(sample.id), " samples")
} else {
    sample.id <- NULL
    message("Using all samples")
}

if (!is.na(varfile)) {
    filterByFile(gds, varfile)
}

## if we have a chromosome indicator but only one gds file, select chromosome
if (!is.na(chr) && !bychrfile) {
    filterByChrom(gds, chr)
}

filterByPass(gds)
filterBySNV(gds)

## filter out my list of regions rather than TOPMed list
build <- switch(config["genome_build"], hg38 = 'b38', hg19 = 'b37', hg36 = 'b36')
if (as.logical(config["exclude_pca_corr"])) {
    ## load my list of filters
    filt.fn <- paste0('../data/highLD/', 'exclude_', build, '.txt')
    filt <- read.table(filt.fn, stringsAsFactors = F)
    message("Using exclusions list:", filt.fn)
    names(filt) <-  c('chrom','start.base','end.base','comment')
    filt$chrom <- as.numeric(substr(filt$chrom, start = 4, stop = nchar(filt$chrom)))
    ## figure out which SNVs fall in these regions
    chrom <- seqGetData(gds, 'chromosome')
    pos <- seqGetData(gds, 'position')
    pca.filt <- rep(TRUE, length(chrom))
    for(f in 1:nrow(filt)){
      pca.filt[chrom == filt$chrom[f] & filt$start.base[f] < pos & pos < filt$end.base[f]] <- FALSE
    }
    ## set filter
    seqSetFilter(gds, variant.sel = pca.filt, action = "intersect", verbose = TRUE)
}

variant.id <- seqGetData(gds, "variant.id")
message("Using ", length(variant.id), " variants")

maf <- as.numeric(config["maf_threshold"])
r <- as.numeric(config["ld_r_threshold"])
win <- as.numeric(config["ld_win_size"]) * 1e6

set.seed(100) # make pruned SNPs reproducible
snpset <- snpgdsLDpruning(gds, sample.id=sample.id, snp.id=variant.id, maf=maf,
                          method="corr", slide.max.bp=win, ld.threshold=r,
                          num.thread=countThreads())

pruned <- unlist(snpset, use.names=FALSE)
save(pruned, file=outfile)

seqClose(gds)

# mem stats
ms <- gc()
cat(">>> Max memory: ", ms[1,6]+ms[2,6], " MB\n")
