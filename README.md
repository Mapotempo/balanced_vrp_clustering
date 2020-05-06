# About Balanced VRP Clustering

This gem aims to help you solving your Vehicle Routing Problems by generating one sub-problem per vehicle. It is an adaptation of kmeans algorithm (based ok ai4r library : https://github.com/SergioFierens/ai4r), including notions of balance.

# Gem generation (for contributors)

Within gem project use
```gem build balanced_vrp_clustering.gemspec``` and ```gem install balanced_vrp_clustering``` to generate gem.

  # Usage

##### Include gem in your own ruby project

In your Gemfile :

```gem 'balanced_vrp_clustering'```

In your ruby script :

```require 'balanced_vrp_clustering'```

##### Clustering example

Initialize your clusterer tool c and provided needed data :

```c = Ai4r::Clusterers::BalancedVRPClustering.new```

```
vehicles_infos = {
  "v_id": vehicle_id e.g. 'vehicle_1',
  "days": list of available days e.g. ['monday', 'tuesday'] ,
  "depot": indice of corresponding depot in matrix, if any provided. Otherwise, [latitude, longitude] of vehicle depot,
  "capactities": { "unit_1": 10, "unit_2": 100 },
  "skills": list of skills e.g. ['big', 'heavy'],
  "total_work_time": total work duration available for this vehicle, 0 if all vehicles are the same,
  "total_work_days": total number of days this vehicle can work
}
c.vehicles_infos = vehicles_infos
c.max_iterations = max_iterations
c.distance_matrix = distance_matrix # provide distance matrix if any, otherwise flying distance will be used
```

Run clustering :

```
data_items = items.collect{ |i|
  i[:latitude],
  i[:longitude],
  i[:id],
  { "unit_1": i[:quantities]['unit_1'], "unit_2": i[:quantities]['unit_2'] },
  { "v_id": id of vehicle that should be assigned to this item if any,
    "skills": list of skills,
    "days": list of available days,
    "matrix_index": only if any matrix was provided
  }
}
cut_symbol = unit to use when balancig clusters
ratio = 1 by default, used to over/underestimate vehicles limits
c.build(DataSet.new(data_items: data_items), cut_symbol, ratio)```

cut_symbol is the referent unit to use when balancing clusters. This unit should exist in both vehicles_infos and data_items structures.
```

Get clusters back :

```
puts c.clusters.size # same same as vehicles_infos
clusters = c.clusters.collect{ |generated_cluster|
  generated_clusters.data_items.collect{ |item| item[2] } # item id
}
```

Items have same structure as data_items initially provided.

# Test

```
APP_ENV=test bundle exec rake test
```
