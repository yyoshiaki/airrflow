def asString (args) {
    def s = ""
    def value = ""
    if (args.size()>0) {
        if (args[0] != 'none') {
            for (param in args.keySet().sort()){
                value = args[param].toString()
                if (!value.isNumber()) {
                    value = "'"+value+"'"
                }
                s = s + ",'"+param+"'="+value
            }
        }
    }
    return s
}

process REPERTOIRE_ANALYSIS {
    tag "${meta.id}"

    label 'process_long_parallelized'
    label 'immcantation'
    label 'immcantation_container'

    if (workflow.profile.tokenize(',').intersect(['conda', 'mamba']).size() >= 1) {
        error "nf-core/airrflow currently does not support Conda. Please use a container profile instead."
    }
    container "docker.io/immcantation/airrflow:5.0.0dev"

    input:
    tuple val(meta), path(tabs) // meta, sequence tsv in AIRR format
    path repertoires_samplesheet

    output:
    tuple val(meta), path("*/*/*repertoire-pass.tsv"), emit: tab // sequence tsv in AIRR format
    path("*/*_command_log.txt"), emit: logs //process logs
    path "*_report"
    path "versions.yml", emit: versions


    script:
    def args = task.ext.args ? asString(task.ext.args) : ''
    def input = ""
    if (repertoires_samplesheet) {
        input = repertoires_samplesheet
    } else {
        input = tabs.join(',')
    }
    """
    Rscript -e "enchantr::enchantr_report('repertoire_analysis', \\
                                        report_params=list('input'='${input}', \\
                                        'cloneby'='${params.cloneby}', \\
                                        'outputby'='${params.cloneby}', \\
                                        'outdir'=getwd(), \\
                                        'nproc'=${task.cpus}, \\
                                        'log'='${meta.id}_clone_command_log' ${args}))"

    cp -r enchantr repertoire_analysis_report && rm -rf enchantr

    echo "${task.process}": > versions.yml
    Rscript -e "cat(paste0('  enchantr: ',packageVersion('enchantr'),'\n'))" >> versions.yml
    """
}
