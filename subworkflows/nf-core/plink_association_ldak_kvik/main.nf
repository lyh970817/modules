include { LDAK_THINCOMMON } from '../../../modules/nf-core/ldak/thincommon/main'
include { LDAK_KVIKSTEP1  } from '../../../modules/nf-core/ldak/kvikstep1/main'
include { LDAK_KVIKSTEP2  } from '../../../modules/nf-core/ldak/kvikstep2/main'

workflow PLINK_ASSOCIATION_LDAK_KVIK {
    take:
    ch_step1_genotypes
    ch_genotype_shards
    ch_pheno
    ch_qcovar
    ch_covar
    ch_step1_extract
    ch_keep
    subset_policy

    main:
    if (!['all', 'thin_common', 'provided'].contains(subset_policy)) {
        error("LDAK-KVIK subset policy must be one of: all, thin_common, provided")
    }

    ch_step1_genotypes_value = ch_step1_genotypes.first()
    ch_pheno_value = ch_pheno.first()
    ch_qcovar_value = ch_qcovar.first()
    ch_covar_value = ch_covar.first()
    ch_keep_value = ch_keep.first()
    ch_extract_value = ch_step1_extract.first()

    if (subset_policy == 'thin_common') {
        ch_valid_thin_genotypes = ch_step1_genotypes_value
            .combine(ch_extract_value)
            .map { meta, bed, bim, fam, _meta5, extract_file ->
                if (extract_file) {
                    error("thin_common policy requires an absent provided extract file")
                }
                tuple(meta, bed, bim, fam)
            }
        LDAK_THINCOMMON(ch_valid_thin_genotypes)
        ch_selected_extract = LDAK_THINCOMMON.out.predictors
            .combine(ch_step1_genotypes_value)
            .map { meta5, extract_file, _meta, _bed, bim, _fam ->
                def selected = extract_file.readLines().findAll { line -> line.trim() }.collect { line -> line.tokenize()[0] } as Set
                def chromosomes = bim.readLines().findAll { line -> selected.contains(line.tokenize()[1]) }.collect { line -> line.tokenize()[0] }.toSet()
                if (chromosomes.size() < 2) {
                    error("LDAK-KVIK Step 1 predictor subset must span at least two chromosomes")
                }
                tuple(meta5, extract_file)
            }
    }
    else if (subset_policy == 'provided') {
        ch_selected_extract = ch_step1_genotypes_value
            .combine(ch_extract_value)
            .map { _meta, _bed, bim, _fam, meta5, extract_file ->
                if (!extract_file) {
                    error("provided policy requires a predictor extract file")
                }
                def selected = extract_file.readLines().findAll { line -> line.trim() }.collect { line -> line.tokenize()[0] } as Set
                def chromosomes = bim.readLines().findAll { line -> selected.contains(line.tokenize()[1]) }.collect { line -> line.tokenize()[0] }.toSet()
                if (chromosomes.size() < 2) {
                    error("LDAK-KVIK Step 1 predictor subset must span at least two chromosomes")
                }
                tuple(meta5, extract_file)
            }
    }
    else {
        ch_selected_extract = ch_extract_value.map { meta5, extract_file ->
            if (extract_file) {
                error("all policy requires an absent predictor extract file")
            }
            tuple(meta5, [])
        }
    }

    LDAK_KVIKSTEP1(
        ch_step1_genotypes_value,
        ch_pheno_value,
        ch_qcovar_value,
        ch_covar_value,
        ch_selected_extract.first(),
    )

    ch_predictions_value = LDAK_KVIKSTEP1.out.predictions.first()

    LDAK_KVIKSTEP2(
        ch_genotype_shards,
        ch_pheno_value.map { meta, phenotype_file, _is_binary -> tuple(meta, phenotype_file) },
        ch_predictions_value,
        ch_qcovar_value,
        ch_covar_value,
        ch_keep_value,
    )

    ch_logs = LDAK_KVIKSTEP1.out.log.mix(LDAK_KVIKSTEP2.out.log)
    ch_versions = LDAK_KVIKSTEP1.out.versions_ldak6.mix(LDAK_KVIKSTEP2.out.versions_ldak6)
    if (subset_policy == 'thin_common') {
        ch_versions = ch_versions.mix(LDAK_THINCOMMON.out.versions_ldak6)
    }
    ch_versions = ch_versions.unique()

    emit:
    results     = LDAK_KVIKSTEP2.out.results
    summaries   = LDAK_KVIKSTEP2.out.summaries
    pvalues     = LDAK_KVIKSTEP2.out.pvalues
    predictions = LDAK_KVIKSTEP1.out.predictions
    logs        = ch_logs
    versions    = ch_versions
}
