json.array! @results do |result|
  json.partial! "api/v1/purls/result", result: result
end
