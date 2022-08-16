class ExportsController < ApplicationController
  def index
    @exports = Export.all
  end
end