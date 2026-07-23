//
// Fit REGENIE Step 1 whole-genome regression models from PLINK-format genotype files
//

include { REGENIE_STEP1   } from '../../../modules/nf-core/regenie/step1/main'
include { REGENIE_SPLITL0 } from '../../../modules/nf-core/regenie/splitl0/main'
include { REGENIE_RUNL0   } from '../../../modules/nf-core/regenie/runl0/main'
include { REGENIE_RUNL1   } from '../../../modules/nf-core/regenie/runl1/main'

workflow PLINK_FIT_REGENIE {
    take:
    ch_genotypes // channel: [ val(meta), path(genotype_file), path(variant_file), path(sample_file) ]
    ch_pheno // channel: [ val(meta), path(pheno) ]
    ch_covar // channel: [ val(meta), path(covar) ], use [] when absent
    val_bsize // value: required positive Step 1 block size
    val_step1_mode // value: 'standard' or 'chunked'
    val_n_l0_jobs // value: number of L0 jobs for chunked mode, use [] for standard mode

    main:
    if (!['standard', 'chunked'].contains(val_step1_mode)) {
        error("PLINK_FIT_REGENIE: val_step1_mode must be 'standard' or 'chunked', got '${val_step1_mode}'")
    }
    bsize = require_positive_integer(
        val_bsize,
        "PLINK_FIT_REGENIE: val_bsize must be a positive integer",
    )

    if (val_step1_mode == 'standard') {
        if (!is_empty_value(val_n_l0_jobs)) {
            error("PLINK_FIT_REGENIE: val_n_l0_jobs must be empty when val_step1_mode is 'standard'")
        }

        REGENIE_STEP1(
            ch_genotypes,
            ch_pheno,
            ch_covar,
            bsize,
        )

        ch_predictions = REGENIE_STEP1.out.predictions
        ch_loco = REGENIE_STEP1.out.loco
        ch_log = REGENIE_STEP1.out.log
        ch_versions = REGENIE_STEP1.out.versions_regenie
    }
    else {
        n_l0_jobs = require_positive_integer(
            val_n_l0_jobs,
            "PLINK_FIT_REGENIE: val_n_l0_jobs must be a positive integer when val_step1_mode is 'chunked'",
        )

        REGENIE_SPLITL0(
            ch_genotypes,
            ch_pheno,
            ch_covar,
            bsize,
            n_l0_jobs,
        )

        ch_validated_split = REGENIE_SPLITL0.out.master
            .join(REGENIE_SPLITL0.out.snplists, by: [0])
            .map { meta, master, snplists ->
                def snplist_files = snplists instanceof List ? snplists : [snplists]
                if (!snplist_files) {
                    error("PLINK_FIT_REGENIE: splitl0 emitted no native jobs for '${meta.id}'")
                }
                def jobs = snplist_files
                    .collect { snplist ->
                        def job_match = snplist.name =~ /_job(\d+)\.snplist$/
                        if (!job_match) {
                            error("PLINK_FIT_REGENIE: cannot derive a native job key from '${snplist.name}'")
                        }
                        [job_number: job_match[0][1] as Integer, snplist: snplist]
                    }
                    .sort { job -> job.job_number }
                def job_numbers = jobs*.job_number
                if (job_numbers.unique().size() != job_numbers.size()) {
                    error("PLINK_FIT_REGENIE: splitl0 emitted duplicate native job keys for '${meta.id}': ${job_numbers}")
                }
                def master_job_prefixes = master.text
                    .readLines()
                    .collect { line -> line.tokenize() }
                    .findAll { fields -> fields && fields[0] ==~ /.*_job\d+$/ }
                    .collect { fields -> java.nio.file.Paths.get(fields[0]).fileName.toString() }
                    .toSet()
                def emitted_job_prefixes = snplist_files.collect { snplist -> snplist.baseName }.toSet()
                if (master_job_prefixes != emitted_job_prefixes) {
                    error("PLINK_FIT_REGENIE: native master/SNP-list jobs disagree for '${meta.id}'")
                }
                [meta, master, snplist_files, jobs]
            }

        ch_l0_jobs = ch_validated_split.flatMap { meta, master, _snplists, jobs ->
            jobs.collect { job -> [meta, master, job.snplist, job.job_number] }
        }

        ch_pheno_by_id = ch_pheno.map { meta, pheno -> [meta.id, pheno] }
        ch_covar_by_id = ch_covar.map { meta, covar -> [meta.id, covar] }

        ch_runl0_inputs = ch_genotypes
            .combine(ch_l0_jobs, by: [0])
            .map { meta, genotype, variant, sample, master, snplist, job_number ->
                [meta.id, meta, genotype, variant, sample, master, snplist, job_number]
            }
            .combine(ch_pheno_by_id, by: [0])
            .combine(ch_covar_by_id, by: [0])

        REGENIE_RUNL0(
            ch_runl0_inputs.map { values ->
                [values[1], values[2], values[3], values[4]]
            },
            ch_runl0_inputs.map { values ->
                [values[1], values[5], values[6], values[7]]
            },
            ch_runl0_inputs.map { values ->
                [values[1], values[8]]
            },
            ch_runl0_inputs.map { values ->
                [values[1], values[9]]
            },
            bsize,
        )

        ch_l0_predictions = REGENIE_RUNL0.out.l0_predictions
            .groupTuple(by: [0])
            .map { meta, l0_predictions ->
                [meta, l0_predictions.flatten()]
            }

        ch_runl1_split_inputs = ch_validated_split
            .map { meta, master, snplists, _jobs -> [meta, master, snplists] }
            .join(ch_l0_predictions, by: [0])

        ch_runl1_inputs = ch_genotypes
            .combine(ch_runl1_split_inputs, by: [0])
            .map { meta, genotype, variant, sample, master, snplists, predictions ->
                [meta.id, meta, genotype, variant, sample, master, snplists, predictions]
            }
            .combine(ch_pheno_by_id, by: [0])
            .combine(ch_covar_by_id, by: [0])

        REGENIE_RUNL1(
            ch_runl1_inputs.map { values ->
                [values[1], values[2], values[3], values[4]]
            },
            ch_runl1_inputs.map { values ->
                [values[1], values[5], values[6], values[7]]
            },
            ch_runl1_inputs.map { values ->
                [values[1], values[8]]
            },
            ch_runl1_inputs.map { values ->
                [values[1], values[9]]
            },
            bsize,
        )

        ch_predictions = REGENIE_RUNL1.out.predictions
        ch_loco = REGENIE_RUNL1.out.loco
        ch_log = REGENIE_SPLITL0.out.log.mix(REGENIE_RUNL0.out.log, REGENIE_RUNL1.out.log)
        ch_versions = REGENIE_SPLITL0.out.versions_regenie.mix(REGENIE_RUNL0.out.versions_regenie, REGENIE_RUNL1.out.versions_regenie)
    }

    emit:
    predictions = ch_predictions
    loco        = ch_loco
    logs        = ch_log
    versions    = ch_versions
}

def is_empty_value(value) {
    value == null || value == [] || value == ''
}

def require_positive_integer(value, message) {
    try {
        def integer_value = value as Integer
        if (integer_value < 1) {
            error(message)
        }
        return integer_value
    }
    catch (_ignored) {
        error(message)
    }
}
