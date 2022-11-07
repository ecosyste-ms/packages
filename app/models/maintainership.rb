class Maintainership < ApplicationRecord
  belongs_to :maintainer
  belongs_to :package
end
