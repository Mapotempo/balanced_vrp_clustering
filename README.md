# About Balanced VRP Clustering

This gem aims to help you solving your Vehicle Routing Problems by generating one sub-problem per vehicle. It is an adaptation of kmeans algorithm (based ok ai4r library : https://github.com/SergioFierens/ai4r), including notions of balance.

# Gem generation (for contributors)

Within gem project use
```gem build balanced_vrp_clustering.gemspec``` and ```gem install balanced_vrp_clustering``` to generate gem.

# Including gem in your own ruby project

In your Gemfile :

```gem 'balanced_vrp_clustering'```

In your ruby script :

```require 'balanced_vrp_clustering'```

# Calling gem for clustering

Initialize your clusterer tool c :

```c = Ai4r::Clusterers::BalancedVRPClustering.new```

Provide maximum iterations and expected caracteristics of your clusters :

```c.max_iterations = max_iterations```
```c.vehicles_infos = vehicles_infos```
vehicles_infos should be an array of hashes. Each hash should include following keys :
- v_id (vehicle id),
- days (list of day skills i.e. 'monday', 'tuesday'...),
- depot (when matrix is provided, indice of depot in matrix, otherwise [latitude, longiture] of vehicle depot)
- capacities (hash with key is unit and value is limit)
- skills (list of skills i.e. 'big', 'heavy'...),
- total_work_time (total work duration available for this vehicle, 0 if all vehicles are the same),
- total_work_days (total number of days this vehicle can work)

Provide your distance matrix if any, otherwise flying distance will be used :

```c.distance_matrix = distance_matrix```

Run clustering :

```c.build(DataSet.new(data_items: data_items), cut_symbol, ratio)```

data_items should be an array of arrays with following data :
- latitude
- longitude
- item id
- unit_quantities (hash where key is unit, value is quantity associated to this item)
- characteristics (hash with following keys : v_id, skills, days, matrix_index. v_id is the id of vehicle that has to be assigned to this item. matrix_index should be provided only if matrix was provided).
cut_symbol is the referent unit to use when balancing clusters. This unit should exist in both vehicles_infos and data_items structures.
ratio is by default 1, it is used to over/underestimate vehicles limits.

Get clusters back :

Each element of c.clusters (same size as vehicles_infos) has field data_items which is an array of all item in this cluster.
Items have same structure as data_items initially provided.