process CUSTOM_GCTACREATEMGRMMANIFEST {
    tag "${meta.id}"
    label 'process_low'
    container "${workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container
        ? 'docker://quay.io/bioconda/base-glibc-busybox-bash:3.1'
        : 'quay.io/bioconda/base-glibc-busybox-bash:3.1'}"

    input:
    tuple val(meta), path(grm_files), val(grm_order)

    output:
    tuple val(meta), path("${prefix}.mgrm"), path(grm_files), emit: mgrm_bundle
    path "versions.yml", emit: versions, topic: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    prefix = task.ext.prefix ?: "${meta.id}"
    order_args = grm_order.collect { value -> "'${value.toString().replace("'", "'\"'\"'")}'" }.join(' ')
    file_args = grm_files.collect { file -> "'${file.name.toString().replace("'", "'\"'\"'")}'" }.join(' ')
    template('gctacreatemgrmmanifest.sh')

    stub:
    prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}.mgrm

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        custom_gctacreatemgrmmanifest: 1.0.0
    END_VERSIONS
    """
}
