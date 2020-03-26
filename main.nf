/*
 * Copyright (c) 2020 Centre for Genomic Regulation (CRG)
 * and the authors, Jose Espinosa-Carrasco and Paolo Di Tommaso.
 *
 * Licensed to the Apache Software Foundation (ASF) under one
 * or more contributor license agreements.  See the NOTICE file
 * distributed with this work for additional information
 * regarding copyright ownership.  The ASF licenses this file
 * to you under the Apache License, Version 2.0 (the
 * "License"); you may not use this file except in compliance
 * with the License.  You may obtain a copy of the License at
 *
 *   http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing,
 * software distributed under the License is distributed on an
 * "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
 * KIND, either express or implied.  See the License for the
 * specific language governing permissions and limitations
 * under the License.
 */

 /*
 * Proof of concept of benchmark-nf: An automatic benchmarking pipeline implemented with Nextflow
 *
 * Authors:
 * - Jose Espinosa-Carrasco <espinosacarrascoj@gmail.com>
 */

nextflow.preview.dsl = 2

@Grab(group='org.yaml', module='snakeyaml', version='1.5')
import org.yaml.snakeyaml.Yaml

@Grab('com.xlson.groovycsv:groovycsv:1.0')
// @Grab('com.xlson.groovycsv:groovycsv:1.3')// slower download
import static com.xlson.groovycsv.CsvParser.parseCsv

 log.info """\
 N F - B E N C H M A R K
 ===================================
pipeline: ${params.pipeline}
 """

// Include the pipeline of modules if available
pipeline_module = file( "${baseDir}/modules/${params.pipeline}/main.nf")
if( !pipeline_module.exists() ) exit 1, "ERROR: The selected pipeline is not included in nf-benchmark: ${params.pipeline}"
include pipeline from  "${baseDir}/modules/${params.pipeline}/main.nf"

// Pipeline meta-information from the pipeline
yamlPath = "${baseDir}/modules/${params.pipeline}/meta.yml"
csvPathMethods = "${baseDir}/assets/methods2benchmark.csv"
csvPathBenchmarker = "${baseDir}/assets/dataFormat2benchmark.csv"
csvPathReference = "${baseDir}/assets/referenceData.csv"

infoBenchmark = setBenchmark(yamlPath, csvPathMethods)
// println (infoBenchmark) // [benchmarker:bali_score, operation:operation_0492, input_data:data_1233, input_format:format_1929, output_data:data_1384, output_format:format_1984]

ref_data = setReference (infoBenchmark, csvPathBenchmarker, csvPathReference)

include benchmark from "./modules/${infoBenchmark.benchmarker}/main.nf"

println("INFO: Benchmark set to: ${infoBenchmark.benchmarker}")

// ref_data.view()

// Hardcodes testing #del
// aligment BB11001
// params.sequences = "${baseDir}/test/sequences/input/BB11001.fa"
// params.reference = "${baseDir}/test/sequences/reference/BB11001.xml.ref"
// benchmarker = "bali_base"

// Run the workflow
workflow {
    pipeline(ref_data)
    benchmark(pipeline.out)
}

/*
 ************
 * Functions
 ************
 */

/*
 * Function reads a csv file are returns the data inside ready to be use
 */
def readCsv (pathCsv) {
    def fileCsv = new File(pathCsv)
    def data = parseCsv(fileCsv.text, autoDetect:true)

    return data
}

/*
 * Takes the info from the pipeline yml file with the pipeline metadata and sets the corresponding benchmark
 */
// benchmarkInfo currently is a CSV but could become a DBs or something else
def setBenchmark (configYmlFile, benchmarkInfo) {

    def fileYml = new File(configYmlFile)
    def yaml = new Yaml()
    def pipelineConfig = yaml.load(fileYml.text)

    // println("INFO: Selected pipeline name is \"${pipelineConfig.name}\"")
    // println("INFO: Path to yaml pipeline configuration file \"${configYmlFile}\"")
    // println("INFO: Path to CSV benchmark info file \"${benchmarkInfo}\"")

    topic = pipelineConfig.pipeline.tcoffee.edam_topic[0]
    operation = pipelineConfig.pipeline.tcoffee.edam_operation[0]

    input_data = pipelineConfig.input.fasta.edam_data[0][0]
    input_format = pipelineConfig.input.fasta.edam_format[0][0]
    output_data = pipelineConfig.output.alignment.edam_data[0][0]
    output_format = pipelineConfig.output.alignment.edam_format[0][0]

    // println("INFO: Selected pipeline name is: ${pipelineConfig.name}")
    // println("INFO: Selected edam topic is: $topic")
    // println("INFO: Selected edam operation is: $operation")

    // println("INFO: Input data is: $input_data")
    // println("INFO: Input format is: ${input_format}")
    // println("INFO: Output data is: $output_data")
    // println("INFO: Output format is: ${output_format}")

    def fileCsv = new File(benchmarkInfo)
    def csvData = parseCsv(fileCsv.text, autoDetect:true)
    def benchmarkDict = [:]
    def i = 0

    for( row in csvData ) {
        if ( row.edam_operation == operation  &&
             row.edam_input_data == input_data &&
             row.edam_input_format == input_format &&
             row.edam_output_data == output_data &&
             row.edam_output_format == output_format ) {
                i += 1

                benchmarkDict = [ (i) : [ benchmarker: row.benchmarker,
                                          operation: row.edam_operation,
                                          input_data: row.edam_input_data,
                                          input_format: row.edam_input_format,
                                          output_data: row.edam_output_data,
                                          output_format: row.edam_output_format ] ]
        }
    }

    if ( benchmarkDict.size() > 1 ) exit 1, "Error: More than one possible benchmark please refine pipeline description for \"${params.pipeline}\" pipeline"
    if ( benchmarkDict.size() == 0 ) exit 1, "Error: The selected pipeline  \"${params.pipeline}\" is not included in nf-benchmark"

    return benchmarkDict [ 1 ]
}

/*
 * Functions returns the test and reference data to be used given the benchmarker
 */
def setReference (benchmarkInfo, benchmarkerCsv, refDataCsv) {

    def dataFormat2benchmark = readCsv(benchmarkerCsv)
    def refData = readCsv(refDataCsv)

    def i = 0
    def refDataDict = [:]

    for( row in dataFormat2benchmark ) {
        if ( row.edam_test_format == benchmarkInfo.input_format  &&
             row.edam_ref_format  == benchmarkInfo.output_format &&
             row.benchmarker      == benchmarkInfo.benchmarker ) {
                i += 1

                refDataDict = [ (i) : [ benchmarker: row.benchmarker,
                                        test_format: row.edam_test_format,
                                        ref_format : row.edam_ref_format ] ]
        }
    }

    if ( refDataDict.size() > 1 ) exit 1, "Error: More than one possible benchmarker please refine pipeline description for \"${params.pipeline}\" pipeline"
    if ( refDataDict.size() == 0 ) exit 1, "Error: The selected pipeline  \"${params.pipeline}\" is not included in nf-benchmark"

    refDataHit = refDataDict[ 1 ]

    Channel
        .fromPath( refDataCsv )
        .splitCsv(header: true)
        .filter { row ->
            row.benchmarker == refDataHit.benchmarker
        }
        .map { [ it.id, //it.edam_test_data,
                 file("${baseDir}/reference_dataset/" + it.id + it.test_data_format),
                 file("${baseDir}/reference_dataset/" + it.id + it.ref_data_format) ]
        }
        .set { reference_data }

    return reference_data
}
