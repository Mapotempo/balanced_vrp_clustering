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

class FunctionsTest < Minitest::Test
  include OverloadableFunctions

  def test_compatible_characteristics
    assert compatible_characteristics?({ v_id: [], skills: [], day_skills: ['all_days'] }, { id: [], skills: [], day_skills: ['all_days'] })

    # v_id
    refute compatible_characteristics?({ v_id: ['v1'], skills: [], day_skills: ['all_days'] }, { id: [], skills: [], day_skills: ['all_days'] })
    assert compatible_characteristics?({ v_id: ['v1'], skills: [], day_skills: ['all_days'] }, { id: ['v1'], skills: [], day_skills: ['all_days'] })
    assert compatible_characteristics?({ v_id: [], skills: [], day_skills: ['all_days'] }, { id: ['v1'], skills: [], day_skills: ['all_days'] })

    # skills
    refute compatible_characteristics?({ v_id: [], skills: ['sk1'], day_skills: ['all_days'] }, { id: [], skills: [], day_skills: ['all_days'] })
    assert compatible_characteristics?({ v_id: [], skills: ['sk1'], day_skills: ['all_days'] }, { id: [], skills: ['sk1'], day_skills: ['all_days'] })
    assert compatible_characteristics?({ v_id: [], skills: [], day_skills: ['all_days'] }, { id: [], skills: ['sk1'], day_skills: ['all_days'] })

    # days
    refute compatible_characteristics?({ v_id: [], skills: [], day_skills: ['other_days'] }, { id: [], skills: [], day_skills: ['all_days'] })
    refute compatible_characteristics?({ v_id: [], skills: [], day_skills: ['monday', 'tuesday'] }, { id: [], skills: [], day_skills: ['wednesday', 'thursday'] })
    assert compatible_characteristics?({ v_id: [], skills: [], day_skills: ['monday', 'tuesday'] }, { id: [], skills: [], day_skills: ['tuesday', 'thursday'] })
  end

  def test_compute_limits
    clusterer, data_set = Instance.two_clusters_4_items

    strict_limit, cut_limit = compute_limits(:visits, 1.0, clusterer.vehicles, data_set.data_items)
    clusterer.vehicles.size.times.each{ |cluster_index|
      assert_equal 0, strict_limit[cluster_index][:duration]
      assert_equal 6, strict_limit[cluster_index][:visits]
      assert_equal 2, cut_limit[:limit]
    }
  end

  def test_compute_limits_with_work_time
    clusterer, data_set = Instance.two_clusters_4_items
    clusterer.vehicles[0][:duration] = 1
    clusterer.vehicles[1][:duration] = 3

    strict_limit, cut_limit = compute_limits(:visits, 1.0, clusterer.vehicles, data_set.data_items)
    clusterer.vehicles.size.times.each{ |cluster_index|
      assert_equal clusterer.vehicles[cluster_index][:duration], strict_limit[cluster_index][:duration]
      assert_equal 6, strict_limit[cluster_index][:visits]
      assert_equal clusterer.vehicles[cluster_index][:duration], cut_limit[cluster_index][:limit]
    }
  end

  def test_use_provided_centroids
    clusterer, data_set = Instance.two_clusters_4_items

    clusterer.instance_variable_set(:@remaining_skills, clusterer.vehicles)
    clusterer.compatibility_function = lambda do |data_item, centroid|
      compatible_characteristics?(data_item[4], centroid[4])
    end

    clusterer.instance_variable_set(:@data_set, data_set)
    clusterer.instance_variable_set(:@number_of_clusters, 2)

    clusterer.centroid_indices = [0, 1]
    clusterer.send(:calc_initial_centroids)
    centroids = clusterer.instance_variable_get(:@centroids)
    assert_equal 2, centroids.size
    assert_equal ['point_1', 'point_2'], (centroids.collect{ |centroid| centroid[2] })
    assert_equal ['point_2', 'point_1', 'point_3', 'point_4'], (clusterer.data_set.data_items.collect{ |item| item[2] })
  end

  def test_check_centroids_validity
    clusterer, data_set = Instance.two_clusters_4_items

    clusterer.compatibility_function = lambda do |data_item, centroid|
      compatible_characteristics?(data_item[4], centroid[4])
    end

    clusterer.instance_variable_set(:@data_set, data_set)
    clusterer.instance_variable_set(:@number_of_clusters, 2)

    clusterer.centroid_indices = [0, 0]
    assert_raises ArgumentError do
      clusterer.send(:calc_initial_centroids)
    end

    clusterer.centroid_indices = [0]
    assert_raises ArgumentError do
      clusterer.send(:calc_initial_centroids)
    end

    clusterer.centroid_indices = [0, 1, 2]
    assert_raises ArgumentError do
      clusterer.send(:calc_initial_centroids)
    end

    clusterer.centroid_indices = ['0', 'a']
    assert_raises ArgumentError do
      clusterer.send(:calc_initial_centroids)
    end

    clusterer.centroid_indices = [10, 1]
    assert_raises ArgumentError do
      clusterer.send(:calc_initial_centroids)
    end

    # check expected_caracteristics and centroids skills are compatible
    clusterer.vehicles[1][:skills] << 'needs_vehicle_1'
    clusterer.instance_variable_set(:@remaining_skills, clusterer.vehicles)
    data_set.data_items[0][4][:skills] << 'needs_vehicle_1'
    clusterer.instance_variable_set(:@data_set, data_set)
    clusterer.centroid_indices = [0, 1]
    assert_raises ArgumentError do
      clusterer.send(:calc_initial_centroids)
    end
  end
end
