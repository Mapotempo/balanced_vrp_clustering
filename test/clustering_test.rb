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
    clusterer.vehicles_infos.first[:skills] = ['vehicle1']
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
    clusterer.vehicles_infos.first[:v_id] = ['vehicle1']
    data_items.data_items.find{ |item| item[2] == generated_clusters[0][0] }[4][:v_id] = ['vehicle1']
    data_items.data_items.find{ |item| item[2] == generated_clusters[1][0] }[4][:v_id] = ['vehicle1']

    clusterer.build(data_items, :visits)
    assert(clusterer.clusters.any?{ |cluster|
      cluster.data_items.any?{ |item| item[2] == generated_clusters[0][0] } &&
        cluster.data_items.any?{ |item| item[2] == generated_clusters[1][0] }
    })
  end

  def test_with_days
    clusterer, data_items = Instance.two_clusters_4_items

    clusterer.vehicles_infos.first[:days] = ['mon']
    data_items.data_items[0][4][:days] = ['mon']
    data_items.data_items[1][4][:days] = ['mon']
    expected = [data_items.data_items[0][2], data_items.data_items[1][2]]

    clusterer.build(data_items, :visits)
    assert(clusterer.clusters.any?{ |cluster|
      cluster.data_items.collect{ |item| item[2] } == expected
    })
  end
end
