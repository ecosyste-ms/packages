require 'pagy/extras/headers'
require 'pagy/extras/items'
require 'pagy/extras/bootstrap'

Pagy::DEFAULT[:items] = 100
Pagy::DEFAULT[:items_param] = :per_page
Pagy::DEFAULT[:max_items] = 100 