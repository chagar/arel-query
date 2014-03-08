require 'arel_query/query'

Arq = ArelQuery::Query

module ArelQuery
  VERSION = '0.0.1'

  def self.connector=(engine)
    @connector = engine
    Arel::Table.engine = engine
  end

  def self.connector
    @connector
  end
end
  
if defined?(ActiveRecord::Base) && ActiveRecord::Base.respond_to?(:connection)
  ArelQuery.connector = ActiveRecord::Base
else
  require 'arel_query/active_record_connector'
  ArelQuery.connector = ArelQuery::Connector::ActiveRecordConnector
end

unless defined?(ActiveRecord::Relation)
  module ActiveRecord
    class Relation; end
    module Explain; end
    module FinderMethods; end
    module Calculations; end
    module SpawnMethods; end
    module QueryMethods; end
    module Batches; end
    module Delegation; end
  end

  require 'active_record/relation'
  require 'active_record/explain'
  require 'active_record/relation/finder_methods'
  require 'active_record/relation/calculations'
  require 'active_record/relation/spawn_methods'
  require 'active_record/relation/query_methods'
  require 'active_record/relation/batches'
  require 'active_record/relation/delegation'
end
