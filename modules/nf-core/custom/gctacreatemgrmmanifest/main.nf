process CUSTOM_GCTACREATEMGRMMANIFEST {
    tag "${meta.id}"
    label 'process_single'

    conda "${moduleDir}/environment.yml"
    container "${workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container
        ? 'https://community-cr-prod.seqera.io/docker/registry/v2/blobs/sha256/52/52ccce28d2ab928ab862e25aae26314d69c8e38bd41ca9431c67ef05221348aa/data'
        : 'community.wave.seqera.io/library/coreutils_grep_gzip_lbzip2_pruned:838ba80435a629f8'}"

    input:
    tuple val(meta), path(grm_files)

    output:
    tuple val(meta), path("${prefix}.mgrm"), path(grm_files), emit: mgrm_bundle
    path "versions.yml", emit: versions, topic: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    prefix = task.ext.prefix ?: "${meta.id}"
    template('gctacreatemgrmmanifest.sh')

    stub:
    prefix = task.ext.prefix ?: "${meta.id}"
    """
    for grm_id in *.grm.id; do
        echo "\${grm_id%.grm.id}"
    done | sort -V > ${prefix}.mgrm

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        coreutils: 9.5
    END_VERSIONS
    """
}
