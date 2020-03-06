# About Balanced VRP Clustering

This gem aims to help you solving your Vehicle Routing Problems by generating one sub-problem per vehicle and/or workable day. It is an adaptation of kmeans algorithm, including notions of balance.

# Gem generation (for contributors)

Within gem project use 
```gem build balanced_vrp_clustering.gemspec``` and ```gem install balanced_vrp_clustering``` to generate gem.

# Including gem in your own ruby project

In your Gemfile : 

```gem 'balanced_vrp_clustering'```

In your ruby script : 

```require 'balanced_vrp_clustering'```
