require File.dirname(__FILE__) + '/lib/squirrel.rb'
ActiveRecord::Base.send :include, Squirrel::Hook
