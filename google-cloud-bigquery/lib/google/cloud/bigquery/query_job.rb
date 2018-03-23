# Copyright 2015 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     https://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.


require "google/cloud/bigquery/service"
require "google/cloud/bigquery/data"
require "google/cloud/bigquery/encryption_configuration"
require "google/apis/bigquery_v2"

module Google
  module Cloud
    module Bigquery
      ##
      # # QueryJob
      #
      # A {Job} subclass representing a query operation that may be performed
      # on a {Table}. A QueryJob instance is created when you call
      # {Project#query_job}, {Dataset#query_job}.
      #
      # @see https://cloud.google.com/bigquery/querying-data Querying Data
      # @see https://cloud.google.com/bigquery/docs/reference/v2/jobs Jobs API
      #   reference
      #
      # @example
      #   require "google/cloud/bigquery"
      #
      #   bigquery = Google::Cloud::Bigquery.new
      #
      #   job = bigquery.query_job "SELECT COUNT(word) as count FROM " \
      #                            "`bigquery-public-data.samples.shakespeare`"
      #
      #   job.wait_until_done!
      #
      #   if job.failed?
      #     puts job.error
      #   else
      #     puts job.data.first
      #   end
      #
      class QueryJob < Job
        ##
        # Checks if the priority for the query is `BATCH`.
        #
        # @return [Boolean] `true` when the priority is `BATCH`, `false`
        #   otherwise.
        #
        def batch?
          val = @gapi.configuration.query.priority
          val == "BATCH"
        end

        ##
        # Checks if the priority for the query is `INTERACTIVE`.
        #
        # @return [Boolean] `true` when the priority is `INTERACTIVE`, `false`
        #   otherwise.
        #
        def interactive?
          val = @gapi.configuration.query.priority
          return true if val.nil?
          val == "INTERACTIVE"
        end

        ##
        # Checks if the the query job allows arbitrarily large results at a
        # slight cost to performance.
        #
        # @return [Boolean] `true` when large results are allowed, `false`
        #   otherwise.
        #
        def large_results?
          val = @gapi.configuration.query.allow_large_results
          return false if val.nil?
          val
        end

        ##
        # Checks if the query job looks for an existing result in the query
        # cache. For more information, see [Query
        # Caching](https://cloud.google.com/bigquery/querying-data#querycaching).
        #
        # @return [Boolean] `true` when the query cache will be used, `false`
        #   otherwise.
        #
        def cache?
          val = @gapi.configuration.query.use_query_cache
          return false if val.nil?
          val
        end

        ##
        # Checks if the query job flattens nested and repeated fields in the
        # query results. The default is `true`. If the value is `false`,
        # #large_results? should return `true`.
        #
        # @return [Boolean] `true` when the job flattens results, `false`
        #   otherwise.
        #
        def flatten?
          val = @gapi.configuration.query.flatten_results
          return true if val.nil?
          val
        end

        ##
        # Limits the billing tier for this job. Queries that have resource usage
        # beyond this tier will raise (without incurring a charge). If
        # unspecified, this will be set to your project default. For more
        # information, see [High-Compute
        # queries](https://cloud.google.com/bigquery/pricing#high-compute).
        #
        # @return [Integer, nil] The tier number, or `nil` for the project
        #   default.
        #
        def maximum_billing_tier
          @gapi.configuration.query.maximum_billing_tier
        end

        ##
        # Limits the bytes billed for this job. Queries that will have bytes
        # billed beyond this limit will raise (without incurring a charge). If
        # `nil`, this will be set to your project default.
        #
        # @return [Integer, nil] The number of bytes, or `nil` for the project
        #   default.
        #
        def maximum_bytes_billed
          Integer @gapi.configuration.query.maximum_bytes_billed
        rescue StandardError
          nil
        end

        ##
        # Checks if the query results are from the query cache.
        #
        # @return [Boolean] `true` when the job statistics indicate a cache hit,
        #   `false` otherwise.
        #
        def cache_hit?
          @gapi.statistics.query.cache_hit
        end

        ##
        # The number of bytes processed by the query.
        #
        # @return [Integer] Total bytes processed for the job.
        #
        def bytes_processed
          Integer @gapi.statistics.query.total_bytes_processed
        rescue StandardError
          nil
        end

        ##
        # Describes the execution plan for the query.
        #
        # @return [Array<Google::Cloud::Bigquery::QueryJob::Stage>] An array
        #   containing the stages of the execution plan.
        #
        # @example
        #   require "google/cloud/bigquery"
        #
        #   bigquery = Google::Cloud::Bigquery.new
        #
        #   sql = "SELECT word FROM `bigquery-public-data.samples.shakespeare`"
        #   job = bigquery.query_job sql
        #
        #   job.wait_until_done!
        #
        #   stages = job.query_plan
        #   stages.each do |stage|
        #     puts stage.name
        #     stage.steps.each do |step|
        #       puts step.kind
        #       puts step.substeps.inspect
        #     end
        #   end
        #
        def query_plan
          return nil unless @gapi.statistics.query.query_plan
          Array(@gapi.statistics.query.query_plan).map do |stage|
            Stage.from_gapi stage
          end
        end

        ##
        # The table in which the query results are stored.
        #
        # @return [Table] A table instance.
        #
        def destination
          table = @gapi.configuration.query.destination_table
          return nil unless table
          retrieve_table table.project_id,
                         table.dataset_id,
                         table.table_id
        end

        ##
        # Checks if the query job is using legacy sql.
        #
        # @return [Boolean] `true` when legacy sql is used, `false` otherwise.
        #
        def legacy_sql?
          val = @gapi.configuration.query.use_legacy_sql
          return true if val.nil?
          val
        end

        ##
        # Checks if the query job is using standard sql.
        #
        # @return [Boolean] `true` when standard sql is used, `false` otherwise.
        #
        def standard_sql?
          !legacy_sql?
        end

        ##
        # The user-defined function resources used in the query. May be either a
        # code resource to load from a Google Cloud Storage URI
        # (`gs://bucket/path`), or an inline resource that contains code for a
        # user-defined function (UDF). Providing an inline code resource is
        # equivalent to providing a URI for a file containing the same code. See
        # [User-Defined Functions](https://cloud.google.com/bigquery/docs/reference/standard-sql/user-defined-functions).
        #
        # @return [Array<String>] An array containing Google Cloud Storage URIs
        #   and/or inline source code.
        #
        def udfs
          udfs_gapi = @gapi.configuration.query.user_defined_function_resources
          return nil unless udfs_gapi
          Array(udfs_gapi).map do |udf|
            udf.inline_code || udf.resource_uri
          end
        end

        ##
        # The encryption configuration of the destination table.
        #
        # @return [Google::Cloud::BigQuery::EncryptionConfiguration] Custom
        #   encryption configuration (e.g., Cloud KMS keys).
        #
        # @!group Attributes
        def encryption
          EncryptionConfiguration.from_gapi(
            @gapi.configuration.query.destination_encryption_configuration
          )
        end

        ##
        # Refreshes the job until the job is `DONE`.
        # The delay between refreshes will incrementally increase.
        #
        # @example
        #   require "google/cloud/bigquery"
        #
        #   bigquery = Google::Cloud::Bigquery.new
        #
        #   sql = "SELECT word FROM `bigquery-public-data.samples.shakespeare`"
        #   job = bigquery.query_job sql
        #
        #   job.wait_until_done!
        #   job.done? #=> true
        #
        def wait_until_done!
          return if done?

          ensure_service!
          loop do
            query_results_gapi = service.job_query_results job_id, max: 0
            if query_results_gapi.job_complete
              @destination_schema_gapi = query_results_gapi.schema
              break
            end
          end
          reload!
        end

        ##
        # Retrieves the query results for the job.
        #
        # @param [String] token Page token, returned by a previous call,
        #   identifying the result set.
        # @param [Integer] max Maximum number of results to return.
        # @param [Integer] start Zero-based index of the starting row to read.
        #
        # @return [Google::Cloud::Bigquery::Data] An object providing access to
        #   data read from the destination table for the job.
        #
        # @example
        #   require "google/cloud/bigquery"
        #
        #   bigquery = Google::Cloud::Bigquery.new
        #
        #   sql = "SELECT word FROM `bigquery-public-data.samples.shakespeare`"
        #   job = bigquery.query_job sql
        #
        #   job.wait_until_done!
        #   data = job.data
        #   data.each do |row|
        #     puts row[:word]
        #   end
        #   data = data.next if data.next?
        #
        def data token: nil, max: nil, start: nil
          return nil unless done?

          ensure_schema!

          options = { token: token, max: max, start: start }
          data_hash = service.list_tabledata \
            destination_table_dataset_id,
            destination_table_table_id,
            options
          Data.from_gapi_json data_hash, destination_table_gapi, service
        end
        alias query_results data

        ##
        # Yielded to a block to accumulate changes for a patch request.
        class Updater < QueryJob
          class << self
            # @private If no job_id or prefix is given, always generate a
            # client-side job ID anyway, for idempotent retry in the
            # google-api-client layer. See
            # https://cloud.google.com/bigquery/docs/managing-jobs#generate-jobid
            def job_ref_from job_id, prefix
              prefix ||= "job_"
              job_id ||= "#{prefix}#{generate_id}"
              API::JobReference.new(
                project_id: @project,
                job_id: job_id
              )
            end

            # @private API object for dataset.
            def dataset_ref_from dts, pjt = nil
              return nil if dts.nil?
              if dts.respond_to? :dataset_id
                Google::Apis::BigqueryV2::DatasetReference.new(
                  project_id: (pjt || dts.project_id || @project),
                  dataset_id: dts.dataset_id
                )
              else
                Google::Apis::BigqueryV2::DatasetReference.new(
                  project_id: (pjt || @project),
                  dataset_id: dts
                )
              end
            end
          end

          ##
          # @private Create an Updater object.
          def initialize gapi
            @gapi = gapi
          end

          # rubocop:disable all

          ##
          # @private Create an Updater from an options hash.
          #
          # @return [Google::Cloud::Bigquery::QueryJob::Updater] A job
          #   configuration object for setting query options.
          def self.from_options query, options
            dataset_config = dataset_ref_from options[:dataset], options[:project]
            req = Google::Apis::BigqueryV2::Job.new(
              configuration: Google::Apis::BigqueryV2::JobConfiguration.new(
                query: Google::Apis::BigqueryV2::JobConfigurationQuery.new(
                  query: query,
                  default_dataset: dataset_config,
                  maximum_billing_tier: options[:maximum_billing_tier]
                )
              )
            )

            updater = QueryJob::Updater.new req
            updater.params = options[:params] if options[:params]
            updater.create = options[:create]
            updater.write = options[:write]
            updater.table = options[:table]
            updater.maximum_bytes_billed = options[:maximum_bytes_billed]
            updater.labels = options[:labels] if options[:labels]
            updater.legacy_sql = Convert.resolve_legacy_sql(
              options[:standard_sql], options[:legacy_sql])
            updater.external = options[:external] if options[:external]
            updater.priority = options[:priority]
            updater.cache = options[:cache]
            updater.large_results = options[:large_results]
            updater.flatten = options[:flatten]
            updater.udfs = options[:udfs]
            updater
          end

          # rubocop:enable all

          # Sets the priority of the query.
          #
          # @param [String] value Specifies a priority for the query. Possible
          #   values include `INTERACTIVE` and `BATCH`.
          #
          # @!group Attributes
          def priority= value
            @gapi.configuration.query.priority = priority_value value
          end

          ##
          # Specifies to look in the query cache for results.
          #
          # @param [Boolean] value Whether to look for the result in the query
          #   cache. The query cache is a best-effort cache that will be flushed
          #   whenever tables in the query are modified. The default value is
          #   true. For more information, see [query
          #   caching](https://developers.google.com/bigquery/querying-data).
          #
          # @!group Attributes
          def cache= value
            @gapi.configuration.query.use_query_cache = value
          end

          ##
          # Allow large results for a legacy SQL query.
          #
          # @param [Boolean] value This option is specific to Legacy SQL.
          #   If `true`, allows the query to produce arbitrarily large result
          #   tables at a slight cost in performance. Requires `table` parameter
          #   to be set.
          #
          # @!group Attributes
          def large_results= value
            @gapi.configuration.query.allow_large_results = value
          end

          ##
          # Flatten nested and repeated fields in legacy SQL queries.
          #
          # @param [Boolean] value This option is specific to Legacy SQL.
          #   Flattens all nested and repeated fields in the query results. The
          #   default value is `true`. `large_results` parameter must be `true`
          #   if this is set to `false`.
          #
          # @!group Attributes
          def flatten= value
            @gapi.configuration.query.flatten_results = value
          end

          ##
          # Sets the default dataset of tables referenced in the query.
          #
          # @param [Dataset] value The default dataset to use for unqualified
          #   table names in the query.
          #
          # @!group Attributes
          def dataset= value
            @gapi.configuration.query.default_dataset =
              Updater.dataset_ref_from value
          end

          ##
          # Sets the query parameters. Standard SQL only.
          #
          # @param [Array, Hash] params Used to pass query arguments when the
          #   `query` string contains either positional (`?`) or named
          #   (`@myparam`) query parameters. If value passed is an array
          #   `["foo"]`, the query must use positional query parameters. If
          #   value passed is a hash `{ myparam: "foo" }`, the query must use
          #   named query parameters. When set, `legacy_sql` will automatically
          #   be set to false and `standard_sql` to true.
          #
          # @!group Attributes
          def params= params
            case params
            when Array then
              @gapi.configuration.query.use_legacy_sql = false
              @gapi.configuration.query.parameter_mode = "POSITIONAL"
              @gapi.configuration.query.query_parameters = params.map do |param|
                Convert.to_query_param param
              end
            when Hash then
              @gapi.configuration.query.use_legacy_sql = false
              @gapi.configuration.query.parameter_mode = "NAMED"
              @gapi.configuration.query.query_parameters =
                params.map do |name, param|
                  Convert.to_query_param(param).tap do |named_param|
                    named_param.name = String name
                  end
                end
            else
              raise "Query parameters must be an Array or a Hash."
            end
          end

          ##
          # Sets the create disposition for creating the query results table.
          #
          # @param [String] value Specifies whether the job is allowed to
          # create new tables. The default value is `needed`.
          #
          #   The following values are supported:
          #
          #   * `needed` - Create the table if it does not exist.
          #   * `never` - The table must already exist. A 'notFound' error is
          #     raised if the table does not exist.
          #
          # @!group Attributes
          def create= value
            @gapi.configuration.query.create_disposition =
              Convert.create_disposition value
          end

          ##
          # Sets the write disposition for when the query results table exists.
          #
          # @param [String] value Specifies the action that occurs if the
          #   destination table already exists. The default value is `empty`.
          #
          #   The following values are supported:
          #
          #   * `truncate` - BigQuery overwrites the table data.
          #   * `append` - BigQuery appends the data to the table.
          #   * `empty` - A 'duplicate' error is returned in the job result if
          #     the table exists and contains data.
          #
          # @!group Attributes
          def write= value
            @gapi.configuration.query.write_disposition =
              Convert.write_disposition value
          end

          ##
          # Sets the destination for the query results table.
          #
          # @param [Table] value The destination table where the query results
          #   should be stored. If not present, a new table will be created
          #   according to the create disposition to store the results.
          #
          # @!group Attributes
          def table= value
            @gapi.configuration.query.destination_table = table_ref_from value
          end

          ##
          # Sets the maximum bytes billed for the query.
          #
          # @param [Integer] value Limits the bytes billed for this job.
          #   Queries that will have bytes billed beyond this limit will fail
          #   (without incurring a charge). Optional. If unspecified, this will
          #   be set to your project default.
          #
          # @!group Attributes
          def maximum_bytes_billed= value
            @gapi.configuration.query.maximum_bytes_billed = value
          end

          ##
          # Sets the labels to use for the job.
          #
          # @param [Hash] value A hash of user-provided labels associated with
          #   the job. You can use these to organize and group your jobs. Label
          #   keys and values can be no longer than 63 characters, can only
          #   contain lowercase letters, numeric characters, underscores and
          #   dashes. International characters are allowed. Label values are
          #   optional. Label keys must start with a letter and each label in
          #   the list must have a different key.
          #
          # @!group Attributes
          #
          def labels= value
            @gapi.configuration.update! labels: value
          end

          ##
          # Sets the query syntax to legacy SQL.
          #
          # @param [Boolean] value Specifies whether to use BigQuery's [legacy
          #   SQL](https://cloud.google.com/bigquery/docs/reference/legacy-sql)
          #   dialect for this query. If set to false, the query will use
          #   BigQuery's [standard
          #   SQL](https://cloud.google.com/bigquery/docs/reference/standard-sql/)
          #   dialect. Optional. The default value is false.
          #
          # @!group Attributes
          #
          def legacy_sql= value
            @gapi.configuration.query.use_legacy_sql = value
          end

          ##
          # Sets the query syntax to standard SQL.
          #
          # @param [Boolean] value Specifies whether to use BigQuery's [standard
          #   SQL](https://cloud.google.com/bigquery/docs/reference/standard-sql/)
          #   dialect for this query. If set to true, the query will use
          #   standard SQL rather than the [legacy
          #   SQL](https://cloud.google.com/bigquery/docs/reference/legacy-sql)
          #   dialect. Optional. The default value is true.
          #
          # @!group Attributes
          #
          def standard_sql= value
            @gapi.configuration.query.use_legacy_sql = !value
          end

          ##
          # Sets definitions for external tables used in the query.
          #
          # @param [Hash<String|Symbol, External::DataSource>] value A Hash
          #   that represents the mapping of the external tables to the table
          #   names used in the SQL query. The hash keys are the table names,
          #   and the hash values are the external table objects.
          #
          # @!group Attributes
          #
          def external= value
            external_table_pairs = value.map do |name, obj|
              [String(name), obj.to_gapi]
            end
            external_table_hash = Hash[external_table_pairs]
            @gapi.configuration.query.table_definitions = external_table_hash
          end

          ##
          # Sets user defined functions for the query.
          #
          # @param [Array<String>, String] value User-defined function resources
          #   used in the query. May be either a code resource to load from a
          #   Google Cloud Storage URI (`gs://bucket/path`), or an inline
          #   resource that contains code for a user-defined function (UDF).
          #   Providing an inline code resource is equivalent to providing a URI
          #   for a file containing the same code. See [User-Defined
          #   Functions](https://cloud.google.com/bigquery/docs/reference/standard-sql/user-defined-functions).
          #
          # @!group Attributes
          def udfs= value
            @gapi.configuration.query.user_defined_function_resources =
              udfs_gapi_from value
          end

          ##
          # Sets the encryption configuration of the destination table.
          #
          # @param [Google::Cloud::BigQuery::EncryptionConfiguration] val
          #   Custom encryption configuration (e.g., Cloud KMS keys).
          #
          # @example
          #   require "google/cloud/bigquery"
          #
          #   bigquery = Google::Cloud::Bigquery.new
          #   dataset = bigquery.dataset "my_dataset"
          #
          #   key_name = "projects/a/locations/b/keyRings/c/cryptoKeys/d"
          #   encrypt_config = bigquery.encryption kms_key: key_name
          #   job = bigquery.query_job "SELECT 1;" do |query|
          #     query.table = dataset.table "my_table", skip_lookup: true
          #     query.encryption = encrypt_config
          #   end
          #
          # @!group Attributes
          def encryption= val
            @gapi.configuration.query.update!(
              destination_encryption_configuration: val.to_gapi
            )
          end

          ##
          # @private Returns the Google API client library version of this job.
          #
          # @return [<Google::Apis::BigqueryV2::Job>] (See
          #   {Google::Apis::BigqueryV2::Job})
          def to_gapi
            @gapi
          end

          protected

          # Creates a table reference from a table object.
          def table_ref_from tbl
            return nil if tbl.nil?
            Google::Apis::BigqueryV2::TableReference.new(
              project_id: tbl.project_id,
              dataset_id: tbl.dataset_id,
              table_id: tbl.table_id
            )
          end

          def priority_value str
            { "batch" => "BATCH",
              "interactive" => "INTERACTIVE" }[str.to_s.downcase]
          end

          def udfs_gapi_from array_or_str
            Array(array_or_str).map do |uri_or_code|
              resource =
                Google::Apis::BigqueryV2::UserDefinedFunctionResource.new
              if uri_or_code.start_with?("gs://")
                resource.resource_uri = uri_or_code
              else
                resource.inline_code = uri_or_code
              end
              resource
            end
          end
        end

        ##
        # Represents a stage in the execution plan for the query.
        #
        # @attr_reader [Float] compute_ratio_avg Relative amount of time the
        #   average shard spent on CPU-bound tasks.
        # @attr_reader [Float] compute_ratio_max Relative amount of time the
        #   slowest shard spent on CPU-bound tasks.
        # @attr_reader [Integer] id Unique ID for the stage within the query
        #   plan.
        # @attr_reader [String] name Human-readable name for the stage.
        # @attr_reader [Float] read_ratio_avg Relative amount of time the
        #   average shard spent reading input.
        # @attr_reader [Float] read_ratio_max Relative amount of time the
        #   slowest shard spent reading input.
        # @attr_reader [Integer] records_read Number of records read into the
        #   stage.
        # @attr_reader [Integer] records_written Number of records written by
        #   the stage.
        # @attr_reader [Array<Step>] steps List of operations within the stage
        #   in dependency order (approximately chronological).
        # @attr_reader [Float] wait_ratio_avg Relative amount of time the
        #   average shard spent waiting to be scheduled.
        # @attr_reader [Float] wait_ratio_max Relative amount of time the
        #   slowest shard spent waiting to be scheduled.
        # @attr_reader [Float] write_ratio_avg Relative amount of time the
        #   average shard spent on writing output.
        # @attr_reader [Float] write_ratio_max Relative amount of time the
        #   slowest shard spent on writing output.
        #
        # @example
        #   require "google/cloud/bigquery"
        #
        #   bigquery = Google::Cloud::Bigquery.new
        #
        #   sql = "SELECT word FROM `bigquery-public-data.samples.shakespeare`"
        #   job = bigquery.query_job sql
        #
        #   job.wait_until_done!
        #
        #   stages = job.query_plan
        #   stages.each do |stage|
        #     puts stage.name
        #     stage.steps.each do |step|
        #       puts step.kind
        #       puts step.substeps.inspect
        #     end
        #   end
        #
        class Stage
          attr_reader :compute_ratio_avg, :compute_ratio_max, :id, :name,
                      :read_ratio_avg, :read_ratio_max, :records_read,
                      :records_written, :status, :steps, :wait_ratio_avg,
                      :wait_ratio_max, :write_ratio_avg, :write_ratio_max

          ##
          # @private Creates a new Stage instance.
          def initialize compute_ratio_avg, compute_ratio_max, id, name,
                         read_ratio_avg, read_ratio_max, records_read,
                         records_written, status, steps, wait_ratio_avg,
                         wait_ratio_max, write_ratio_avg, write_ratio_max
            @compute_ratio_avg = compute_ratio_avg
            @compute_ratio_max = compute_ratio_max
            @id                = id
            @name              = name
            @read_ratio_avg    = read_ratio_avg
            @read_ratio_max    = read_ratio_max
            @records_read      = records_read
            @records_written   = records_written
            @status            = status
            @steps             = steps
            @wait_ratio_avg    = wait_ratio_avg
            @wait_ratio_max    = wait_ratio_max
            @write_ratio_avg   = write_ratio_avg
            @write_ratio_max   = write_ratio_max
          end

          ##
          # @private New Stage from a statistics.query.queryPlan element.
          def self.from_gapi gapi
            steps = Array(gapi.steps).map { |g| Step.from_gapi g }
            new gapi.compute_ratio_avg, gapi.compute_ratio_max, gapi.id,
                gapi.name, gapi.read_ratio_avg, gapi.read_ratio_max,
                gapi.records_read, gapi.records_written, gapi.status, steps,
                gapi.wait_ratio_avg, gapi.wait_ratio_max, gapi.write_ratio_avg,
                gapi.write_ratio_max
          end
        end

        ##
        # Represents an operation in a stage in the execution plan for the
        # query.
        #
        # @attr_reader [String] kind Machine-readable operation type. For a full
        #   list of operation types, see [Steps
        #   metadata](https://cloud.google.com/bigquery/query-plan-explanation#steps_metadata).
        # @attr_reader [Array<String>] substeps Human-readable stage
        #   descriptions.
        #
        # @example
        #   require "google/cloud/bigquery"
        #
        #   bigquery = Google::Cloud::Bigquery.new
        #
        #   sql = "SELECT word FROM `bigquery-public-data.samples.shakespeare`"
        #   job = bigquery.query_job sql
        #
        #   job.wait_until_done!
        #
        #   stages = job.query_plan
        #   stages.each do |stage|
        #     puts stage.name
        #     stage.steps.each do |step|
        #       puts step.kind
        #       puts step.substeps.inspect
        #     end
        #   end
        #
        class Step
          attr_reader :kind, :substeps

          ##
          # @private Creates a new Stage instance.
          def initialize kind, substeps
            @kind = kind
            @substeps = substeps
          end

          ##
          # @private New Step from a statistics.query.queryPlan[].steps element.
          def self.from_gapi gapi
            new gapi.kind, Array(gapi.substeps)
          end
        end

        protected

        def ensure_schema!
          return unless destination_schema.nil?

          query_results_gapi = service.job_query_results job_id, max: 0
          # raise "unable to retrieve schema" if query_results_gapi.schema.nil?
          @destination_schema_gapi = query_results_gapi.schema
        end

        def destination_schema
          @destination_schema_gapi
        end

        def destination_table_dataset_id
          @gapi.configuration.query.destination_table.dataset_id
        end

        def destination_table_table_id
          @gapi.configuration.query.destination_table.table_id
        end

        def destination_table_gapi
          Google::Apis::BigqueryV2::Table.new \
            table_reference: @gapi.configuration.query.destination_table,
            schema: destination_schema
        end
      end
    end
  end
end
