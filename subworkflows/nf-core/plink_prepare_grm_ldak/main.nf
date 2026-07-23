include { LDAK_CALCKINS } from '../../../modules/nf-core/ldak/calckins/main'
include { LDAK_FILTER   } from '../../../modules/nf-core/ldak/filter/main'
include { LDAK_SUBGRM   } from '../../../modules/nf-core/ldak/subgrm/main'

workflow PLINK_PREPARE_GRM_LDAK {
    take:
    ch_genotypes
    ch_weights
    val_filter_relatedness

    main:
    if (!(val_filter_relatedness in [true, false])) {
        error("val_filter_relatedness must be a Boolean")
    }

    LDAK_CALCKINS(ch_genotypes, ch_weights)

    ch_unfiltered_grm = LDAK_CALCKINS.out.ldak_grm
    ch_versions = LDAK_CALCKINS.out.versions_ldak6

    if (val_filter_relatedness) {
        LDAK_FILTER(ch_unfiltered_grm)

        ch_subgrm_input = ch_unfiltered_grm
            .join(LDAK_FILTER.out.filtered_list)
            .map { meta, grm_bin, grm_id, grm_details, grm_adjust, keep, _lose ->
                def work_meta = meta + [id: "${meta.id}.unrelated", focal_meta: meta]
                tuple(work_meta, grm_bin, grm_id, grm_details, grm_adjust, keep)
            }

        LDAK_SUBGRM(ch_subgrm_input)

        ch_analysis_grm = LDAK_SUBGRM.out.sub_grm.map { meta, grm_bin, grm_id, grm_details, grm_adjust ->
            tuple(meta.focal_meta, grm_bin, grm_id, grm_details, grm_adjust)
        }
        ch_filtered_list = LDAK_FILTER.out.filtered_list
        ch_maxrel = LDAK_FILTER.out.maxrel
        ch_versions = ch_versions
            .mix(LDAK_FILTER.out.versions_ldak6)
            .mix(LDAK_SUBGRM.out.versions_ldak6)
    }
    else {
        ch_analysis_grm = ch_unfiltered_grm
        ch_filtered_list = channel.empty()
        ch_maxrel = channel.empty()
    }

    emit:
    analysis_grm   = ch_analysis_grm
    unfiltered_grm = ch_unfiltered_grm
    filtered_list  = ch_filtered_list
    maxrel         = ch_maxrel
    versions       = ch_versions
}
