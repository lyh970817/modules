process CUSTOM_GCTAMERGEGRMPARTS {
    tag "${meta.id}"
    label 'process_single'
    container "${workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container
        ? 'https://community-cr-prod.seqera.io/docker/registry/v2/blobs/sha256/52/52ccce28d2ab928ab862e25aae26314d69c8e38bd41ca9431c67ef05221348aa/data'
        : 'community.wave.seqera.io/library/coreutils_grep_gzip_lbzip2_pruned:838ba80435a629f8'}"

    input:
    tuple val(meta), path(grm_bin_parts), path(grm_n_bin_parts), path(grm_id_parts), val(part_numbers), val(expected_parts)

    output:
    tuple val(meta), path("${prefix}.grm.*"), emit: grm_files
    path "versions.yml", emit: versions, topic: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    prefix = task.ext.prefix ?: "${meta.id}"
    bin_args = grm_bin_parts.collect { file -> "'${file}'" }.join(' ')
    n_bin_args = grm_n_bin_parts.collect { file -> "'${file}'" }.join(' ')
    id_args = grm_id_parts.collect { file -> "'${file}'" }.join(' ')
    part_args = part_numbers.join(' ')
    def helper_script = file("${moduleDir}/templates/gctamergegrmparts.sh").bytes.encodeBase64().toString()
    """
    printf '%s' '${helper_script}' | base64 --decode > gctamergegrmparts.sh
    bash gctamergegrmparts.sh '${expected_parts}' '${prefix}' '${part_args}' "${bin_args}" "${n_bin_args}" "${id_args}" '${task.process}'
    """

    stub:
    prefix = task.ext.prefix ?: "${meta.id}"
    """
    printf '\0\0\0\0' > ${prefix}.grm.bin
    printf '\0\0\0\0' > ${prefix}.grm.N.bin
    printf 'stub\tstub\n' > ${prefix}.grm.id
    printf '"%s":\n    gctamergegrmparts: 1.0.0\n' "${task.process}" > versions.yml
    """
}
