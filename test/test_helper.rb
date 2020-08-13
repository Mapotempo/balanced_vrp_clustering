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

ENV['APP_ENV'] ||= 'test'

require './lib/balanced_vrp_clustering'

require 'minitest/reporters'
Minitest::Reporters.use!
require 'minitest/autorun'
require 'minitest/stub_any_instance'
require 'minitest/focus'
require 'byebug'
require 'rack/test'
require 'find'

include Ai4r::Data

module Instance
  def self.load_clusterer(filepath)
    data_set, options, ratio = Marshal.load(File.binread(filepath))

    clusterer = Ai4r::Clusterers::BalancedVRPClustering.new
    clusterer.max_iterations = options[:max_iterations]
    clusterer.distance_matrix = options[:distance_matrix]
    clusterer.vehicles = options[:clusters_infos]
    clusterer.centroid_indices = options[:centroid_indices] || []

    [clusterer, data_set, options, ratio]
  end

  def self.two_clusters_4_items
    clusterer = Ai4r::Clusterers::BalancedVRPClustering.new
    clusterer.max_iterations = 300
    clusterer.vehicles = [
      {
        id: ['vehicle_0'],
        depot: {
          coordinates: [45.604784, 4.758965],
        },
        capacities: { visits: 6 },
        skills: [],
        day_skills: ['all_days'],
        duration: 0,
        total_work_days: 1
      }, {
        id: ['vehicle_1'],
        depot: {
          coordinates: [45.576412, 4.805614],
        },
        capacities: { visits: 6 },
        skills: [],
        day_skills: ['all_days'],
        duration: 0,
        total_work_days: 1
      }
    ]

    data_set = DataSet.new(data_items: [[45.604784, 4.758965, 'point_1', { visits: 1 }, { v_id: [], skills: [], day_skills: ['all_days'], duration_from_and_to_depot: [0.0, 4814.68] }],
                                        [45.344334, 4.817731, 'point_2', { visits: 1 }, { v_id: [], skills: [], day_skills: ['all_days'], duration_from_and_to_depot: [29354.21, 25852.47] }],
                                        [45.576412, 4.805614, 'point_3', { visits: 1 }, { v_id: [], skills: [], day_skills: ['all_days'], duration_from_and_to_depot: [4814.68, 0.0] }],
                                        [45.258324, 4.687322, 'point_4', { visits: 1 }, { v_id: [], skills: [], day_skills: ['all_days'], duration_from_and_to_depot: [38972.24, 36596.43] }]])

    [clusterer, data_set]
  end

  def self.two_clusters_4_items_with_matrix
    clusterer = Ai4r::Clusterers::BalancedVRPClustering.new
    clusterer.max_iterations = 300
    clusterer.distance_matrix = [
      [0, 2824, 1110, 2299, 1823],
      [2780, 0, 2132, 660, 2803],
      [1174, 2212, 0, 1687, 1248],
      [2349, 668, 1701, 0, 2372],
      [1863, 2865, 1240, 2340, 0]
    ]
    clusterer.vehicles = [
      {
        id: ['vehicle_0'],
        depot: {
          matrix_index: 0,
          coordinates: [45.604784, 4.758965]
        },
        capacities: { visits: 6 },
        skills: [],
        day_skills: ['all_days'],
        duration: 0,
        total_work_days: 1
      }, {
        id: ['vehicle_1'],
        depot: {
          matrix_index: 0,
          coordinates: [45.604784, 4.758965]
        },
        capacities: { visits: 6 },
        skills: [],
        day_skills: ['all_days'],
        duration: 0,
        total_work_days: 1
      }
    ]

    data_set = DataSet.new(data_items: [[45.604784, 4.758965, 'point_1', { visits: 1 }, { matrix_index: 1, v_id: [], skills: [], day_skills: ['all_days'], duration_from_and_to_depot: [2824, 2824] }],
                                        [45.344334, 4.817731, 'point_2', { visits: 1 }, { matrix_index: 2, v_id: [], skills: [], day_skills: ['all_days'], duration_from_and_to_depot: [1110, 1110] }],
                                        [45.576412, 4.805614, 'point_3', { visits: 1 }, { matrix_index: 3, v_id: [], skills: [], day_skills: ['all_days'], duration_from_and_to_depot: [2299, 2299] }],
                                        [45.258324, 4.687322, 'point_4', { visits: 1 }, { matrix_index: 4, v_id: [], skills: [], day_skills: ['all_days'], duration_from_and_to_depot: [1823, 1823] }]])

    [clusterer, data_set]
  end
end
