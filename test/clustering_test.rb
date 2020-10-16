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

class ClusteringTest < Tests
  def test_basic_clustering
    clusterer, data_set = Instance.two_clusters_4_items
    clusterer.build(data_set, :visits)

    # right number of clusters generated
    assert_equal 2, clusterer.clusters.size
    # all items in a cluster
    assert_equal 4, clusterer.clusters.collect{ |cluster| cluster.data_items.size }.reduce(&:+)
    # no empty cluster
    refute_includes clusterer.clusters.collect{ |cluster| cluster.data_items.size }, 0
  end

  def test_basic_clustering_with_matrix
    clusterer, data_set = Instance.two_clusters_4_items_with_matrix
    clusterer.build(data_set, :visits)

    # right number of clusters generated
    assert_equal 2, clusterer.clusters.size
    # all items in a cluster
    assert_equal 4, clusterer.clusters.collect{ |cluster| cluster.data_items.size }.reduce(&:+)
    # no empty cluster
    refute_includes clusterer.clusters.collect{ |cluster| cluster.data_items.size }, 0
  end

  def test_with_skills
    clusterer, data_set = Instance.two_clusters_4_items
    clusterer.build(data_set, :visits)

    generated_clusters = clusterer.clusters.collect{ |c| c.data_items.collect{ |item| item[2] } }
    clusterer.vehicles.first[:skills] = ['vehicle1']
    data_set.data_items.find{ |item| item[2] == generated_clusters[0][0] }[4][:skills] = ['vehicle1']
    data_set.data_items.find{ |item| item[2] == generated_clusters[1][0] }[4][:skills] = ['vehicle1']

    clusterer.build(data_set, :visits)
    assert(clusterer.clusters.any?{ |cluster|
      cluster.data_items.any?{ |item| item[2] == generated_clusters[0][0] } &&
        cluster.data_items.any?{ |item| item[2] == generated_clusters[1][0] }
    })
  end

  def test_with_sticky
    clusterer, data_set = Instance.two_clusters_4_items
    clusterer.build(data_set, :visits)

    generated_clusters = clusterer.clusters.collect{ |c| c.data_items.collect{ |item| item[2] } }
    clusterer.vehicles.first[:id] = ['vehicle1']
    data_set.data_items.find{ |item| item[2] == generated_clusters[0][0] }[4][:v_id] = ['vehicle1']
    data_set.data_items.find{ |item| item[2] == generated_clusters[1][0] }[4][:v_id] = ['vehicle1']

    clusterer.build(data_set, :visits)
    assert(clusterer.clusters.any?{ |cluster|
      cluster.data_items.any?{ |item| item[2] == generated_clusters[0][0] } &&
        cluster.data_items.any?{ |item| item[2] == generated_clusters[1][0] }
    })
  end

  def test_with_output
    Dir.mktmpdir('temp_', 'test/') { |tmpdir|
      clusterer, data_set = Instance.two_clusters_4_items
      clusterer.geojson_dump_folder = tmpdir
      clusterer.build(data_set, :visits)
      refute_empty(Dir["#{tmpdir}/generated_cluster_*_iteration_*.geojson"], 'At least one geojson output should have been generated')
    }
  end

  def test_with_days
    clusterer, data_set = Instance.two_clusters_4_items

    clusterer.vehicles.first[:day_skills] = ['mon']
    data_set.data_items[0][4][:day_skills] = ['mon']
    data_set.data_items[1][4][:day_skills] = ['mon']
    expected = [data_set.data_items[0][2], data_set.data_items[1][2]].sort

    clusterer.build(data_set, :visits)
    assert(clusterer.clusters.any?{ |cluster|
      cluster.data_items.collect{ |item| item[2] }.sort == expected
    })
  end

  def test_infeasible_skills
    # the skills of the service does not exist in any of the vehicles
    clusterer, data_set, options, ratio = Instance.load_clusterer('test/fixtures/infeasible_skills.bindump')

    assert clusterer.build(data_set, options[:cut_symbol], ratio, options)
  end

  def test_division_by_nan
    clusterer, data_set, options, ratio = Instance.load_clusterer('test/fixtures/division_by_nan.bindump')
    # options[:seed] = 182581703914854297101438278871236808945

    assert clusterer.build(data_set, options[:cut_symbol], ratio, options)
  end

  def test_cluster_balance
    # from test_cluster_balance in optimizer-api project
    regularity_restart = 6
    balance_deviations = []
    (1..regularity_restart).each{ |trial|
      puts "Regularity trial: #{trial}/#{regularity_restart}"
      max_balance_deviation = 0

      clusterer, data_set, options, ratio = Instance.load_clusterer('test/fixtures/cluster_balance.bindump')

      # Remove vehicle capacities so that capacity is not the limiting factor.
      # Otherwise, checking the balance doesn't make sense beucase this is a dicho-type split.
      clusterer.vehicles.each{ |v_i|
        v_i.delete(:capacities)
        v_i[:duration] = 500000
      }

      while data_set.data_items.size > 100
        number_of_items_expected = data_set.data_items.size

        clusterer.build(data_set, options[:cut_symbol], ratio, options)

        repartition = clusterer.clusters.collect{ |c| c.data_items.size }
        puts "#{number_of_items_expected} items divided in into #{repartition}"

        # Check balance wrt total_duration not just service_duration
        service_durations = clusterer.clusters.collect{ |c| c.data_items.sum{ |item| item[3][:duration] } }
        route_times = clusterer.centroids.collect{ |c| c[4][:route_time] }
        depot_durations = clusterer.centroids.collect{ |c| c[4][:duration_from_and_to_depot] }
        total_durations = [0, 1].collect{ |i| service_durations[i] + route_times[i] + depot_durations[i] }

        assert_equal 2, clusterer.clusters.size, 'The number of clusters is not correct'
        assert_equal number_of_items_expected, repartition.sum, 'Some items are missing'
        assert_equal data_set.data_items.sum{ |i| i[3][:duration] }, service_durations.sum, 'The sum of service durations is not correct'
        assert_equal clusterer.centroids.collect{ |c| c[3][:duration] }, service_durations, 'Internal service duration statistics are not correct'

        max_balance_deviation = [max_balance_deviation, 1 - total_durations.min / total_durations.max].max

        data_set.data_items.delete_if{ |item| clusterer.clusters.first.data_items.none?{ |i| i[2] == item[2] } }
      end

      balance_deviations << max_balance_deviation
    }

    # TODO: fix the following statistics and limits
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
    clusterer, data_set, options, ratio = Instance.load_clusterer('test/fixtures/length_centroid.bindump')

    clusterer.build(data_set, options[:cut_symbol], ratio, options)

    assert_equal 2, clusterer.clusters.count{ |c| !c.data_items.empty? }, 'There are only 2 data_items, should have at most 2 non-empty clusters.'
  end

  def test_avoid_capacities_overlap
    # from test_avoid_capacities_overlap in optimizer-api project
    # depending on the seed, sometimes it doesn't pass -- 1 out of 10
    # it is because points with huge quantities which came last
    # TODO: we should handle these extreme cases better
    clusterer, data_set, options, ratio = Instance.load_clusterer('test/fixtures/avoid_capacities_overlap.bindump')

    clusterer.build(data_set, options[:cut_symbol], ratio, options)

    assert_equal 5, clusterer.clusters.count{ |c| !c.data_items.empty? }, 'There should be 5 non-empty clusters'

    %i[kg qte].each{ |unit|
      assert_operator clusterer.clusters.map.with_index.count{ |cluster, i|
        cluster.data_items.sum{ |item| item[3][unit] } > clusterer.vehicles[i][:capacities][unit]
      }, :<=, 1
    }
  end

end
