include { FIND_THRESHOLD as FIND_CLONAL_THRESHOLD } from '../../modules/local/enchantr/find_threshold'
include { FIND_THRESHOLD as REPORT_THRESHOLD } from '../../modules/local/enchantr/find_threshold'
include { CLONAL_ASSIGNMENT } from '../../modules/local/enchantr/clonal_assignment'
include { REPERTOIRE_ANALYSIS} from '../../modules/local/enchantr/repertoire_analysis'
include { DOWSER_LINEAGES } from '../../modules/local/enchantr/dowser_lineages'

workflow CLONAL_ANALYSIS {
    take:
    ch_repertoire_reference
    ch_logo

    main:
    ch_versions = Channel.empty()
    ch_logs = Channel.empty()

    if (params.clonal_threshold == "auto") {

        ch_find_threshold = ch_repertoire_reference.map{ it -> it[1] }
                                        .collect()
        ch_find_threshold_samplesheet =  ch_find_threshold
                        .flatten()
                        .map{ it -> it.getName().toString() }
                        .collectFile(name: 'find_threshold_samplesheet.txt', newLine: true)

        FIND_CLONAL_THRESHOLD (
            ch_find_threshold,
            ch_logo,
            ch_find_threshold_samplesheet
        )
        def ch_threshold = FIND_CLONAL_THRESHOLD.out.mean_threshold
        ch_versions = ch_versions.mix(FIND_CLONAL_THRESHOLD.out.versions)

        // Collect raw threshold values into a single list so we can distinguish
        // between (A) no values at all (likely upstream failure), and
        // (B) values present but all invalid thresholds ('' / 'NA' / 'NaN').
        def raw_list = ch_threshold
            .splitText( limit:1 ) { it.trim().toString() }
            .map { it -> it.trim() }
            .collect()

        // Process the collected list to identify when no valid thresholds were found
        clone_threshold = raw_list
            .map { list ->
                if (!list || list.size() == 0) {
                    // upstream produced nothing — do not print a message here
                    return []
                }

                def valid = list.findAll { it != '' && it != 'NA' && it != 'NaN' }
                if (valid.size() == 0) {
                    // The automatic threshold finder returned values but all were
                    // NA, NaN or empty strings - ask the user to set a manual value.
                    error "Automatic clone_threshold detection failed. Consider setting --clonal_threshold manually."
                }

                return valid
            }
            .flatten()

    } else {
        clone_threshold = params.clonal_threshold

        ch_find_threshold = ch_repertoire_reference.map{ it -> it[1] }
                                        .collect()
        ch_find_threshold_samplesheet =  ch_find_threshold
                        .flatten()
                        .map{ it -> it.getName().toString() }
                        .collectFile(name: 'find_threshold_samplesheet.txt', newLine: true)

        if (!params.skip_report_threshold){
            REPORT_THRESHOLD (
                ch_find_threshold,
                ch_logo,
                ch_find_threshold_samplesheet
            )
            ch_versions = ch_versions.mix(REPORT_THRESHOLD.out.versions)
        }
    }

    // merge all repertoires by cloneby metadata field
    ch_repertoire_reference.map{ it -> [ it[0]."${params.cloneby}",
                                it[0].id,
                                it[0].sample_id,
                                it[0].subject_id,
                                it[0].species,
                                it[0].single_cell,
                                it[0].locus,
                                it[1],
                                it[2] ] }
                .groupTuple()
                .map{ get_meta_tabs(it) }
                .set{ ch_repertoire_grouped }

    ch_repertoire_grouped.dump(tag: "ch_repertoire_grouped")

    CLONAL_ASSIGNMENT(
        ch_repertoire_grouped,
        clone_threshold.collect(),
        []
    )

    ch_versions = ch_versions.mix(CLONAL_ASSIGNMENT.out.versions)

    // prepare ch for define clones all samples report
    CLONAL_ASSIGNMENT.out.tab
            .map { it -> it[1]}
            .collect()
            .map { it -> [ [id:'all_reps'], it ] }
            .set{ch_all_repertoires_cloned}

    ch_all_repertoires_cloned.dump(tag: "ch_all_repertoires_cloned")

    if (!params.skip_all_clones_report){

        ch_all_repertoires_cloned_samplesheet = ch_all_repertoires_cloned.map{ it -> it[1] }
                                        .collect()
                                        .flatten()
                                        .map{ it -> it.getName().toString() }
                                        .collectFile(name: 'all_repertoires_cloned_samplesheet.txt', newLine: true)

        REPERTOIRE_ANALYSIS(
            ch_all_repertoires_cloned,
            ch_all_repertoires_cloned_samplesheet
        )
        ch_versions = ch_versions.mix(REPERTOIRE_ANALYSIS.out.versions)
    }

    if (params.lineage_trees){
        DOWSER_LINEAGES(
            CLONAL_ASSIGNMENT.out.tab
        )
        ch_versions = ch_versions.mix(DOWSER_LINEAGES.out.versions)
    }

    emit:
    repertoire = REPERTOIRE_ANALYSIS.out.tab
    versions = ch_versions
    logs = ch_logs
}

// Function to map
def get_meta_tabs(arr) {
    if (arr[3].unique().size() > 1) {
            error "Multiple subject_id found for ${arr[0]} (${arr[3].join(', ')}). Please check your input parameters and ensure that all samples with the same 'cloneby' value have the same 'subject_id' value."
    }

    def meta = [:]
    meta.id                 = [arr[0]].unique().join("")
    meta.sample_id          = arr[2].flatten()
    meta.subject_id         = arr[3].unique().join("")
    meta.species            = arr[4].unique().join("")
    meta.single_cell        = arr[5].unique().join("")
    meta.locus              = arr[6].unique().join("")

    def array = []

        array = [ meta, arr[7].flatten(), arr[8].unique() ]
        if (arr[8].size() > 1) {
            error "Multiple reference fasta files found for ${meta.id}. Please check your input parameters and ensure that all samples with the same ${params.genotypeby} value (parameter 'genotype_by') have the same ${params.cloneby} value (parameter 'clone_by')."
        }
    return array
}
