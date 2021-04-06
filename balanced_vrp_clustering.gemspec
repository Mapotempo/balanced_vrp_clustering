Gem::Specification.new do |s|
  s.name = 'balanced_vrp_clustering'
  s.version = '0.2.0'
  s.date = '2021-03-09'
  s.summary = 'Gem for clustering points of a given VRP.'
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
  s.add_dependency "awesome_print"   # for geojson debug output
end
