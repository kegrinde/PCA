library(argparser)
library(TopmedPipeline)
library(SeqVarTools)
library(SNPRelate)
library(gdsfmt)
sessionInfo()

argp <- arg_parser("Correlation of variants with PCs")
argp <- add_argument(argp, "config", help="path to config file")
#argp <- add_argument(argp, "--chromosome", help="chromosome (1-24 or X,Y)", type="character")
argp <- add_argument(argp, "--version", help="pipeline version number")
argv <- parse_args(argp)
cat(">>> TopmedPipeline version ", argv$version, "\n")
config <- readConfig(argv$config)
#chr <- intToChr(argv$chromosome)

required <- c("gds_file",
              "pca_file")
optional <- c("n_pcs"=20,
              "out_file"="pca_load.RData",
              "variant_include_file"=NA)
config <- setConfigDefaults(config, required, optional)
print(config)

## gds file can have two parts split by chromosome identifier
gdsfile <- config["gds_file"]
outfile <- config["out_file"]
varfile <- config["variant_include_file"]
#if (!is.na(chr)) {
#    message("Running on chromosome ", chr)
#    bychrfile <- grepl(" ", gdsfile) # do we have one file per chromosome?
#    gdsfile <- insertChromString(gdsfile, chr)
#    outfile <- insertChromString(outfile, chr, err="out_file")
#    varfile <- insertChromString(varfile, chr)
#}

gds <- seqOpen(config["gds_file"])

if (!is.na(varfile)) {
    variant.id <- getobj(varfile)
} else {
    filt <- seqGetData(gds, "annotation/filter") == "PASS"
    snv <- isSNV(gds, biallelic=TRUE)
    variant.id <- seqGetData(gds, "variant.id")[filt & snv]
}

### if we have a chromosome indicator but only one gds file, select chromosome
#if (!is.na(chr) && !bychrfile) {
#    chrom <- seqGetData(gds, "chromosome")
#    seqSetFilter(gds, variant.sel=(chrom == chr), verbose=FALSE)
#    var.chr <- seqGetData(gds, "variant.id")
#    variant.id <- intersect(variant.id, var.chr)
#    seqResetFilter(gds, verbose=FALSE)
#}
message("Using ", length(variant.id), " variants")

pca <- getobj(config["pca_file"])
n_pcs <- min(as.integer(config["n_pcs"]), length(pca$sample.id))
#nt <- countThreads()
#snpgdsPCACorr(pca, gdsobj=gds, snp.id=variant.id, eig.which=1:n_pcs,
#              num.thread=nt, outgds=outfile)
loadings <- snpgdsPCASNPLoading(pca, gdsobj = gds)

## add chromosome and position to output
#seqSetFilter(gds, variant.id=variant.id)
seqSetFilter(gds, variant.id=loadings$snp.id)
chromosome <- seqGetData(gds, "chromosome")
position <- seqGetData(gds, "position")
seqClose(gds)

#pca.corr <- openfn.gds(outfile, readonly=FALSE)
#add.gdsn(pca.corr, "chromosome", chromosome, compress="LZMA_RA")
#add.gdsn(pca.corr, "position", position, compress="LZMA_RA")
#closefn.gds(pca.corr)
#cleanup.gds(outfile)
loadings$snp.chrom <- chromosome
loadings$snp.pos <- position

save(loadings, file = outfile)

# mem stats
ms <- gc()
cat(">>> Max memory: ", ms[1,6]+ms[2,6], " MB\n")
