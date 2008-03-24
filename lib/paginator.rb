module Squirrel
  # The Page class holds information about the current page of results.
  class Page
    attr_reader :offset, :limit, :page, :per_page
    def initialize(offset, limit, page, per_page)
      @offset, @limit, @page, @per_page = offset, limit, page, per_page
    end
  end

  # A Paginator object is what gets inserted into the result set and is returned by
  # the #pages method of the result set. Contains offets and limits for all pages.
  class Paginator < Array
    attr_reader :total_results, :per_page, :current, :next, :previous, :first, :last, :current_range
    def initialize opts={}
      @total_results = opts[:count].to_i
      @limit         = opts[:limit].to_i
      @offset        = opts[:offset].to_i

      @per_page      = @limit
      @current       = (@offset / @limit) + 1
      @first         = 1
      @last          = ((@total_results-1) / @limit) + 1
      @next          = @current + 1 if @current < @last
      @previous      = @current - 1 if @current > 1
      @current_range = ((@offset+1)..([@offset+@limit, @total_results].min))

      (@first..@last).each do |page|
        self[page-1] = Page.new((page-1) * @per_page, @per_page, page, @per_page)
      end
    end
  end
end
