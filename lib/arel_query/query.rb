module ArelQuery
  class Query
    # "none" is the one not in the list in the source code
  
    UNSUPPORTED_METHODS = { includes:    :joins,     eager_load:    :joins,
                            preload:     :joins,     bind:          nil,
                            references:  :joins,     extending:     nil,
                            unscope:     nil,        readonly:      nil,
                            reorder:     nil,        reverse_order: nil,
                            create_with: nil }
  
    SINGLE_VALUE_METHODS = [:limit, :offset, :from]
    MULTI_VALUE_METHODS = [:select, :group, :order, :joins]
    DEFINED_METHODS = [:where, :having, :lock, :uniq, :distinct]
  
    def initialize(table_name)
      @arel_table = Arel::Table.new(table_name)
      @values = {}
    end
  
    # Compare ActiveRecord::Relation#initialize_copy
    def initialize_copy(other)
      @values = @values.dup # Note contents is not dup'ed and should be read only. See Object#dup
      @arel = nil
    end

    def set_value(name, value)
      @values[name] = value
    end

    def add_values(name, values)
      @values[name] ||= []
      @values[name] += values
    end

    SINGLE_VALUE_METHODS.each do |name|
      define_method("#{name}!") do |arg|
        set_value(name, arg)
        self
      end
    end

    MULTI_VALUE_METHODS.each do |name|
      define_method("#{name}!") do |*args|
        add_values(name, args)
        self
      end
    end

    (SINGLE_VALUE_METHODS + MULTI_VALUE_METHODS + DEFINED_METHODS).each do |name|
      define_method(name) do |*args|
        clone.send("#{name}!", *args)
      end
    end
  
    UNSUPPORTED_METHODS.each do |name, alternative|
      msg = "Unsupported ActiveRecord query method #{name}."
      msg += " Try #{alternative} instead." unless alternative.nil?
      define_method(name) { |*args| raise NoMethodError, msg }
      define_method("#{name}!") { |*args| raise NoMethodError, msg }
    end
    
    def to_sql
      arel.to_sql
    end
  
    # Compare ActiveRecord::QueryMethods#where! and line from #build_arel
    def where!(opts, *rest)
      add_values(:where, build_where(opts, rest))
      self
    end

    # Compare ActiveRecord::QueryMethods#having!
    def having!(opts, *rest)
      add_values(:having, build_where(opts, reset))
      self
    end

    # Compare ActiveRecord::QueryMethods#lock!
    def lock!(locks = true)
      set_value(:lock, locks)
      self
    end

    # Compare ActiveRecord::QueryMethods#distinct!
    def distinct!(value = true)
      set_value(:distinct, value)
      self
    end
    alias_method :uniq!, :distinct!

    # Compare ActiveRecord::QueryMethods#arel
    def arel
      @arel ||= build_arel
    end
  
    private

    # Compare ActiveRecord::QueryMethods#build_arel
    def build_arel
      arel = Arel::SelectManager.new(@arel_table.engine, @arel_table)
      build_joins(arel, @values[:joins]) if @values.key?(:joins)
      dummy_relation.send(:collapse_wheres, arel, (@values[:where] - ['']).uniq) if @values.key?(:where)
      arel.having(*@values[:having].uniq.reject(&:blank?)) if @values.key?(:having)
      arel.take(ArelQuery.connector.connection.sanitize_limit(@values[:limit])) if @values.key?(:limit)
      arel.skip(@values[:offset].to_i) if @values.key?(:offset)
      arel.group(*@values[:group].uniq.reject(&:blank?)) if @values.key?(:group)
      arel.order(*@values[:order].uniq.reject(&:blank?)) if @values.key?(:order)
      arel.project(*(@values[:select] || [Arel.star]).uniq)
      arel.distinct(@values[:distinct]) if @values.key?(:distinct)
      arel.from(@values[:from]) if @values.key?(:from)
      arel.lock(@values[:lock]) if @values.key?(:lock)
      arel
    end
  
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
          [ActiveRecord::Base.send(:sanitize_sql_array, other.empty? ? opts : ([opts] + other))]
        end
      when Hash
        ActiveRecord::PredicateBuilder.build_from_hash(ActiveRecord::Base, opts, @arel_table)
      else
        [opts]
      end
    end

    # Compare ActiveRecord::QueryMethods#build_joins
    def build_joins(arel, joins)
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
      
      join_list = join_nodes + dummy_relation.send(:custom_join_ast, arel, string_joins)
      arel.join_sources.concat(join_list)
    end
  end
end
