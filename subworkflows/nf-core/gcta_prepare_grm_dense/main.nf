include { GCTA_MAKEGRMPART         } from '../../../modules/nf-core/gcta/makegrmpart/main'
include { CUSTOM_GCTAMERGEGRMPARTS } from '../../../modules/nf-core/custom/gctamergegrmparts/main'

workflow GCTA_PREPARE_GRM_DENSE {
    take:
    ch_genotypes // [meta, mfile, bed_pgen, bim_pvar, fam_psam]
    ch_snp_group_file // [meta2, snp_group_file|[]]
    val_n_parts

    main:
    ch_scattered = ch_genotypes
        .combine(val_n_parts)
        .flatMap { meta, mfile, bed_pgen, bim_pvar, fam_psam, n_parts ->
            if (!(n_parts instanceof Integer) || n_parts < 1) {
                throw new IllegalArgumentException('n_parts must be a positive integer')
            }
            (1..n_parts).collect { part ->
                tuple(meta.id, meta, n_parts, part, mfile, bed_pgen, bim_pvar, fam_psam)
            }
        }

    ch_joined = ch_scattered.combine(
        ch_snp_group_file.map { meta2, snp_group_file -> tuple(meta2.id, meta2, snp_group_file) },
        by: 0
    )

    ch_inputs = ch_joined.multiMap { key, meta, n_parts, part, mfile, bed_pgen, bim_pvar, fam_psam, meta2, snp_group_file ->
        genotypes: tuple(meta, n_parts, part, mfile, bed_pgen, bim_pvar, fam_psam)
        snp_group: tuple(meta2, snp_group_file)
    }

    GCTA_MAKEGRMPART(ch_inputs.genotypes, ch_inputs.snp_group)

    ch_gathered = GCTA_MAKEGRMPART.out.grm_files
        .map { meta, grm_parts, n_parts, part -> tuple(meta.id, meta, grm_parts) }
        .groupTuple(by: 0)
        .map { key, metas, file_lists -> tuple(metas.first(), file_lists.flatten()) }

    ch_effective_parts = ch_genotypes
        .map { meta, mfile, bed_pgen, bim_pvar, fam_psam -> meta }
        .combine(val_n_parts)
        .map { meta, n_parts -> tuple(meta, n_parts) }
    CUSTOM_GCTAMERGEGRMPARTS(ch_gathered)

    ch_versions = GCTA_MAKEGRMPART.out.versions_gcta
        .mix(versionsFromYaml(CUSTOM_GCTAMERGEGRMPARTS.out.versions))
        .unique()

    emit:
    grm_files       = CUSTOM_GCTAMERGEGRMPARTS.out.grm_files
    effective_parts = ch_effective_parts
    versions        = ch_versions
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
