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

require 'rubygems'

require 'ai4r'

require 'helpers/helper.rb'
require 'concerns/overloadable_functions.rb'

module Ai4r
  module Clusterers
    class BalancedVRPClustering < KMeans
      include OverloadableFunctions

      attr_reader :iterations
      attr_reader :cut_limit

      parameters_info vehicles: 'Attributes of each cluster to generate. If centroid_indices are provided
                      then vehicles should be ordered according to centroid_indices order',
                      vehicles_infos: '(DEPRECATED) Use vehicles',
                      distance_matrix: 'Distance matrix to use to compute distance between two data_items',
                      compatibility_function: 'Custom implementation of a compatibility_function.'\
                        'It must be a closure receiving a data item and a centroid and return a '\
                        'boolean (true: if compatible and false: if incompatible).'

      def build(data_set, cut_symbol, cut_ratio = 1.0, options = {})
        # Build a new clusterer, using data items found in data_set.
        # Items will be clustered in "number_of_clusters" different
        # clusters. Each item is defined by :
        #    index 0 : latitude
        #    index 1 : longitude
        #    index 2 : item_id
        #    index 3 : unit_quantities -> for each unit, quantity associated to this item
        #    index 4 : characteristics -> { v_id: sticky_vehicle_ids, skills: skills, days: day_skills, matrix_index: matrix_index }

        # DEPRECATED variables (to be removed before public release)
        @vehicles ||= @vehicles_infos # (DEPRECATED)

        ### return clean errors if unconsistent data ###
        if cut_symbol && data_set.data_items.any?{ |item| item[3].nil? || !item[3].has_key?(cut_symbol) }
          raise ArgumentError, 'Cut symbol corresponding unit should be provided for all item'
        end

        ### values ###
        @data_set = data_set
        @cut_symbol = cut_symbol
        @unit_symbols = [cut_symbol]
        @unit_symbols |= @vehicles.collect{ |c| c[:capacities].keys }.flatten.uniq if @vehicles.any?{ |c| c[:capacities] }
        @number_of_clusters = [@vehicles.size, data_set.data_items.collect{ |data_item| [data_item[0], data_item[1]] }.uniq.size].min

        ### default values ###
        @max_iterations ||= [0.5 * @data_set.data_items.size, 100].max

        @distance_function ||= lambda do |a, b|
          if @distance_matrix
            @distance_matrix[a[4][:matrix_index]][b[4][:matrix_index]]
          else
            Helper.flying_distance(a, b)
          end
        end

        @compatibility_function ||= lambda do |data_item, centroid|
          if compatible_characteristics?(data_item[4], centroid[4])
            true
          else
            false
          end
        end

        @data_set.data_items.each{ |item|
          item[3].default = nil
          item[4].default = nil
          item[4][:v_id] ||= []
          item[4][:skills] ||= []
          item[4][:days] ||= %w[0_day_skill 1_day_skill 2_day_skill 3_day_skill 4_day_skill 5_day_skill 6_day_skill]
          item[3][:visits] ||= 1
        }

        @vehicles.each{ |vehicle_info|
          vehicle_info[:total_work_days] ||= 1
          vehicle_info[:skills] ||= []
          vehicle_info[:days] ||= %w[0_day_skill 1_day_skill 2_day_skill 3_day_skill 4_day_skill 5_day_skill 6_day_skill]
        }

        compute_distance_from_and_to_depot(@vehicles, @data_set, distance_matrix) if @cut_symbol == :duration
        @strict_limitations, @cut_limit = compute_limits(cut_symbol, cut_ratio, @vehicles, @data_set.data_items, options[:entity])
        @remaining_skills = @vehicles.dup

        @manage_empty_clusters_iterations = 0

        ### algo start ###
        @iteration = 0

        @i_like_to_move_it_move_it = []
        @moved_up = 0
        @moved_down = 0
        @clusters_with_capacity_violation = Array.new(@number_of_clusters){ [] }

        if @cut_symbol
          @total_cut_load = @data_set.data_items.inject(0) { |sum, d| sum + d[3][@cut_symbol].to_f }
          if @total_cut_load.zero?
            @cut_symbol = nil # Disable balancing because there is no point
          else
            @data_set.data_items.sort_by! { |x| -x[3][@cut_symbol].to_f }
            data_length = @data_set.data_items.size
            @data_set.data_items[(data_length * 0.1).to_i..(data_length * 0.90).to_i] = @data_set.data_items[(data_length * 0.1).to_i..(data_length * 0.90).to_i].shuffle!
          end
        end

        calc_initial_centroids

        @rate_balance = 0.0
        until stop_criteria_met || @iteration >= @max_iterations
          @rate_balance = 1.0 - (0.2 * @iteration / @max_iterations) if @cut_symbol

          update_cut_limit

          calculate_membership_clusters
          recompute_centroids
        end

        if options[:last_iteration_balance_rate] || options[:last_iteration_no_strict_limitations]
          @rate_balance = options[:last_iteration_balance_rate] if options[:last_iteration_balance_rate]
          @strict_limitations = [] if options[:last_iteration_no_strict_limitations]

          update_cut_limit

          calculate_membership_clusters
        end

        self
      end

      def move_capacity_violating_dataitems
        @needed_moving = @i_like_to_move_it_move_it.size
        mean_distance_diff = @i_like_to_move_it_move_it.collect{ |d| d[1] }.mean
        mean_ratio = @i_like_to_move_it_move_it.collect{ |d| d[2] }.mean

        @moved_down = 0
        @moved_up = 0

        # TODO: check if any other type of ordering might help
        # Since the last one that is moved up will appear at the very top and vice-versa for the down.
        # We need the most distant ones to closer to the top so that the cluster can move to that direction next iteration
        # but a random order might work better for the down ones since they are in the middle and the border is not a straight line
        # nothing vanilla order 9/34
        # @i_like_to_move_it_move_it.shuffle!  7/34 not much of help. it increases normal iteration count but decreases the loop time
        # @i_like_to_move_it_move_it.sort_by!{ |i| i[5] } 6/34 fails .. good
        # @i_like_to_move_it_move_it.sort_by!{ |i| -i[5] } 5/34 fails .. better
        # 0.33sort+ and 0.66sort-  #8/21 fails ... bad
        # 0.33shuffle and 0.66sort- #7/20 fails ... bad

        @i_like_to_move_it_move_it.sort_by!{ |i| -i[5] }

        until @i_like_to_move_it_move_it.empty? do
          data = @i_like_to_move_it_move_it.pop

          # TODO: check the effectiveness of the following stochastic condition.
          # Specifically, moving the "up" ones always would be better...?
          # But the downs are the really problematic ones so moving them would make sense too.
          # Tested some options but it looks alright as it is.. Needs more testing.

          # if the capacity violation leads to more than 2-5 times increase, move it
          # otherwise, move it with a probability correlated to the detour it generated
          if data[2] > [2 * mean_ratio.to_f, 5].min || rand < (data[1] / (3 * mean_distance_diff + 1e-10))
            point = data[0][0..1]
            centroid_with_violation = @centroids[data[3]][0..1]
            centroid_witout_violation = @centroids[data[4]][0..1]
            if Helper.check_if_projection_inside_the_line_segment(point, centroid_with_violation, centroid_witout_violation, 0.1)
              @moved_down += 1
              data[0][3][:moved_down] = true
              @data_set.data_items.insert(@data_set.data_items.size - 1, @data_set.data_items.delete(data[0]))
            else
              @moved_up += 1
              data[0][3][:moved_up] = true
              @data_set.data_items.insert(0, @data_set.data_items.delete(data[0]))
            end
          end
        end
        # puts "#{@needed_moving} \tpoints needs love, #{@moved_down} of them moved_down, #{@moved_up} of them moved_up, #{@needed_moving - @moved_down - @moved_up} of them untouched \tviolations=#{@clusters_with_capacity_violation.collect.with_index{ |array, i| array.empty? ? ' _ ' : "|#{i + 1}|" }.join(' ')}"
      end

      def recompute_centroids
        move_capacity_violating_dataitems

        @old_centroids_lat_lon = @centroids.collect{ |centroid| [centroid[0], centroid[1]] }

        centroid_smoothing_coeff = 0.1 + 0.9 * (@iteration / @max_iterations.to_f)**0.5

        @centroids.each_with_index{ |centroid, index|
          # Smooth the centroid movement (and keeps track of the "history") with the previous centroid (to prevent erratic jumps)
          # Calculates the new centroid with weighted mean (using the number of visits and distance to current centroid as a weight)
          # That's what matters the most (how many times we have to go to a zone an how far this zone is)
          total_weighted_visit_distance = 0
          @clusters[index].data_items.each{ |d_i|
            d_i[3][:weighted_visit_distance] = if d_i[3][:moved_up]
                                                 d_i[3][:visits] * 0.1 * Helper.flying_distance(centroid, d_i) + 1e-10
                                               elsif d_i[3][:moved_down]
                                                 d_i[3][:visits] * 10 * Helper.flying_distance(centroid, d_i) + 1e-10
                                               else
                                                 d_i[3][:visits] * Helper.flying_distance(centroid, d_i) + 1e-10
                                               end
            d_i[3][:moved_up] = d_i[3][:moved_down] = nil
            total_weighted_visit_distance += d_i[3][:weighted_visit_distance]
          }
          centroid[0] = centroid_smoothing_coeff * centroid[0] + (1.0 - centroid_smoothing_coeff) * @clusters[index].data_items.sum{ |d_i| d_i[0] * d_i[3][:weighted_visit_distance] } / total_weighted_visit_distance.to_f
          centroid[1] = centroid_smoothing_coeff * centroid[1] + (1.0 - centroid_smoothing_coeff) * @clusters[index].data_items.sum{ |d_i| d_i[1] * d_i[3][:weighted_visit_distance] } / total_weighted_visit_distance.to_f

          # A selector which selects closest point to represent the centroid which is the most "representative" in terms of distace to the
          point_closest_to_centroid_center = clusters[index].data_items.min_by([[(@clusters[index].data_items.size / 10.0).ceil, 5].min, 2].max){ |data_point|
            Helper.flying_distance(centroid, data_point)
          }.min_by{ |data_point|
            clusters[index].data_items.sum{ |d_i| @distance_function.call(data_point, d_i) * d_i[3][:visits] } # / total_visits_in_cluster.to_f
          }

          # register the id and matrix_index of the point representing the centroid
          centroid[2] = point_closest_to_centroid_center[2].dup # id TODO: Check if dup necessary ?
          # correct the matrix_index of the centroid with the index of the point_closest_to_centroid_center
          centroid[4][:matrix_index] = point_closest_to_centroid_center[4][:matrix_index] if centroid[4][:matrix_index]

          next unless @cut_symbol

          # move the data_points closest to the centroid centers to the top of the data_items list so that balancing can start early
          @data_set.data_items.insert(0, @data_set.data_items.delete(point_closest_to_centroid_center))

          # correct the distance_from_and_to_depot info of the new cluster with the average of the points
          if centroid[4][:duration_from_and_to_depot]
            centroid[4][:duration_from_and_to_depot] = @clusters[index].data_items.map{ |d| d[4][:duration_from_and_to_depot] }.reduce(&:+) / @clusters[index].data_items.size.to_f
          end
        }

        swap_a_centroid_with_capacity_problems

        @iteration += 1
      end

      def swap_a_centroid_with_capacity_problems
        @clusters_with_capacity_violation.map.with_index.sort_by{ |arr, _i| -arr.size }.each{ |preferred_clusters, violated_cluster|
          break if preferred_clusters.empty?

          # TODO: elimination/determination of units per cluster should be done at the beginning
          # Each centroid should know what matters to them.
          the_units_that_matter = @centroids[violated_cluster][3].select{ |i, v| i && v.positive? }.keys & @strict_limitations[violated_cluster].select{ |i, v| i && v}.keys

          # TODO: only consider the clusters that are "compatible" with this cluster -- i.e., they can serve the points of this cluster and vice-versa
          favorite_clusters = @centroids.map.with_index.select{ |c, i|
            the_units_that_matter.all?{ |unit| # cluster to be swapped should
              c[3][unit] < 0.99 * @strict_limitations[violated_cluster][unit] && # be less loaded
                @strict_limitations[i][unit] >= 1.01 * @centroids[violated_cluster][3][unit] && # have more capacity
                @clusters[violated_cluster].data_items.all?{ |d_i| @compatibility_function.call(d_i, @centroids[i]) } &&
                @clusters[i].data_items.all?{ |d_i| @compatibility_function.call(d_i, @centroids[violated_cluster]) }
            } # and they should be able to serve eachothers's points
          }

          if favorite_clusters.empty?
            # puts "cannot swap #{violated_cluster + 1} because no one can save it"
            next
          end

          favorite_cluster = favorite_clusters.min_by{ |c, i|
            the_units_that_matter.sum{ |unit| c[3][unit].to_f / @strict_limitations[i][unit] * (rand(0.90) + 0.1) } # give others some chance with randomness
          }[1]

          swap_safe = @centroids[violated_cluster][0..2] # lat lon point_id
          @centroids[violated_cluster][0..2] = @centroids[favorite_cluster][0..2]
          @centroids[favorite_cluster][0..2] = swap_safe

          # puts "swapped #{violated_cluster + 1} with #{favorite_cluster + 1}"
          break # swap only one at a time
        }

        @clusters_with_capacity_violation.each(&:clear)
      end

      # Classifies the given data item, returning the cluster index it belongs
      # to (0-based).
      def evaluate(data_item)
        distances = @centroids.collect.with_index{ |centroid, cluster_index|
          dist = distance(data_item, centroid, cluster_index)

          dist += 2**32 unless @compatibility_function.call(data_item, centroid)

          dist
        }

        closest_cluster_index = get_min_index(distances)

        if capactity_violation?(data_item, closest_cluster_index)
          mininimum_without_capacity_violation = 2**32 # only consider compatible ones
          closest_cluster_wo_violation_index = nil
          @number_of_clusters.times{ |k|
            next unless distances[k] < mininimum_without_capacity_violation &&
                        !capactity_violation?(data_item, k)

            closest_cluster_wo_violation_index = k
            mininimum_without_capacity_violation = distances[k]
          }
          if closest_cluster_wo_violation_index
            @clusters_with_capacity_violation[closest_cluster_index] << closest_cluster_wo_violation_index
            mininimum_with_capacity_violation = distances.min
            @i_like_to_move_it_move_it << [data_item, mininimum_without_capacity_violation - mininimum_with_capacity_violation, mininimum_without_capacity_violation / mininimum_with_capacity_violation, closest_cluster_index, closest_cluster_wo_violation_index, mininimum_with_capacity_violation]
            closest_cluster_index = closest_cluster_wo_violation_index
          end
        end

        closest_cluster_index
      end

      protected

      def distance(data_item, centroid, cluster_index)
        # TODO: Move extra logic outside of the distance function.
        # The user should be able to overload 'distance' function witoud losing any functionality
        distance = @distance_function.call(data_item, centroid)

        cut_value = @centroids[cluster_index][3][@cut_symbol].to_f
        limit = if @cut_limit.is_a? Array
                  @cut_limit[cluster_index][:limit]
                else
                  @cut_limit[:limit]
                end

        # balance between clusters computation
        balance = 1.0
        if @apply_balancing
          # At this "stage" of the clustering we would expect this limit to be met
          expected_cut_limit = limit * @percent_assigned_cut_load
          # Compare "expected_cut_limit to the current cut_value
          # and penalize (or favorise) if cut_value/expected_cut_limit greater (or less) than 1.
          balance = if @percent_assigned_cut_load < 0.95
                      # First down-play the effect of balance (i.e., **power < 1)
                      # After then make it more pronounced (i.e., **power > 1)
                      (cut_value / expected_cut_limit)**((2 + @rate_balance) * @percent_assigned_cut_load)
                    else
                      # If at the end of the clustering, do not take the power
                      (cut_value / expected_cut_limit)
                    end
        end

        if @rate_balance
          (1.0 - @rate_balance) * distance + @rate_balance * distance * balance
        else
          distance * balance
        end
      end

      def calculate_membership_clusters
        @centroids.each{ |centroid| centroid[3] = Hash.new(0) }
        @clusters = Array.new(@number_of_clusters) do
          Ai4r::Data::DataSet.new data_labels: @data_set.data_labels
        end
        @cluster_indices = Array.new(@number_of_clusters){ [] }

        @total_assigned_cut_load = 0
        @percent_assigned_cut_load = 0
        @apply_balancing = false
        @data_set.data_items.each{ |data_item|
          cluster_index = evaluate(data_item)
          @clusters[cluster_index] << data_item
          update_metrics(data_item, cluster_index)
        }

        manage_empty_clusters if has_empty_cluster?
      end

      def calc_initial_centroids
        @centroids, @old_centroids_lat_lon = [], nil
        if @centroid_indices.empty?
          populate_centroids('random')
        else
          populate_centroids('indices')
        end
      end

      def populate_centroids(populate_method, number_of_clusters = @number_of_clusters)
        # Generate centroids based on remaining_skills available
        # Similarly with data_items, each centroid is defined by :
        #    index 0 : latitude
        #    index 1 : longitude
        #    index 2 : item_id
        #    index 3 : unit_fullfillment -> for each unit, quantity contained in corresponding cluster
        #    index 4 : characterisits -> { v_id: sticky_vehicle_ids, skills: skills, days: day_skills, matrix_index: matrix_index }
        raise ArgumentError, 'No vehicles provided' if @remaining_skills.nil?

        case populate_method
        when 'random'
          while @centroids.length < number_of_clusters
            skills = @remaining_skills.shift

            # Find the items which are not already used, and specifically need the skill set of this cluster
            compatible_items = @data_set.data_items.select{ |item|
              !@centroids.collect{ |centroid| centroid[2] }.flatten.include?(item[2]) &&
                !item[4].empty? &&
                !(item[4][:v_id].empty? && item[4][:skills].empty?) &&
                @compatibility_function.call(item, [0, 0, 0, 0, skills, 0])
            }

            if compatible_items.empty?
              # If there are no items which specifically needs these skills,
              # then find all the items that can be assigned to this cluster
              compatible_items = @data_set.data_items.select{ |item|
                !@centroids.collect{ |centroid| centroid[2] }.flatten.include?(item[2]) &&
                  @compatibility_function.call(item, [0, 0, 0, 0, skills, 0])
              }
            end

            if compatible_items.empty?
              # If, still, there are no items that can be assigned to this cluster
              # initialize it with a random point
              compatible_items = @data_set.data_items.reject{ |item|
                @centroids.collect{ |centroid| centroid[2] }.flatten.include?(item[2])
              }
            end

            item = compatible_items[rand(compatible_items.size)]

            skills[:matrix_index] = item[4][:matrix_index]
            skills[:duration_from_and_to_depot] = item[4][:duration_from_and_to_depot]
            @centroids << [item[0], item[1], item[2], Hash.new(0), skills]

            @data_set.data_items.insert(0, @data_set.data_items.delete(item))
          end
        when 'indices' # for initial assignment only (with the :centroid_indices option)
          raise ArgumentError, 'Same centroid_index provided several times' if @centroid_indices.size != @centroid_indices.uniq.size

          raise ArgumentError, 'Wrong number of initial centroids provided' if @centroid_indices.size != @number_of_clusters

          insert_at_begining = []
          @centroid_indices.each do |index|
            raise ArgumentError, 'Invalid centroid index' unless (index.is_a? Integer) && index >= 0 && index < @data_set.data_items.length

            skills = @remaining_skills.shift
            item = @data_set.data_items[index]
            raise ArgumentError, 'Centroids indices and vehicles do not match' unless @compatibility_function.call(item, [nil, nil, nil, nil, skills])

            skills[:matrix_index] = item[4][:matrix_index]
            skills[:duration_from_and_to_depot] = item[4][:duration_from_and_to_depot]
            @centroids << [item[0], item[1], item[2], Hash.new(0), skills]

            insert_at_begining << item
          end

          insert_at_begining.each{ |i|
            @data_set.data_items.insert(0, @data_set.data_items.delete(i))
          }
        end
        @number_of_clusters = @centroids.length
      end

      def manage_empty_clusters
        @manage_empty_clusters_iterations += 1
        return if self.on_empty == 'terminate' # Do nothing to terminate with error. (The empty cluster will be assigned a nil centroid, and then calculating the distance from this centroid to another point will raise an exception.)

        initial_number_of_clusters = @number_of_clusters
        if @manage_empty_clusters_iterations < @data_set.data_items.size * 2
          eliminate_empty_clusters
        else
          # try generating all clusters again
          @clusters, @centroids, @cluster_indices = [], [], []
          @remaining_skills = @vehicles.dup
          @number_of_clusters = @centroids.length
        end
        return if self.on_empty == 'eliminate'

        populate_centroids(self.on_empty, initial_number_of_clusters) # Add initial_number_of_clusters - @number_of_clusters
        calculate_membership_clusters
        @manage_empty_clusters_iterations = 0
      end

      def eliminate_empty_clusters
        old_clusters, old_centroids, old_cluster_indices = @clusters, @centroids, @cluster_indices
        @clusters, @centroids, @cluster_indices = [], [], []
        @remaining_skills = []
        @number_of_clusters.times do |i|
          if old_clusters[i].data_items.empty?
            @remaining_skills << old_centroids[i][4]
          else
            @clusters << old_clusters[i]
            @cluster_indices << old_cluster_indices[i]
            @centroids << old_centroids[i]
          end
        end
        @number_of_clusters = @centroids.length
      end

      def stop_criteria_met
        centroids_converged_or_in_loop(Math.sqrt(@iteration).to_i) && # This check should stay first since it keeps track of the centroid movements..
          @needed_moving.zero? # Do not converge if there were decision due to capacity violation.
      end

      private

      def compute_vehicle_work_time_with
        coef = @centroids.map.with_index{ |centroid, index|
          @vehicles[index][:total_work_time] / ([centroid[4][:duration_from_and_to_depot], 1].max * @vehicles[index][:total_work_days])
        }.min

        # TODO: The following filter is there to not to affect the existing functionality.
        # However, we should improve the functioanlity and make it less arbitrary.
        coef = if coef > 1.5
                 1.5
               elsif coef > 1.0
                 1.0
               else
                 coef * 0.9 # To make sure the limit will not become 0.
               end

        @centroids.map.with_index{ |centroid, index|
          @vehicles[index][:total_work_time] - coef * centroid[4][:duration_from_and_to_depot] * @vehicles[index][:total_work_days]
        }
      end

      def update_cut_limit
        return if @rate_balance == 0.0 || @cut_symbol.nil? || @cut_symbol != :duration || !@cut_limit.is_a?(Array)

        # TODO: This functionality is implemented only for duration cut_symbol. Make sure it doesn't interfere with other cut_symbols
        vehicle_work_time = compute_vehicle_work_time_with
        total_vehicle_work_times = vehicle_work_time.reduce(&:+).to_f
        @centroids.size.times{ |index|
          @cut_limit[index][:limit] = @total_cut_load * vehicle_work_time[index] / total_vehicle_work_times
        }
      end

      def centroids_converged_or_in_loop(last_n_iterations)
        # Checks if there is a loop of size last_n_iterations
        if @iteration.zero?
          # Initialize the array stats array
          @last_n_average_diffs = [0.0] * (2 * last_n_iterations + 1)
          return false
        end

        # Calculate total absolute centroid movement in meters
        total_movement_meter = 0
        @number_of_clusters.times { |i|
          total_movement_meter += Helper.euclidean_distance(@old_centroids_lat_lon[i], @centroids[i])
        }

        # If convereged, we can stop
        return true if total_movement_meter < @number_of_clusters * 10

        @last_n_average_diffs.push total_movement_meter.to_f

        # Check if there is a centroid loop of size n
        (1..last_n_iterations).each{ |n|
          last_n_iter_average_curr = @last_n_average_diffs[-n..-1].reduce(:+)
          last_n_iter_average_prev = @last_n_average_diffs[-(n + n)..-(1 + n)].reduce(:+)

          # If we make exact same moves again and again, we can stop
          return true if (last_n_iter_average_curr - last_n_iter_average_prev).abs < 1e-5
        }

        # Clean old stats
        @last_n_average_diffs.shift if @last_n_average_diffs.size > (2 * last_n_iterations + 1)

        false
      end

      def update_metrics(data_item, cluster_index)
        @unit_symbols.each{ |unit|
          @centroids[cluster_index][3][unit] += data_item[3][unit].to_f
          next if unit != @cut_symbol

          @total_assigned_cut_load += data_item[3][unit].to_f
          @percent_assigned_cut_load = @total_assigned_cut_load / @total_cut_load.to_f
          if !@apply_balancing && @centroids.all?{ |centroid| centroid[3][@cut_symbol].positive? }
            @apply_balancing = true
          end
        }
      end

      def capactity_violation?(item, cluster_index)
        return false if @strict_limitations.empty?

        @centroids[cluster_index][3].any?{ |unit, value|
          @strict_limitations[cluster_index][unit] && (value + item[3][unit].to_f > @strict_limitations[cluster_index][unit])
        }
      end
    end
  end
end
