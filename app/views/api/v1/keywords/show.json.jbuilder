json.partial! 'api/v1/keywords/keyword', keyword: [@keyword, @pagy.count]

json.packages do
  json.array! @packages, partial: 'api/v1/packages/package', as: :package
end

json.related_keywords do
  json.array! @related_keywords, partial: 'api/v1/keywords/keyword', as: :keyword
end