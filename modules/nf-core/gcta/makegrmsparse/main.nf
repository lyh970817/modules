process GCTA_MAKEGRMSPARSE {
    tag "${meta.id}"
    label 'process_medium'

    conda "${moduleDir}/environment.yml"
    container "${workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container
        ? 'https://community-cr-prod.seqera.io/docker/registry/v2/blobs/sha256/46/46b0d05f0daa47561d87d2a9cac5e51edc2c78e26f1bbab439c688386241a274/data'
        : 'community.wave.seqera.io/library/gcta:1.94.1--9bc35dc424fcf6e9'}"

    input:
    tuple val(meta), path(mfile), path(bed_pgen), path(bim_pvar), path(fam_psam)
    val sparse_cutoff

    output:
    tuple val(meta), path("${sparse_prefix}.grm.*"), emit: sparse_grm_files
    tuple val(meta), path("${sparse_prefix}.log"), emit: log
    tuple val("${task.process}"), val("gcta"), eval("gcta --version | sed -En 's/^[*] version v([0-9.]*).*/\\1/p'"), emit: versions_gcta, topic: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    def genotype_files = bed_pgen instanceof List ? bed_pgen : [bed_pgen]
    def genotype_extension = genotype_files[0].name.tokenize('.').last()
    def multi_file_flag = genotype_extension == 'pgen' ? '--mpfile' : '--mbfile'
    def prefix = task.ext.prefix ?: "${meta.id}"
    sparse_prefix = "${prefix}_sp"
    """
    gcta \
        ${multi_file_flag} ${mfile} \
        --make-grm \
        --sparse-cutoff ${sparse_cutoff} \
        --thread-num ${task.cpus} \
        --out ${sparse_prefix} \
        ${args}
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    sparse_prefix = "${prefix}_sp"
    """
    echo -e "0\t0\t1" > ${sparse_prefix}.grm.sp
    echo -e "FID\tIID" > ${sparse_prefix}.grm.id
    echo "GCTA sparse GRM stub" > ${sparse_prefix}.log
    """
}
