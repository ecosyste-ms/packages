class ExportsController < ApplicationController
  def index
    @exports = Export.order("date DESC")
  end
end