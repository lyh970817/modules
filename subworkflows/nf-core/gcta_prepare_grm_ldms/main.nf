include { GCTA_CALCULATELDSCORES        } from '../../../modules/nf-core/gcta/calculateldscores/main'
include { CUSTOM_GCTASTRATIFYLDSCORES   } from '../../../modules/nf-core/custom/gctastratifyldscores/main'
include { GCTA_MAKEGRMPART              } from '../../../modules/nf-core/gcta/makegrmpart/main'
include { CUSTOM_GCTAMERGEGRMPARTS      } from '../../../modules/nf-core/custom/gctamergegrmparts/main'
include { CUSTOM_GCTACREATEMGRMMANIFEST } from '../../../modules/nf-core/custom/gctacreatemgrmmanifest/main'

workflow GCTA_PREPARE_GRM_LDMS {
    take:
    ch_genotypes // [meta, mfile, bed, bim, fam]
    val_ld_score_region_kb
    val_ld_bins
    val_maf_edges
    val_n_parts

    main:
    ch_ld_inputs = ch_genotypes.map { meta, mfile, bed, bim, fam -> tuple(meta, bed, bim, fam) }
    GCTA_CALCULATELDSCORES(ch_ld_inputs, val_ld_score_region_kb)

    ch_stratify_inputs = GCTA_CALCULATELDSCORES.out.ld_scores
        .combine(val_ld_bins)
        .combine(val_maf_edges.map { edges -> [value: edges] })
        .map { meta, ld_scores, ld_bins, wrapped_edges -> tuple(meta, ld_scores, ld_bins, wrapped_edges.value) }
    CUSTOM_GCTASTRATIFYLDSCORES(ch_stratify_inputs)

    ch_strata = CUSTOM_GCTASTRATIFYLDSCORES.out.strata_manifest.flatMap { meta, manifest ->
        def header = manifest.readLines().first().split('\t') as List
        manifest
            .readLines()
            .drop(1)
            .collect { line ->
                def values = line.split('\t', -1) as List
                def row = [header, values].transpose().collectEntries()
                tuple(meta, row.model_key, row.stratum_key, row)
            }
    }

    ch_group_records = CUSTOM_GCTASTRATIFYLDSCORES.out.snp_group_files.flatMap { meta, files ->
        def file_list = files instanceof List ? files : [files]
        file_list.collect { group_file ->
            def match = group_file.name =~ /_snp_group_(ld[0-9]+_maf[0-9]+)[.]txt$/
            if (!match.find()) {
                throw new IllegalStateException("Unrecognised SNP-group filename: ${group_file.name}")
            }
            tuple(meta.id, meta, 'ldms', match.group(1), group_file)
        }
    }

    ch_jobs = ch_group_records
        .combine(
            ch_genotypes.map { meta, mfile, bed, bim, fam -> tuple(meta.id, mfile, bed, bim, fam) },
            by: 0
        )
        .combine(val_n_parts)
        .flatMap { focal_key, meta, model_key, stratum_key, group_file, mfile, bed, bim, fam, n_parts ->
            if (!(n_parts instanceof Integer) || n_parts < 1) {
                throw new IllegalArgumentException('n_parts must be a positive integer')
            }
            def work_meta = meta + [
                id: "${meta.id}.${model_key}.${stratum_key}",
                focal_meta: meta,
                model_key: model_key,
                stratum_key: stratum_key,
            ]
            (1..n_parts).collect { part ->
                tuple(work_meta, n_parts, part, mfile, bed, bim, fam, group_file)
            }
        }

    ch_make_inputs = ch_jobs.multiMap { work_meta, n_parts, part, mfile, bed, bim, fam, group_file ->
        genotypes: tuple(work_meta, n_parts, part, mfile, bed, bim, fam)
        snp_group: tuple(work_meta, group_file)
    }
    GCTA_MAKEGRMPART(ch_make_inputs.genotypes, ch_make_inputs.snp_group)

    ch_gathered_parts = GCTA_MAKEGRMPART.out.grm_files
        .map { meta, files, n_parts, part -> tuple("${meta.focal_meta.id}|${meta.model_key}|${meta.stratum_key}", meta, files) }
        .groupTuple(by: 0)
        .map { key, metas, file_lists -> tuple(metas.first(), file_lists.flatten()) }
    CUSTOM_GCTAMERGEGRMPARTS(ch_gathered_parts)

    ch_manifest_inputs = CUSTOM_GCTAMERGEGRMPARTS.out.grm_files
        .map { meta, files -> tuple(meta.focal_meta.id, meta.focal_meta, files) }
        .groupTuple(by: 0)
        .map { focal_key, focal_metas, file_lists -> tuple(focal_metas.first(), file_lists.flatten()) }
    CUSTOM_GCTACREATEMGRMMANIFEST(ch_manifest_inputs)

    ch_versions = GCTA_CALCULATELDSCORES.out.versions_gcta
        .mix(versionsFromYaml(CUSTOM_GCTASTRATIFYLDSCORES.out.versions))
        .mix(GCTA_MAKEGRMPART.out.versions_gcta)
        .mix(versionsFromYaml(CUSTOM_GCTAMERGEGRMPARTS.out.versions))
        .mix(versionsFromYaml(CUSTOM_GCTACREATEMGRMMANIFEST.out.versions))
        .unique()

    emit:
    mgrm_bundle = CUSTOM_GCTACREATEMGRMMANIFEST.out.mgrm_bundle
    strata      = ch_strata
    versions    = ch_versions
}

def versionsFromYaml(channel) {
    channel.flatMap { versions_file ->
        def lines = versions_file.readLines().findAll { line -> line?.trim() }
        if (lines.size() < 2) {
            throw new IllegalStateException("Invalid versions file: ${versions_file}")
        }
        def process_name = lines.first().trim().replaceAll(/^['"]|['"]?:$/, '')
        lines
            .drop(1)
            .collect { line ->
                def fields = line.trim().split(':', 2)
                if (fields.size() != 2) {
                    throw new IllegalStateException("Invalid versions entry in ${versions_file}: ${line}")
                }
                tuple(process_name, fields[0].trim(), fields[1].trim())
            }
    }
}
