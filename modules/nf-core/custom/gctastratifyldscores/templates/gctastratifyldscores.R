#!/usr/bin/env Rscript

input_file <- "$ld_scores"
output_prefix <- "$prefix"
ld_bin_count <- suppressWarnings(as.integer("$ld_bins"))
maf_boundaries <- c(${maf_edges.join(',')})

fail <- function(message) stop(message, call. = FALSE)
format_bound <- function(value) format(signif(value, 8), scientific = FALSE, trim = TRUE)

if (length(ld_bin_count) != 1L || is.na(ld_bin_count) || ld_bin_count < 1L) {
  fail("ld_bins must be one positive integer")
}
if (length(maf_boundaries) < 2L || any(!is.finite(maf_boundaries))) {
  fail("maf_edges must contain at least two finite numeric boundaries")
}
if (any(diff(maf_boundaries) <= 0)) fail("maf_edges must be strictly increasing")
if (maf_boundaries[1] < 0 || maf_boundaries[length(maf_boundaries)] > 0.5) {
  fail("maf_edges must lie within 0 and 0.5")
}

scores <- read.table(input_file, header = TRUE, check.names = FALSE, stringsAsFactors = FALSE)

required_columns <- c("SNP", "ldscore_SNP")
missing_columns <- setdiff(required_columns, colnames(scores))
if (length(missing_columns) > 0L) {
  fail(paste("LD-score input is missing required columns:", paste(missing_columns, collapse = ", ")))
}
if (!"MAF" %in% colnames(scores) && !"freq" %in% colnames(scores)) {
  fail("LD-score input must contain native freq or MAF")
}
maf <- if ("MAF" %in% colnames(scores)) scores\$MAF else pmin(scores\$freq, 1 - scores\$freq)

ld_boundaries <- as.numeric(quantile(
  scores\$ldscore_SNP,
  probs = seq(0, 1, length.out = ld_bin_count + 1L),
  names = FALSE,
  type = 7
))

manifest_rows <- list()
row_index <- 1L

for (ld_index in seq_len(ld_bin_count)) {
  ld_lower <- ld_boundaries[ld_index]
  ld_upper <- ld_boundaries[ld_index + 1L]
  ld_member <- scores\$ldscore_SNP >= ld_lower & if (ld_index == ld_bin_count) scores\$ldscore_SNP <= ld_upper else scores\$ldscore_SNP < ld_upper

  for (maf_index in seq_len(length(maf_boundaries) - 1L)) {
    maf_lower <- maf_boundaries[maf_index]
    maf_upper <- maf_boundaries[maf_index + 1L]
    maf_member <- maf >= maf_lower & if (maf_index == length(maf_boundaries) - 1L) maf <= maf_upper else maf < maf_upper
    member <- ld_member & maf_member
    predictor_count <- sum(member)
    # Skip empty quantile cells so sparse strata do not abort the run.
    if (predictor_count == 0L) next

    stratum_key <- sprintf("ld%02d_maf%02d", ld_index, maf_index)
    group_filename <- sprintf("%s_snp_group_%s.txt", output_prefix, stratum_key)
    writeLines(scores\$SNP[member], group_filename)

    manifest_rows[[row_index]] <- data.frame(
      model_key = "ldms",
      stratum_key = stratum_key,
      ld_lower = format_bound(ld_lower),
      ld_upper = format_bound(ld_upper),
      maf_lower = format_bound(maf_lower),
      maf_upper = format_bound(maf_upper),
      predictor_count = predictor_count,
      group_filename = group_filename,
      stringsAsFactors = FALSE
    )
    row_index <- row_index + 1L
  }
}

if (length(manifest_rows) == 0L) {
  fail("No non-empty strata produced; check ld_bins and maf_edges.")
}

manifest <- do.call(rbind, manifest_rows)
write.table(manifest, paste0(output_prefix, ".strata.tsv"), sep = "\t", quote = FALSE, row.names = FALSE)

version_lines <- c(
  paste0('"$task.process":'),
  paste0("    r-base: ", as.character(getRversion()))
)
writeLines(version_lines, "versions.yml")
