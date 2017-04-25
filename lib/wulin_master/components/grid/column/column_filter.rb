require 'wulin_master/components/grid/column/sql_adapter'

module WulinMaster
  module ColumnFilter
    # Apply a where condition on the query to filter the result set with the filtering value
    def apply_filter(query, filtering_value, filtering_operator='equals')
      adapter = WulinMaster::SqlAdapter.new(model, query)
      filtering_operator ||= 'equals'
      return query if filtering_value.blank?

      # Search by NULL
      return filter_by_null(query, filtering_value, filtering_operator, adapter) if filtering_value.to_s.downcase == 'null'

      # Although RoleUser `belongs_to` user, User (in WulinOAuth) doesn't provide
      # `has_many` relationship to RoleUser since it is not inherited from
      # ActiveRecord. For this reason, query for RoleUser should use filter_without_reflection.

      if reflection && (defined?(RolesUser) ? query != RolesUser : true)
        return filter_with_reflection(query, filtering_value, filtering_operator, adapter)
      else
        return filter_without_reflection(query, filtering_value, sql_type, adapter)
      end
      adapter.query
    end

    private

    def filter_by_null(query, filtering_value, filtering_operator, adapter)
      operator = case filtering_operator
      when 'equals' then ''
      when 'not_equals' then 'NOT'
      end
      if self.reflection
        return query.where("#{relation_table_name}.#{self.source} IS #{operator} NULL")
      else
        adapter.null_query(complete_column_name, operator, self)
        return adapter.query
      end
    end

    def filter_with_reflection(query, filtering_value, filtering_operator, adapter)
      if @options[:sql_expression]
        return query.where(["UPPER(cast((#{@options[:sql_expression]}) as text)) LIKE UPPER(?)", filtering_value+"%"])
      else
        column_type = column_type(self.reflection.klass, self.source)
        # for special column,
        if self.source =~ /(_)?id$/ or [:integer, :float, :decimal, :boolean, :date, :datetime].include? column_type
          filtering_value = format_filtering_value(filtering_value, column_type)
          if ['equals', 'not_equals'].include? filtering_operator
            return apply_equation_filter(query, filtering_operator, filtering_value, column_type.to_s, adapter)
          elsif ['include', 'exclude'].include? filtering_operator
            return apply_inclusion_filter(query, filtering_operator, filtering_value)
          end
        # for string column
        else
          return apply_string_filter(query, filtering_operator, filtering_value)
        end
      end
    end

    def apply_equation_filter(query, operator, value, column_type, adapter)
      if ['date', 'datetime'].include? column_type
        operator = (operator == 'equals') ? 'LIKE' : 'NOT LIKE'
        return query.where(["to_char(##{relation_table_name}.#{self.source}, 'YYYY-MM-DD') #{operator} UPPER(?)", "#{value}%"])
      elsif column_type == "boolean"
        adapter.boolean_query("#{relation_table_name}.#{self.source}", value, self)
        return adapter.query
      else
        where_condition = {relation_table_name.to_sym => {self.source.to_sym => value}}
        if operator == 'equals'
          return query.where(where_condition)
        else
          return query.where.not(where_condition)
        end
      end
    end

    def apply_inclusion_filter(query, operator, value)
      relation_class = self.reflection.klass
      ids = relation_class.where("#{relation_table_name}.#{self.source} = ?", value).map do |e|
        real_relation_name = relation_class.reflections.find { |k| k[1].klass.name == model.name }[0]
        e.send(real_relation_name).map(&:id)
      end.flatten.uniq
      if ids.blank?
        operator = (operator == 'include') ? 'IS' : 'IS NOT'
        return query.where("#{model.table_name}.id #{operator} NULL")
      else
        operator = (operator == 'include') ? 'IN' : 'NOT IN'
        return query.where("#{model.table_name}.id #{operator} (?)", ids)
      end
    end

    def apply_string_filter(query, operator, value)
      operator = case operator
      when 'equals' then 'LIKE'
      when 'not_equals' then 'NOT LIKE'
      end
      return query.where(["UPPER(cast(#{relation_table_name}.#{self.source} as text)) #{operator} UPPER(?)", value + "%"])
    end

    def format_filtering_value(value, column_type)
      formatted_value = if column_type == :integer
        value.to_i
      elsif column_type == :float or column_type == :decimal
        filtering_value.to_f
      elsif column_type == :boolean
        true_values = ["y", "yes", "ye", "t", "true"]
        true_values.include?(value.downcase)
      end
    end

    def filter_without_reflection(query, filtering_value, column_sql_type, adapter)
      case column_sql_type.to_s
      when 'date', 'datetime'
        return query.where(["to_char(#{self.source}, 'YYYY-MM-DD') LIKE UPPER(?)", filtering_value+"%"])
      when "boolean"
        true_values = ["y", "yes", "ye", "t", "true"]
        true_or_false = true_values.include?(filtering_value.downcase)
        adapter.boolean_query(complete_column_name, true_or_false, self)
        return adapter.query
      else
        filtering_value = filtering_value.gsub(/'/, "''")

        enums = self.model.try(:defined_enums)
        if enums && enums.has_key?(self.source.to_s)
          filtering_value = self.model.send(self.source.to_s.pluralize).find {|k, v| v if k.start_with?(filtering_value)}
        end

        if ['integer', 'float', 'decimal'].include? sql_type.to_s and is_table_column?
          return query.where(self.source => filtering_value)
        else
          adapter.string_query(complete_column_name, filtering_value, self)
          return adapter.query
        end
      end
    end

  end
end
