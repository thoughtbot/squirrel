require 'paginator'

module Thoughtbot
	module Squirrel
		module ActiveRecordHook # :nodoc:
			def self.included base
				class << base
					alias_method :pre_squirrel_find, :find
					def find *args, &blk
				    args ||= [:all]
						if blk
							query = Query.new(self, &blk)
							query.execute(*args)
						else
							pre_squirrel_find(*args)
						end
					end
				end
			end
		end

		class Query
			attr_reader :conditions, :model

			def initialize model, &blk
				@model = model
				@joins = nil
				@conditions = ConditionBlock.new(@model, "AND", blk.binding, :base, &blk)
				hand_out_join_associations
			end
			
			def joins
				@joins ||= hashized_join_associations
			end
			
			def join_dependency
				@join_dependency ||= ::ActiveRecord::Associations::ClassMethods::JoinDependency.new(model, self.include, nil)
			end

			def execute *args
				if args.first == :query
					self
				else
					results = model.find args[0], (args[1] || {}).merge(@conditions.to_params)
					if @conditions.paginate?
            count_conditions = @conditions.to_params
            limit  = count_conditions.delete(:limit)
            offset = count_conditions.delete(:offset)

					  class << results
					    attr_reader :pages
					    attr_reader :total_results
				    end

            total_results = model.count(count_conditions)
				    results.instance_variable_set("@pages", Paginator.new( :count => total_results, :limit => limit, :offset => offset) )
				    results.instance_variable_set("@total_results", total_results)
				  end
				  results
				end
			end
			
			def include
				@conditions.include
			end
			
			protected
			
			def hand_out_join_associations
				@conditions.assign_join_associations(joins)
			end

			def join_parent_names assn
				if assn.respond_to? :parent
					[join_parent_names(assn.parent), assn.reflection.name].flatten
				else
					[:base]
				end
			end

			def hashized_join_associations
				joins = {}
				join_dependency.joins.reverse.each do |join|
					join_parent_names(join).inject(joins){|hash, name| hash[name] ||= {} }[:_join] = join
				end
				joins
			end

			class ConditionBlock
				attr_accessor :model, :join, :binding, :reflections, :reflection

				def initialize model, join, binding, reflection = nil, &blk
					@model = model
					@join = join
					@conditions = []
					@condition_blocks = []
					@reflections = []
					@reflection = reflection
					@binding = binding
					@order = []
					@negative = false
					@paginator = false

					existing_methods = self.class.instance_methods(false)
					(model.column_names - existing_methods).each do |col|
						(class << self; self; end).class_eval do
							define_method(col.to_s.intern) do
								column(col)
							end
						end
					end
					(model.reflections.keys - existing_methods).each do |assn|
						(class << self; self; end).class_eval do
							define_method(assn.to_s.intern) do
								association(assn)
							end
						end
					end

					if blk
						instance_eval &blk
					end
				end

				def column name
					@conditions << Condition.new(name)
					@conditions.last
				end

				def association name, &blk
					name = name.to_s.intern
					ref = @model.reflect_on_association(name)
					@condition_blocks << ConditionBlock.new(ref.klass, join, binding, ref.name, &blk)
					@condition_blocks.last
				end

				def any &blk
					@condition_blocks << ConditionBlock.new(model, "OR", binding, &blk)
					@condition_blocks.last
				end

				def all &blk
					@condition_blocks << ConditionBlock.new(model, "AND", binding, &blk)
					@condition_blocks.last
				end
				
				def order_by *columns
					@order += [columns].flatten
				end
				
				def order_clause
					@order.blank? ? nil : @order.collect{|col| col.full_name + (col.negative? ? " DESC" : "") }.join(", ")
			  end
				
				def paginate opts = {}
				  @paginator = true
				  page     = (opts[:page]     || 1).to_i
				  per_page = (opts[:per_page] || 20).to_i
				  limit( per_page, ( page - 1 ) * per_page )
			  end
			  
			  def limit lim, off = nil
			    find_options.merge! :limit => lim, :offset => (off || find_options[:offset])
		    end
		    
		    def paginate?
		      @paginator || @condition_blocks.any?(&:paginate?)
	      end
				
				def -@
					@negative = !@negative
				end
				
				def to_params
					ps = {}
					ps.merge! :conditions => to_sql, :include => self.include
					ps.merge! find_options.merge(:order => order_clause)
					ps
				end

				def to_sql
					segments = conditions.collect{|c| c.to_sql }.compact
					return nil if segments.length == 0
					cond = "(" + segments.collect{|s| s.first }.join(" #{join} ") + ")"
					cond = "NOT #{cond}" if negative?
					
					values = segments.inject([]){|all, now| all + now[1..-1] }
					[ cond, *values ]
				end

				def conditions
					@conditions + @condition_blocks
				end
				
				def assign_join_associations(joins)
					@join_associations = reflection.nil? ? joins : joins[reflection]
					conditions.each do |cond|
						cond.assign_join_associations(@join_associations)
					end
				end

				def include
					@condition_blocks.inject({}) do |inc, cb|
						if cb.reflection.nil?
							inc.merge(cb.include)
						else
							inc[cb.reflection] ||= {}
							inc[cb.reflection] = inc[cb.reflection].merge(cb.include)
							inc
						end
					end
				end
				
				def complex?
					@condition_blocks.any?{|each| each.reflection != self.reflection }
				end
				
				def negative?
					@negative
				end

				def method_missing meth, *args
					m = eval("method(:#{meth})", binding)
					if m
						m.call(*args)
					else
						raise NameError, "Column or Relationship #{meth} not defined for #{@model.class.name}"
					end
				end
				
				def find_options
				  @find_options ||= {}
			  end
			end

			class Condition
				attr_reader :name, :operator, :operand

				def initialize name
					@name = name
					@sql = nil
					@negative = false
				end

				[ :==, :===, :=~, :<=>, :<=, :<, :>, :>= ].each do |op|
					define_method(op) do |val|
						@operator = op
						@operand = val
						self
					end
				end

				def contains? val
					@operator = :contains
					@operand = val
					self
				end
				
				def -@
					@negative = !@negative
					self
				end
				
				def negative?
					@negative
				end
				
				def assign_join_associations(joins)
					@join_association = joins[:_join]
				end
				
				def full_name
					if @join_association
						"#{@join_association.aliased_table_name}.#{name}"
					else
						name
					end
				end

				def to_sql(join_association = {})
					return nil if operator.nil?
					
					op, arg_format, values = operator, "?", [operand]
					op, arg_format, values = case operator
					when :<=>       then    [ "BETWEEN", "? AND ?",   [ operand.first, operand.last ] ]
					when :=~        then
						case operand
						when String   then    [ "LIKE",    arg_format,  values ]
						when Regexp   then    [ "REGEXP",  arg_format,  values.map(&:source) ]
						end
					when :==, :===  then
						case operand
						when Array    then    [ "IN",      "(?)",       values ]
						when Range    then    [ "IN",      "(?)",       values ]
						when nil      then    [ "IS",      "NULL",      [] ]
						else                  [ "=",       arg_format,  values ]
						end
					when :contains  then    [ "LIKE",    arg_format,  values.map{|v| "%#{v}%" } ]
					else                    [ op,        arg_format,  values ]
					end		
					sql = "#{full_name} #{op} #{arg_format}"
					sql = "NOT (#{sql})" if @negative
					[ sql, *values ]
				end

			end
		end
	end
end