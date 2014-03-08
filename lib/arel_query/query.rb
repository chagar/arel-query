require 'arel'
#require 'active_support'
#require 'active_support/rails'
#require 'active_record'

module ArelQuery
  class Query
    # "none" is the one not in the list in the source code
    # Apparently #having uses build_where as well?
  
    UNSUPPORTED_METHODS = { includes:    :joins,     eager_load:    :joins,
                            preload:     :joins,     bind:          nil,
                            references:  :joins,     extending:     nil,
                            unscope:     nil,        readonly:      nil,
                            reorder:     nil,        reverse_order: nil,
                            create_with: nil }
  
    PASSTHROUGH_METHODS = { select: :project,      group:    nil,
                            order:  nil,           having:   nil,
                            limit:  :take,         offset:   :skip,
                            lock:   nil,           from:     nil,
                            uniq:   :distinct,     distinct: nil }
  
    DEFINED_METHODS = [:where, :joins]
  
    def initialize(table_name)
      @arel_table = Arel::Table.new(table_name)
      @arel = Arel::SelectManager.new(@arel_table.engine, @arel_table) # From ActiveRecord::QueryMethods#build_arel
    end
  
    def initialize_copy(other)
      @arel_table, @arel = @arel_table.clone, @arel.clone
    end
  
    PASSTHROUGH_METHODS.each do |name, arel_name|
      arel_name = name if arel_name.nil?
      
      define_method("#{name}!") do |*args|
        @arel.send(arel_name, *args)
        self
      end
    end
  
    (DEFINED_METHODS + PASSTHROUGH_METHODS.keys).each do |name|
      define_method(name) do |*args|
        clone.send("#{name}!", *args)
      end
    end
  
    UNSUPPORTED_METHODS.each do |name, alternative|
      msg = "Unsupported query method #{name}."
      msg += " Try #{alternative} instead." unless alternative.nil?
      define_method(name) { |*args| raise NoMethodError, msg }
    end
    
    def to_sql
      @arel.to_sql
    end
  
    # Compare ActiveRecord::QueryMethods#where! and line from #build_arel
    def where!(opts, *rest)
      where_values = build_where(opts, rest)
      dummy_relation.send(:collapse_wheres, @arel, (where_values - ['']).uniq)
      self
    end
  
    #Compare ActiveRecord::QueryMethods#joins! and line from #build_arel
    def joins!(*args)
      args.compact!
      args.flatten!
      build_joins(args) unless args.empty?
      self
    end
  
    private
  
    def dummy_relation
      @dummy_relation ||= ActiveRecord::Relation.new(nil, @arel_table)
    end
    
    # Compare ActiveRecord::QueryMethods#build_where, and ActiveRecord::Sanitization#sanitize_sql
    # Avoids calling #sanitize_sql, which results in error setting table_name = self.table_name
    def build_where(opts, other = [])
      case opts
      when String, Array
        if opts.is_a?(String) && other.empty?
          [opts]
        else
          [@klass.send(:sanitize_sql_array, other.empty? ? opts : ([opts] + other))]
        end
      when Hash
        ActiveRecord::PredicateBuilder.build_from_hash(ActiveRecord::Base, opts, @arel_table)
      else
        [opts]
      end
    end
  
    # Compare ActiveRecord::QueryMethods#build_joins
    def build_joins(joins)
      buckets = joins.group_by do |join|
        case join
        when String
          :string_join
        when Hash, Symbol, Array
          raise TypeError, "Unsupported join type #{join.class}. Try String instead."
        when ActiveRecord::Associations::JoinDependency
          raise TypeError, "Unsupported join type #{join.class}. Try String instead."
        when Arel::Nodes::Join
          :join_node
        else
          raise 'unknown class: %s' % join.class.name
        end
      end
  
      join_nodes                = (buckets[:join_node] || []).uniq
      string_joins              = (buckets[:string_join] || []).map(&:strip).uniq
      
      join_list = join_nodes + dummy_relation.send(:custom_join_ast, @arel, string_joins)
  
      @arel.join_sources.concat(join_list)
    end
  end
end
