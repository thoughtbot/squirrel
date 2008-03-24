class Hash
  def deep_merge other
    self.dup.deep_merge! other
  end
  
  def deep_merge! other
    other.each do |key, value|
      if self[key].is_a?(Hash) && value.is_a?(Hash)
        self[key] = self[key].deep_merge(value)
      else
        self[key] = value
      end
    end
    self
  end
end

module ActiveRecord #:nodoc: all
  module Associations
    module ClassMethods
      class JoinDependency
        class JoinAssociation
          def ancestry #:doc
            [ parent.ancestry, reflection.name ].flatten.compact
          end
        end
        class JoinBase
          def ancestry
            nil
          end
        end
      end
    end
  end
end

