Gem::Specification.new do |s|
  s.name = 'balanced_vrp_clustering'
  s.version = '0.1.7'
  s.date = '2020-08-13'
  s.summary = 'Gem to clusterize points of a given VRP.'
  s.authors = 'Mapotempo'
  s.files = [
    "lib/balanced_vrp_clustering.rb",
    "lib/helpers/helper.rb",
    "lib/helpers/hull.rb",
    "lib/concerns/overloadable_functions.rb"
  ]
  s.require_paths = ["lib", "test"]

  s.add_dependency "color-generator" # for geojson debug output
  s.add_dependency "geojson2image"   # for geojson debug output
end
