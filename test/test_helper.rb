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
ORIGINAL_VERBOSITY = $VERBOSE
$VERBOSE = nil if $VERBOSE && ENV['APP_ENV'] == 'test' # for suppressing the warnings of external libraries
require './lib/balanced_vrp_clustering'
$VERBOSE = ORIGINAL_VERBOSITY

require 'byebug'
require 'find'
require 'minitest/reporters'
Minitest::Reporters.use!
require 'minitest/around/unit'
require 'minitest/autorun'
require 'minitest/focus'
require 'minitest/retry'
require 'minitest/stub_any_instance'

include Ai4r::Data

class Tests < Minitest::Test
  def around
    @original_seed ||= Random::DEFAULT.seed
    yield
    srand @original_seed
  end
end

module Instance
  def self.load_clusterer(filepath)
    data_set, options, ratio = Marshal.load(File.binread(filepath))

    # to make the tests independently repeatable with the same minitest seed
    @callers ||= Hash.new(0)
    @seed ||= Random::DEFAULT.seed

    options[:seed] ||= @seed + @callers[caller[0] + filepath]
    @callers[caller[0] + filepath] += 1

    puts "seed #{options[:seed]}"

    options[:vehicles] ||= options.delete(:clusters_infos) || options.delete(:vehicles_infos) # deprecated

    Instance.compute_duration_from_and_to_depot(options[:vehicles], data_set, options[:distance_matrix]) # duration_from_and_to_depot moved to user side

    clusterer = Ai4r::Clusterers::BalancedVRPClustering.new
    clusterer.max_iterations = options[:max_iterations]
    clusterer.distance_matrix = options[:distance_matrix]
    clusterer.vehicles = options[:vehicles]
    clusterer.centroid_indices = options[:centroid_indices] || []

    [clusterer, data_set, options, ratio]
  end

  def self.compute_duration_from_and_to_depot(vehicles, data_set, matrix)
    # TODO: check if we always need duration_from_and_to_depot (even if the vehicles don't have a duration limit)

    return if data_set.data_items.all?{ |item| item[4][:duration_from_and_to_depot]&.size.to_f == vehicles.size }

    raise 'matrix is mandatory for automatic _duration_from_and_to_depot calculation' if matrix.nil? || matrix.empty? || matrix.any?{ |row| row.empty? }

    data_set.data_items.each{ |point| point[4][:duration_from_and_to_depot] = [] }

    vehicles.each{ |vehicle_info|
      single_index_array = [vehicle_info[:depot][:matrix_index]]
      point_indices = data_set.data_items.map{ |point| point[4][:matrix_index] }
      time_matrix_from_depot = Helper.unsquared_matrix(matrix, single_index_array, point_indices)
      time_matrix_to_depot = Helper.unsquared_matrix(matrix, point_indices, single_index_array)

      data_set.data_items.each_with_index{ |point, index|
        point[4][:duration_from_and_to_depot] << time_matrix_from_depot[0][index] + time_matrix_to_depot[index][0]
      }
    }
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
