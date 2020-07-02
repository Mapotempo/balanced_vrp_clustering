# Copyright © Mapotempo, 2020
#
# This file is part of Mapotempo.
#
# Mapotempo is free software. You can redistribute it and/or
# modify since you respect the terms of the GNU Affero General
# Public License as published by the Free Software Foundation,
# either version 3 of the License, or (at your option) any later version.
#
# Mapotempo is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY
# or FITNESS FOR A PARTICULAR PURPOSE.  See the Licenses for more details.
#
# You should have received a copy of the GNU Affero General Public License
# along with Mapotempo. If not, see:
# <http://www.gnu.org/licenses/agpl.html>
#
require './test/test_helper'

class ClusteringTest < Minitest::Test
  def test_basic_clustering
    clusterer, data_items = Instance.two_clusters_4_items
    clusterer.build(data_items, :visits)

    # right number of clusters generated
    assert_equal 2, clusterer.clusters.size
    # all items in a cluster
    assert_equal 4, clusterer.clusters.collect{ |cluster| cluster.data_items.size }.reduce(&:+)
    # no empty cluster
    refute_includes clusterer.clusters.collect{ |cluster| cluster.data_items.size }, 0
  end

  def test_basic_clustering_with_matrix
    clusterer, data_items = Instance.two_clusters_4_items_with_matrix
    clusterer.build(data_items, :visits)

    # right number of clusters generated
    assert_equal 2, clusterer.clusters.size
    # all items in a cluster
    assert_equal 4, clusterer.clusters.collect{ |cluster| cluster.data_items.size }.reduce(&:+)
    # no empty cluster
    refute_includes clusterer.clusters.collect{ |cluster| cluster.data_items.size }, 0
  end

  def test_with_skills
    clusterer, data_items = Instance.two_clusters_4_items
    clusterer.build(data_items, :visits)

    generated_clusters = clusterer.clusters.collect{ |c| c.data_items.collect{ |item| item[2] } }
    clusterer.vehicles.first[:skills] = ['vehicle1']
    data_items.data_items.find{ |item| item[2] == generated_clusters[0][0] }[4][:skills] = ['vehicle1']
    data_items.data_items.find{ |item| item[2] == generated_clusters[1][0] }[4][:skills] = ['vehicle1']

    clusterer.build(data_items, :visits)
    assert(clusterer.clusters.any?{ |cluster|
      cluster.data_items.any?{ |item| item[2] == generated_clusters[0][0] } &&
        cluster.data_items.any?{ |item| item[2] == generated_clusters[1][0] }
    })
  end

  def test_with_sticky
    clusterer, data_items = Instance.two_clusters_4_items
    clusterer.build(data_items, :visits)

    generated_clusters = clusterer.clusters.collect{ |c| c.data_items.collect{ |item| item[2] } }
    clusterer.vehicles.first[:v_id] = ['vehicle1']
    data_items.data_items.find{ |item| item[2] == generated_clusters[0][0] }[4][:v_id] = ['vehicle1']
    data_items.data_items.find{ |item| item[2] == generated_clusters[1][0] }[4][:v_id] = ['vehicle1']

    clusterer.build(data_items, :visits)
    assert(clusterer.clusters.any?{ |cluster|
      cluster.data_items.any?{ |item| item[2] == generated_clusters[0][0] } &&
        cluster.data_items.any?{ |item| item[2] == generated_clusters[1][0] }
    })
  end

  def test_with_output
    Dir.mktmpdir('temp_', 'test/') { |tmpdir|
      clusterer, data_items = Instance.two_clusters_4_items
      clusterer.geojson_dump_folder = tmpdir
      clusterer.build(data_items, :visits)
      refute_empty(Dir["#{tmpdir}/generated_cluster_*_iteration_*.geojson"], 'At least one geojson output should have been generated')
    }
  end

  def test_with_days
    clusterer, data_items = Instance.two_clusters_4_items

    clusterer.vehicles.first[:days] = ['mon']
    data_items.data_items[0][4][:days] = ['mon']
    data_items.data_items[1][4][:days] = ['mon']
    expected = [data_items.data_items[0][2], data_items.data_items[1][2]].sort

    clusterer.build(data_items, :visits)
    assert(clusterer.clusters.any?{ |cluster|
      cluster.data_items.collect{ |item| item[2] }.sort == expected
    })
  end

  def test_infeasible_skills
    # the skills of the service does not exist in any of the vehicles
    data_set, options, ratio = Marshal.load(File.binread('test/fixtures/infeasible_skills.bindump'))

    clusterer = Ai4r::Clusterers::BalancedVRPClustering.new
    clusterer.max_iterations = options[:max_iterations]
    clusterer.distance_matrix = options[:distance_matrix]
    clusterer.vehicles = options[:clusters_infos]

    assert clusterer.build(data_set, options[:cut_symbol], ratio, options)
  end

  def test_division_by_nan
    data_set, options, ratio = Marshal.load(File.binread('test/fixtures/division_by_nan.bindump'))
    # options[:seed] = 182581703914854297101438278871236808945

    clusterer = Ai4r::Clusterers::BalancedVRPClustering.new
    clusterer.max_iterations = options[:max_iterations]
    clusterer.distance_matrix = options[:distance_matrix]
    clusterer.vehicles = options[:clusters_infos]
    clusterer.centroid_indices = options[:centroid_indices] || []

    assert clusterer.build(data_set, options[:cut_symbol], ratio, options)
  end

  def test_cluster_balance
    # from test_cluster_balance in optimizer-api project
    regularity_restart = 6
    balance_deviations = []
    (1..regularity_restart).each{ |trial|
      puts "Regularity trial: #{trial}/#{regularity_restart}"
      max_balance_deviation = 0

      data_set, options, ratio = Marshal.load(File.binread('test/fixtures/cluster_balance.bindump'))
      units = data_set.data_items.collect{ |i| i[3].keys }.flatten.uniq

      clusterer = Ai4r::Clusterers::BalancedVRPClustering.new
      clusterer.max_iterations = options[:max_iterations]
      clusterer.distance_matrix = options[:distance_matrix]
      clusterer.vehicles = options[:clusters_infos]

      while data_set.data_items.size > 100
        number_of_items_expected = data_set.data_items.size

        total_load_by_units = Hash.new(0)
        data_set.data_items.each{ |item| item[3].each{ |unit, quantity| total_load_by_units[unit] += quantity if units.include? unit} }
        # Adapt each vehicle capacity according to items to clusterize
        clusterer.vehicles.each{ |v_i|
          v_i[:capacities] = {}
          total_load_by_units.collect{ |unit, quantity|
            v_i[:capacities][unit] = quantity * 0.65
          }
        }

        clusterer.build(data_set, options[:cut_symbol], ratio, entity: :vehicle)

        repartition = clusterer.clusters.collect{ |c| c.data_items.size }
        puts "#{number_of_items_expected} items divided in into #{repartition}"
        durations = clusterer.clusters.collect{ |c| c.data_items.collect{ |item| item[3][:duration] }.reduce(&:+) }

        assert_equal 2, clusterer.clusters.size, 'The number of clusters is not correct'
        assert_equal number_of_items_expected, repartition.reduce(&:+), 'Some items are missing'
        assert_equal data_set.data_items.collect{ |i| i[3][:duration] }.reduce(&:+), durations.reduce(&:+), 'The sum of service durations is not correct'

        max_balance_deviation = [max_balance_deviation, durations.max.to_f / durations.reduce(&:+) * 2 - 1].max

        data_set.data_items.delete_if{ |item| clusterer.clusters.first.data_items.none?{ |i| i[2] == item[2] } }
      end

      balance_deviations << max_balance_deviation
    }

    # The limits of max_dev and the RHS of the asserts represent the current performance of the clustering algorighm.
    # The limit values are tightest possible to ensure that any degredation would trip the assert.
    # False negative are rare, once every ~10 runs on local and once every ~30 runs on Travis.
    # That is, if the test fails there probably is a performance degredation.
    asserts = [
      {
        condition: balance_deviations.count{ |max_dev| max_dev > 0.25 } <= (regularity_restart * 0.02).ceil,
        message: 'The maximum balance deviation can be larger than 25% only very rarely -- <2% of the trials.'
      }, {
        condition: balance_deviations.count{ |max_dev| max_dev > 0.21 } <= (regularity_restart * 0.20).ceil,
        message: 'The maximum balance deviation sould not be larger than 21% for more than 20% of the trials.'
      }, {
        condition: balance_deviations.count{ |max_dev| max_dev > 0.185 } <= (regularity_restart * 0.35).ceil,
        message: 'The maximum balance deviation sould not be larger than 18.5% for more than 35% of the trials.'
      }, {
        condition: balance_deviations.count{ |max_dev| max_dev <= 0.165 } >= (regularity_restart * 0.45).floor,
        message: 'The maximum balance deviation sould be less than 16.5% most of the time -- >45% of the trials.'
      }
    ]

    puts balance_deviations.collect{ |i| i.round(3) }.sort.join(', ') if asserts.any?{ |assert| !assert[:condition] }

    asserts.each { |check| assert check[:condition], check[:message] }
  end

  def test_length_centroid
    # from test_length_centroid in optimizer-api project
    # more vehicles than data_items..
    data_set, options, ratio = Marshal.load(File.binread('test/fixtures/length_centroid.bindump'))

    clusterer = Ai4r::Clusterers::BalancedVRPClustering.new
    clusterer.max_iterations = options[:max_iterations]
    clusterer.distance_matrix = options[:distance_matrix]
    clusterer.vehicles = options[:clusters_infos]

    clusterer.build(data_set, options[:cut_symbol], ratio, options)
    clusterer.clusters.delete([])

    assert_equal 2, clusterer.clusters.size
  end

  def test_avoid_capacities_overlap
    # from test_avoid_capacities_overlap in optimizer-api project
    # depending on the seed, sometimes it doesn't pass -- 1 out of 10
    data_items, options, ratio = Marshal.load(File.binread('test/fixtures/avoid_capacities_overlap.bindump'))

    clusterer = Ai4r::Clusterers::BalancedVRPClustering.new
    clusterer.max_iterations = options[:max_iterations]
    clusterer.distance_matrix = options[:distance_matrix]
    clusterer.vehicles = options[:clusters_infos]

    clusterer.build(DataSet.new(data_items: data_items), options[:cut_symbol], ratio, options)
    clusterer.clusters.delete([])

    assert_equal 5, clusterer.clusters.size

    %i[kg qte].each{ |unit|
      assert_operator clusterer.clusters.map.with_index.count{ |cluster, i|
        cluster.data_items.sum{ |item| item[3][unit] } > clusterer.vehicles[i][:capacities][unit]
      }, :<=, 1
    }
  end

end
