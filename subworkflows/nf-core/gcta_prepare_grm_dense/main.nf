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
        .map { meta, grm_parts, n_parts, part -> tuple(meta.id, meta, grm_parts, n_parts, part) }
        .groupTuple(by: 0)
        .map { key, metas, file_lists, expected_values, returned_parts ->
            def meta = metas.first()
            def expected = expected_values.first() as Integer
            def parts = returned_parts.collect { it as Integer }.sort()
            if (metas.any { it != meta } || expected_values.any { it as Integer != expected }) {
                throw new IllegalStateException("Inconsistent gathered identity for ${key}")
            }
            if (parts != (1..expected).toList()) {
                throw new IllegalStateException("Returned part keys for ${key} were ${parts}, expected 1..${expected}")
            }
            def files = file_lists.flatten()
            tuple(
                meta,
                files.findAll { file -> file.name.endsWith('.grm.bin') && !file.name.endsWith('.N.bin') },
                files.findAll { file -> file.name.endsWith('.grm.N.bin') },
                files.findAll { file -> file.name.endsWith('.grm.id') },
                parts,
                expected,
            )
        }

    ch_effective_parts = ch_gathered.map { meta, bins, n_bins, ids, parts, expected -> tuple(meta, expected) }
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
