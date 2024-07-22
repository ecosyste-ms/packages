require 'pagy/extras/headers'
require 'pagy/extras/limit'
require 'pagy/extras/bootstrap'
require 'pagy/extras/countless'
require 'pagy/extras/array'
require 'pagy/extras/overflow'

Pagy::DEFAULT[:limit] = 100
Pagy::DEFAULT[:limit_param] = :per_page
Pagy::DEFAULT[:limit_max] = 1000
Pagy::DEFAULT[:overflow] = :empty_page
