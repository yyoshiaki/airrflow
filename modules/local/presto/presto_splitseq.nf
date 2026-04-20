process PRESTO_SPLITSEQ {
    tag "$meta.id"
    label "process_low"
    label 'immcantation'

    conda "bioconda::presto=0.7.8"
    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://community-cr-prod.seqera.io/docker/registry/v2/blobs/sha256/10/103c49b8078f59cf606995618535a988c1055c13f06d060bdb5f642c6b217fc6/data' :
        'biocontainers/presto:0.7.8--pyhdfd78af_0' }"

    input:
    tuple val(meta), path(reads)

    output:
    tuple val(meta), path("${meta.id}_atleast-*.fasta"), emit: fasta
    path("*_command_log.txt"), emit: logs
    path "versions.yml" , emit: versions

    script:
    def args = task.ext.args ?: ''
    """
    SplitSeq.py group -s $reads \\
    $args \\
    --outname ${meta.id} \\
    --fasta > ${meta.id}_command_log.txt

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        presto: \$( SplitSeq.py --version | awk -F' '  '{print \$2}' )
    END_VERSIONS
    """
}
