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
require 'active_support'
require 'active_support/core_ext'

require 'ai4r'

require 'helpers/helper.rb'
require 'concerns/overloadable_functions.rb'

# for geojson dump
require 'helpers/hull.rb'
require 'color-generator'
require 'geojson2image'

INCOMPATIBILITY_DISTANCE_PENALTY = 2**32

module Ai4r
  module Clusterers
    class BalancedVRPClustering < KMeans
      LINKING_RELATIONS = %i[order same_route sequence same_vehicle shipment].freeze
      BINDING_RELATIONS = %i[order same_route sequence same_vehicle].freeze

      include OverloadableFunctions

      attr_reader :iteration
      attr_reader :cut_limit

      parameters_info vehicles: 'Attributes of each cluster to generate. If centroid_indices are provided
                      then vehicles should be ordered according to centroid_indices order',
                      vehicles_infos: '(DEPRECATED) Use vehicles',
                      logger: 'The logger to write the output. All written to logger.debug at the moment.',
                      geojson_dump_folder: 'If set, every geojson_dump_freq many iterations,'\
                        'the geojson will be dumped to geojson_dump_folder.',
                      geojson_dump_freq: 'Sets the frequency for geojson dump. (Default: 2)',
                      distance_matrix: 'Distance matrix to use to compute distance between two data_items',
                      compatibility_function: 'Custom implementation of a compatibility_function.'\
                        'It must be a closure receiving a data item and a centroid and return a '\
                        'boolean (true: if compatible and false: if incompatible).',
                      on_empty: '(DEPRECATED) the only possible option is \'closest\''\
                        ' -- i.e., relocate the empty cluster to the closest compatible point.'

      def initialize
        super
        @logger ||= nil
        @distance_matrix ||= nil
        @unit_symbols ||= nil
        @geojson_colors ||= nil
        @on_empty = 'closest' # the other options are not available
      end

      def build(data_set, cut_symbol, related_item_indices = {}, cut_ratio = 1.0, options = {})
        # Build a new clusterer, using data items found in data_set.
        # Items will be clustered in "number_of_clusters" different
        # clusters. Each item is defined by :
        #    index 0 : latitude
        #    index 1 : longitude
        #    index 2 : item_id
        #    index 3 : unit_quantities -> for each unit, quantity associated to this item
        #    index 4 : characteristics -> { v_id: sticky_vehicle_ids, skills: skills, day_skills: day_skills, matrix_index: matrix_index }

        # First of all, set and display the seed
        options[:seed] ||= Random.new_seed
        @logger&.info "Clustering with seed=#{options[:seed]}"
        srand options[:seed]

        # DEPRECATED variables (to be removed before public release)
        @vehicles ||= @vehicles_infos # (DEPRECATED)

        raise ArgumentError, 'Each data_item should be uniq' if data_set.data_items.size != data_set.data_items.uniq.size

        ### return clean errors if inconsistent data ###
        if distance_matrix && data_set.data_items.any?{ |item| !item[4][:matrix_index] }
          raise ArgumentError, 'Distance matrix provided: matrix index should be provided for all vehicles and items'
        end

        if data_set.data_items.any?{ |item| item[4][:duration_from_and_to_depot]&.size != @vehicles.size }
          raise ArgumentError, 'duration_from_and_to_depot should be provided for all data items'
        end

        if data_set.data_items.any?{ |item| !(item[0] && item[1]) }
          raise ArgumentError, 'Location info (lattitude and longitude) should be provided for all items'
        end

        unless @on_empty == 'closest'
          raise ArgumentError, 'Only \'closest\' option is supported for :on_empty parameter'
        end

        if cut_symbol && !@vehicles.all?{ |v_i| v_i[:capacities]&.has_key?(cut_symbol) || (cut_symbol == :duration && v_i[:duration]) }
          # TODO: remove this condition and handle the infinity capacities properly.
          raise ArgumentError, 'All vehicles should have a limit for the unit corresponding to the cut symbol'
        end

        connect_linked_items(data_set.data_items, related_item_indices)

        ### values ###
        @data_set = data_set
        @cut_symbol = cut_symbol
        @unit_symbols = [cut_symbol].compact
        @unit_symbols |= @vehicles.collect{ |c| c[:capacities].keys }.flatten.uniq if @vehicles.any?{ |c| c[:capacities] }
        @number_of_clusters = @vehicles.size

        ### default values ###
        @logger ||= nil
        @geojson_dump_folder ||= nil
        @geojson_dump_freq ||= 2
        @max_balance_violation = 0
        @max_iterations ||= [0.5 * @data_set.data_items.size, 100].max

        @distance_function ||= lambda do |a, b|
          if @distance_matrix
            [@distance_matrix[a[4][:matrix_index]][b[4][:matrix_index]], @distance_matrix[b[4][:matrix_index]][a[4][:matrix_index]]].min
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
          item[4][:day_skills] ||= %w[0_day_skill 1_day_skill 2_day_skill 3_day_skill 4_day_skill 5_day_skill 6_day_skill]
          item[3][:visits] ||= 1
          item[4][:centroid_weights] = {
            limit: Array.new(@number_of_clusters, 1),
            compatibility: 1
          }
        }

        @vehicles.each{ |vehicle_info|
          vehicle_info[:id] = [vehicle_info[:id]].flatten if vehicle_info[:id]
          vehicle_info[:total_work_days] ||= 1
          vehicle_info[:skills] ||= []
          vehicle_info[:day_skills] ||= %w[0_day_skill 1_day_skill 2_day_skill 3_day_skill 4_day_skill 5_day_skill 6_day_skill]
          vehicle_info[:vehicle_count] ||= 1
        }

        # Initialise the [:centroid_weights][:compatibility] of data_items which need specifique vehicles
        # These weights are increased if the data_item is not assigned to its closest clusters due to incompatibility
        compatibility_groups = Hash.new{ [] }
        @data_set.data_items.group_by{ |d_i| [d_i[4][:v_id], d_i[4][:skills], d_i[4][:day_skills]] }.each{ |_skills, group|
          compatibility_groups[@vehicles.collect{ |vehicle_info| @compatibility_function.call(group[0], [nil, nil, nil, nil, vehicle_info]) ? 1 : 0 }] += group
        }
        @expected_n_visits = @data_set.data_items.sum{ |d_i| d_i[3][:visits] } / @number_of_clusters.to_f
        compatibility_groups.each{ |compatibility, group|
          compatible_vehicle_count = [compatibility.sum, 1].max
          incompatible_vehicle_count = @vehicles.size - compatible_vehicle_count

          compatibility_weight = (@expected_n_visits**((1.0 + Math.log(incompatible_vehicle_count / @vehicles.size.to_f + 0.1)) / (1.0 + Math.log(1.1)))) / [group.size / compatible_vehicle_count, 1.0].max

          group.each{ |d_i| d_i[4][:centroid_weights][:compatibility] = compatibility_weight.ceil }
        }

        @strict_limitations, @cut_limit = compute_limits(cut_symbol, cut_ratio, @vehicles, @data_set.data_items)

        ### algo start ###
        @iteration = 0

        @items_with_limit_violation = []
        @clusters_with_limit_violation = Array.new(@number_of_clusters){ [] }

        @balance_coeff = Array.new(@number_of_clusters, 1.0)

        calc_initial_centroids

        if @cut_symbol
          @total_cut_load = @data_set.data_items.inject(0) { |sum, d| sum + d[3][@cut_symbol].to_f }
          if @total_cut_load.zero?
            @cut_symbol = nil # Disable balancing because there is no point
          else
            # first @centroids.length data_items correspond to centroids, they should remain at the begining of the set
            data_length = @data_set.data_items.size
            @data_set.data_items[[@centroids.length, data_length].min..-1] = @data_set.data_items[[@centroids.length, data_length].min..-1].sort_by { |x| -x[3][@cut_symbol].to_f }
            range_end = (data_length * 0.9).to_i
            range_begin = [(@centroids.length + data_length * 0.1).to_i, range_end].min
            @data_set.data_items[range_begin..range_end] = @data_set.data_items[range_begin..range_end].shuffle

            @density_cap = Float::EPSILON # used for speed approximation
            @density_range_ratio = 6
            @density_speed_conversion_power = 6

            calculate_local_speeds # if we want to use route_time for capacity_checks this needs to taken out of the if block

            area_per_cluster = Helper.approximate_polygon_area(Helper.approximate_quadrilateral_polygon(@data_set.data_items)) / @vehicles.size.to_f
            speed = @data_set.data_items.collect{ |i| i[4][:local_speed] }.mean
            visit_count_per_cluster = @data_set.data_items.sum{ |i| i[3][:visits] } / @vehicles.size.to_f
            total_work_days_per_cluster = @vehicles.sum{ |v| v[:total_work_days] } / @vehicles.size.to_f

            @approximate_total_route_time = Helper.compute_approximate_route_time(area_per_cluster, visit_count_per_cluster, speed, total_work_days_per_cluster) * @vehicles.size
          end
        end

        mark_the_items_which_needs_to_stay_at_the_top

        until stop_criteria_met || @iteration >= @max_iterations
          calculate_membership_clusters

          output_cluster_geojson if @iteration.modulo(@geojson_dump_freq).zero?

          update_balance_coefficients

          recompute_centroids
        end

        Helper.output_cluster_stats(@centroids, @logger)

        output_cluster_geojson

        self
      end

      def connect_linked_items(data_items, related_item_indices)
        (LINKING_RELATIONS | BINDING_RELATIONS).each{ |relation|
          related_item_indices[relation]&.each{ |linked_indices|
            raise ArgumentError, 'Each relation group of related_item_indices should contain only unique indices' unless linked_indices.uniq.size == linked_indices.size
          }
        }

        (LINKING_RELATIONS - BINDING_RELATIONS).each{ |relation|
          related_item_indices[relation]&.each{ |linked_indices|
            raise ArgumentError, 'A service should not appear in multiple non-binding linking relations' if linked_indices.any?{ |ind| data_items[ind][4].key?(:linked_item) }

            linked_indices << linked_indices.first # create a loop
            (linked_indices.size - 1).times{ |i|
              item = data_items[linked_indices[i]]
              next_item = data_items[linked_indices[i + 1]]
              item[4][:linked_item] = next_item
            }
          }
        }

        BINDING_RELATIONS.each{ |relation|
          related_item_indices[relation]&.each{ |linked_indices|
            linked_indices << linked_indices.first # create a loop
            (linked_indices.size - 1).times{ |i|
              item = data_items[linked_indices[i]]
              next_item = data_items[linked_indices[i + 1]]
              if !item[4].key?(:linked_item) && !next_item[4].key?(:linked_item)
                item[4][:linked_item] = next_item
              elsif item[4].key?(:linked_item) && next_item[4].key?(:linked_item)
                # either there are two loops to join together or these items are already connected via loop
                first_loop_end = item
                item = item[4][:linked_item] while [first_loop_end, next_item].exclude? item[4][:linked_item]
                next if item[4][:linked_item] == next_item # connected via loop, nothing to do

                second_loop_end = next_item
                next_item = next_item[4][:linked_item] while next_item[4][:linked_item] != second_loop_end

                item[4][:linked_item] = second_loop_end
                next_item[4][:linked_item] = first_loop_end
              else
                next_item, item = item, next_item if item[4].key?(:linked_item)
                item[4][:linked_item] = next_item
                loop_end = next_item
                next_item = next_item[4][:linked_item] while next_item[4][:linked_item] != loop_end
                next_item[4][:linked_item] = item unless next_item == item
              end
            }
          }
        }
      end

      def move_limit_violating_dataitems
        @limit_violation_count = @items_with_limit_violation.size
        mean_distance_diff = @items_with_limit_violation.collect{ |d| d[1] }.mean
        mean_ratio = @items_with_limit_violation.collect{ |d| d[2] }.mean

        moved_down = 0
        moved_up = 0

        # TODO: check if any other type of ordering might help
        # Since the last one that is moved up will appear at the very top and vice-versa for the down.
        # We need the most distant ones to closer to the top so that the cluster can move to that direction next iteration
        # but a random order might work better for the down ones since they are in the middle and the border is not a straight line
        # nothing vanilla order 9/34
        # @items_with_limit_violation.shuffle!  7/34 not much of help. it increases normal iteration count but decreases the loop time
        # @items_with_limit_violation.sort_by!{ |i| i[5] } 6/34 fails .. good
        # @items_with_limit_violation.sort_by!{ |i| -i[5] } 5/34 fails .. better
        # 0.33sort+ and 0.66sort-  #8/21 fails ... bad
        # 0.33shuffle and 0.66sort- #7/20 fails ... bad

        @items_with_limit_violation.sort_by!{ |i| -i[5] }

        until @items_with_limit_violation.empty? do
          data = @items_with_limit_violation.pop

          # TODO: check the effectiveness of the following stochastic condition.
          # Specifically, moving the "up" ones always would be better...?
          # But the downs are the really problematic ones so moving them would make sense too.
          # Tested some options but it looks alright as it is.. Needs more testing.

          # if the limt violation leads to more than 2-5 times distance increase, move it
          # otherwise, move it with a probability correlated to the detour it generates
          if !data[0][4][:needs_to_stay_at_the_top] && (data[2] > [2 * mean_ratio.to_f, 5].min || rand < (data[1] / (3 * mean_distance_diff + 1e-10)))
            point = data[0][0..1]
            centroid_with_violation = @centroids[data[3]][0..1]
            centroid_witout_violation = data[4] && @centroids[data[4]][0..1]
            if centroid_witout_violation && Helper.check_if_projection_inside_the_line_segment(point, centroid_with_violation, centroid_witout_violation, 0.1)
              moved_down += 1
              data[0][4][:moved_down] = true
              data[0][4][:centroid_weights][:limit].collect!{ |w| [w * 2, [@expected_n_visits / 10, 5].max].min } # TODO: a better mechanism ?
              data[0][4][:centroid_weights][:limit][data[3]] = 1
              @data_set.data_items.insert(@data_set.data_items.size - 1, @data_set.data_items.delete(data[0]))
            else
              moved_up += 1
              data[0][4][:moved_up] = true if centroid_witout_violation
              @data_set.data_items.insert(@needs_to_stay_at_the_top, @data_set.data_items.delete(data[0]))
            end
          end
        end
        if @limit_violation_count.positive?
          @logger&.debug "Decisions taken due to capacity violation for #{@limit_violation_count} items: #{moved_down} of them moved_down, #{moved_up} of them moved_up, #{@limit_violation_count - moved_down - moved_up} of them untouched"
          @logger&.debug "#{@clusters_with_limit_violation.count(&:any?)} clusters have limit violation (order): #{@clusters_with_limit_violation.collect.with_index{ |array, i| array.empty? ? ' _ ' : "|#{i + 1}|" }.join(' ')}" if @number_of_clusters <= 10
          @logger&.debug "#{@clusters_with_limit_violation.count(&:any?)} clusters have limit violation (index): #{@clusters_with_limit_violation.collect.with_index{ |array, i| array.empty? ? nil : i}.compact.join(', ')}" if @number_of_clusters > 10
        end
      end

      def recompute_centroids
        move_limit_violating_dataitems

        @old_centroids_lat_lon = @centroids.collect{ |centroid| [centroid[0], centroid[1]] }

        centroid_smoothing_coeff = 0.1 + 0.9 * (@iteration / @max_iterations.to_f)**0.5

        @centroids.each_with_index{ |centroid, index|
          next if @clusters[index].data_items.empty?

          # Smooth the centroid movement (and keeps track of the "history") with the previous centroid (to prevent erratic jumps)
          # Calculates the new centroid with weighted mean (using the number of visits and distance to current centroid as a weight)
          # That's what matters the most (how many times we have to go to a zone an how far this zone is)
          total_weighted_visit_distance = 0
          @clusters[index].data_items.each{ |d_i|
            distance_weight = if d_i[4][:moved_up]
                                0.1
                              elsif d_i[4][:moved_down]
                                10
                              else
                                1
                              end

            d_i[4][:weighted_visit_distance] = distance_weight * (Helper.flying_distance(centroid, d_i) + 1)**0.2 * d_i[3][:visits]**0.2 * d_i[4][:centroid_weights][:compatibility] * d_i[4][:centroid_weights][:limit][index]
            d_i[4][:moved_up] = d_i[4][:moved_down] = nil
            total_weighted_visit_distance += d_i[4][:weighted_visit_distance]
          }
          centroid[0] = centroid_smoothing_coeff * centroid[0] + (1.0 - centroid_smoothing_coeff) * @clusters[index].data_items.sum{ |d_i| d_i[0] * d_i[4][:weighted_visit_distance] } / total_weighted_visit_distance.to_f
          centroid[1] = centroid_smoothing_coeff * centroid[1] + (1.0 - centroid_smoothing_coeff) * @clusters[index].data_items.sum{ |d_i| d_i[1] * d_i[4][:weighted_visit_distance] } / total_weighted_visit_distance.to_f

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

          # correct the distance_from_and_to_depot info of the new cluster with the average of the points
          centroid[4][:duration_from_and_to_depot] = @clusters[index].data_items.map{ |d| d[4][:duration_from_and_to_depot][index] }.reduce(&:+) / @clusters[index].data_items.size.to_f if centroid[4][:duration_from_and_to_depot]
        }

        swap_a_centroid_with_limit_violation

        @iteration += 1
      end

      def swap_a_centroid_with_limit_violation
        already_swapped_a_centroid = false
        @clusters_with_limit_violation.map.with_index.sort_by{ |arr, _i| -arr.size }.each{ |preferred_clusters, violated_cluster|
          if preferred_clusters.empty?
            @centroids[violated_cluster][4][:capacity_offence_coeff] -= 0.3 if @centroids[violated_cluster][4][:capacity_offence_coeff] > 0.3
            next
          end

          # TODO: elimination/determination of units per cluster should be done at the beginning
          # Each centroid should know what matters to them.
          the_units_that_matter = @centroids[violated_cluster][3].select{ |i, v| i && v.positive? }.keys & @strict_limitations[violated_cluster].select{ |i, v| i && v }.keys

          # TODO: only consider the clusters that are "compatible" with this cluster -- i.e., they can serve the points of this cluster and vice-versa
          favorite_clusters = @centroids.map.with_index.select{ |c, _i|
            the_units_that_matter.any?{ |unit|
              limit = c[4][:capacities][unit]
              !@centroids[violated_cluster][4][:capacities][unit].nil? && (limit.nil? || limit > @centroids[violated_cluster][4][:capacities][unit])
            }
          }.select{ |c, i|
            clusters_can_be_swapped = the_units_that_matter.all?{ |unit| # cluster to be swapped should
              (@strict_limitations[violated_cluster][unit].nil? || c[3][unit] < 0.98 * @strict_limitations[violated_cluster][unit]) && # be less loaded
                (@strict_limitations[i][unit].nil? || @strict_limitations[i][unit] >= 1.02 * @centroids[violated_cluster][3][unit]) && # have more limit
                @clusters[violated_cluster].data_items.all?{ |d_i| @compatibility_function.call(d_i, @centroids[i]) } &&
                @clusters[i].data_items.all?{ |d_i| @compatibility_function.call(d_i, @centroids[violated_cluster]) }
            } # and they should be able to serve eachothers's points

            next unless clusters_can_be_swapped

            # check if swapping the centroids is okay from multi-depot point of view
            violated_duration_from_and_to_depot = @clusters[violated_cluster].data_items.sum{ |d| d[4][:duration_from_and_to_depot][i] } / @clusters[violated_cluster].data_items.size.to_f
            favorite_duration_from_and_to_depot = @clusters[i].data_items.sum{ |d| d[4][:duration_from_and_to_depot][violated_cluster] } / @clusters[i].data_items.size.to_f

            (violated_duration_from_and_to_depot < @centroids[violated_cluster][4][:duration_from_and_to_depot] ||
              favorite_duration_from_and_to_depot < @centroids[i][4][:duration_from_and_to_depot]) ||
              (violated_duration_from_and_to_depot < 2 * @centroids[violated_cluster][4][:duration_from_and_to_depot] &&
                favorite_duration_from_and_to_depot < 2 * @centroids[i][4][:duration_from_and_to_depot])
          }

          if favorite_clusters.empty?
            @logger&.debug "cannot swap #{violated_cluster + 1}th cluster due compatibility, increasing its balance_coeff"
            @balance_coeff[violated_cluster] /= 0.95 # increase the coefficient of the violated cluster

            @centroids[violated_cluster][4][:capacity_offence_coeff] += 1

            # TODO: this coefficient can be made dependent to
            # the number of times this cluster refused an item
            # or the total "load" of all rejected items
            # or the item that has the smallest items_with_limit_violation[3] (ratio)...
            # and a coeff that makes sure that this cluster will not be the closest in the next itration
            next
          end

          next if already_swapped_a_centroid

          favorite_cluster = favorite_clusters.min_by{ |c, index|
            the_units_that_matter.sum{ |unit|
              if @strict_limitations[index][unit].nil?
                0
              else
                # give others some chance with randomness
                c[3][unit].to_f / @strict_limitations[index][unit] * (rand(0.90) + 0.1)
              end
            }
          }[1] # index of the minimum

          # TODO: we need to understand why the folling if condition happens:
          # It is probably due to missing units in capacity -- which lead to
          # the same point "rejected" by every cluster and this
          # makes them get labeled "violated"
          next if favorite_cluster == violated_cluster

          swap_safe = [
            @centroids[violated_cluster][0..2],
            @centroids[violated_cluster][4][:matrix_index],
            @centroids[violated_cluster][4][:duration_from_and_to_depot],
            @balance_coeff[violated_cluster]
          ] # lat lon point_id and matrix_index duration_from_and_to_depot if exists

          @centroids[violated_cluster][0..2] = @centroids[favorite_cluster][0..2]
          @centroids[violated_cluster][4][:matrix_index] = @centroids[favorite_cluster][4][:matrix_index]
          @centroids[violated_cluster][4][:duration_from_and_to_depot] = @centroids[favorite_cluster][4][:duration_from_and_to_depot]
          @balance_coeff[violated_cluster] = @balance_coeff[favorite_cluster]

          @centroids[favorite_cluster][0..2] = swap_safe[0]
          @centroids[favorite_cluster][4][:matrix_index] = swap_safe[1]
          @centroids[favorite_cluster][4][:duration_from_and_to_depot] = swap_safe[2]
          @balance_coeff[favorite_cluster] = swap_safe[3]

          @logger&.debug "swapped location of #{violated_cluster + 1}th cluster with #{favorite_cluster + 1}th cluster"
          already_swapped_a_centroid = true # break # swap only one at a time
        }

        @clusters_with_limit_violation.each(&:clear)
      end

      # Classifies the given data item, returning the cluster index it belongs
      # to (0-based).
      def evaluate(data_item)
        distances = @centroids.collect.with_index{ |centroid, cluster_index|
          dist = distance(data_item, centroid, cluster_index)

          dist += INCOMPATIBILITY_DISTANCE_PENALTY unless @compatibility_function.call(data_item, centroid)

          dist
        }

        closest_cluster_index = get_min_index(distances)

        if capactity_violation?(data_item, closest_cluster_index)
          mininimum_without_limit_violation = INCOMPATIBILITY_DISTANCE_PENALTY # only consider compatible ones
          closest_cluster_wo_violation_index = nil
          @number_of_clusters.times{ |k|
            next unless distances[k] < mininimum_without_limit_violation &&
                        !capactity_violation?(data_item, k)

            closest_cluster_wo_violation_index = k
            mininimum_without_limit_violation = distances[k]
          }

          if closest_cluster_wo_violation_index
            mininimum_with_limit_violation = distances.min
            diff = mininimum_without_limit_violation - mininimum_with_limit_violation
            ratio = mininimum_without_limit_violation / mininimum_with_limit_violation
            ratio = 1 if ratio.to_f.nan?

            @items_with_limit_violation << [data_item, diff, ratio, closest_cluster_index, closest_cluster_wo_violation_index, mininimum_with_limit_violation]

            @clusters_with_limit_violation[closest_cluster_index] << closest_cluster_wo_violation_index
            closest_cluster_index = closest_cluster_wo_violation_index
          end
        end

        closest_cluster_index
      end

      protected

      def distance(data_item, centroid, cluster_index)
        total_dist = 0

        do_forall_linked_items_of(data_item){ |linked_item| total_dist += @distance_function.call(linked_item, centroid) }

        total_dist * @balance_coeff[cluster_index]
      end

      def calculate_membership_clusters
        update_strict_duration_limitation_wrt_depot

        @centroids.each{ |centroid| centroid[3] = Hash.new(0) }
        @clusters = Array.new(@number_of_clusters) do
          Ai4r::Data::DataSet.new data_labels: @data_set.data_labels
        end

        @already_assigned = Hash.new{ |h, k| h[k] = false }

        @data_set.data_items.each{ |data_item|
          next if @already_assigned[data_item] # another item with a relation handled this item

          cluster_index = evaluate(data_item)

          do_forall_linked_items_of(data_item){ |linked_item|
            assign_item(linked_item, cluster_index)
            update_metrics(linked_item, cluster_index)
          }
        }

        manage_empty_clusters
      end

      def assign_item(data_item, cluster_index)
        @already_assigned[data_item] = true
        @clusters[cluster_index] << data_item
      end

      def calc_initial_centroids
        @centroids, @old_centroids_lat_lon, @remaining_skills = [], nil, @vehicles.dup
        if @centroid_indices.empty?
          populate_centroids('random')
        else
          populate_centroids('indices')
        end
        @centroids.each{ |c|
          c[4][:capacity_offence_coeff] = 0
          c[4][:route_time] = 0
        }
      end

      def populate_centroids(populate_method, number_of_clusters = @number_of_clusters)
        # Generate centroids based on remaining_skills available
        # Similarly with data_items, each centroid is defined by :
        #    index 0 : latitude
        #    index 1 : longitude
        #    index 2 : item_id
        #    index 3 : unit_fullfillment -> for each unit, quantity contained in corresponding cluster
        #    index 4 : characterisits -> { v_id: sticky_vehicle_ids, skills: skills, day_skills: day_skills, matrix_index: matrix_index }
        raise ArgumentError, 'No vehicles provided' if @remaining_skills.nil?

        case populate_method
        when 'random'
          while @centroids.length < number_of_clusters
            available_items ||= @data_set.data_items.dup # get a new container object

            skills = @remaining_skills.shift

            # Select from the items which are not already used which
            # specifically need the skill set of this cluster
            # Prefer items whom closest depot corresponds to current cluster.
            items_to_consider = available_items.select{ |item|
              !item[4].empty? &&
                !(item[4][:v_id].empty? && item[4][:skills].empty?) &&
                @compatibility_function.call(item, [0, 0, 0, 0, skills, 0])
            }
            compatible_items = compatible_items_multi_depot_selector(items_to_consider)

            # If there are no items which specifically needs these skills,
            # then find all the items that can be assigned to this cluster.
            # Prefer items whom closest depot corresponds to current cluster.
            if compatible_items.empty?
              items_to_consider = available_items.select{ |item|
                @compatibility_function.call(item, [0, 0, 0, 0, skills, 0])
              }
              compatible_items = compatible_items_multi_depot_selector(items_to_consider)
            end

            # If, still, there are no items that can be assigned to this cluster
            # initialize it with a random point
            # Prefer items whom closest depot corresponds to current cluster.
            compatible_items = compatible_items_multi_depot_selector(available_items) if compatible_items.empty?

            # If, still empty (!) there are more clusters then items so
            # initialize it at a random point
            compatible_items = compatible_items_multi_depot_selector(@data_set.data_items) if compatible_items.empty?

            item = compatible_items[rand(compatible_items.size)]

            skills[:matrix_index] = item[4][:matrix_index]
            skills[:duration_from_and_to_depot] = item[4][:duration_from_and_to_depot][@centroids.length]
            @centroids << [item[0], item[1], item[2], Hash.new(0), skills]

            do_forall_linked_items_of(item){ |linked_item| available_items.delete(linked_item) }

            @data_set.data_items.insert(0, @data_set.data_items.delete(item))
          end
        when 'indices' # for initial assignment only (with the :centroid_indices option)
          raise ArgumentError, 'Same centroid_index provided several times' if @centroid_indices.size != @centroid_indices.uniq.size

          raise ArgumentError, 'Wrong number of initial centroids provided' if @centroid_indices.size != @number_of_clusters

          insert_at_begining = []
          @centroid_indices.each_with_index do |index, ind|
            raise ArgumentError, 'Invalid centroid index' unless (index.is_a? Integer) && index >= 0 && index < @data_set.data_items.length

            skills = @remaining_skills.shift
            item = @data_set.data_items[index]

            # check if linked data items are assigned to different centroids
            do_forall_linked_items_of(item){ |linked_item|
              msg = "Centroid #{ind} is initialised with a service which has a linked service that is used to initialise centroid #{insert_at_begining.index(linked_item)}"
              raise ArgumentError, msg if insert_at_begining.include?(linked_item)
            }

            raise ArgumentError, "Centroid #{ind} is initialised with an incompatible service -- #{index}" unless @compatibility_function.call(item, [nil, nil, nil, nil, skills])

            skills[:matrix_index] = item[4][:matrix_index]
            skills[:duration_from_and_to_depot] = item[4][:duration_from_and_to_depot][@centroids.length]
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
        return unless has_empty_cluster?

        @clusters.each_with_index{ |empty_cluster, ind|
          next unless empty_cluster.data_items.empty?

          empty_centroid = @centroids[ind]

          distances = @clusters.collect{ |cluster|
            next unless cluster.data_items.size > 1

            min_distance = Float::INFINITY

            closest_item = cluster.data_items.select{ |d_i|
              @compatibility_function.call(d_i, empty_centroid)
            }.min_by{ |d_i|
              total_dist = 0

              do_forall_linked_items_of(d_i){ |linked_item| total_dist += @distance_function.call(linked_item, empty_centroid) }

              min_distance = [total_dist, min_distance].min

              total_dist
            }
            next if closest_item.nil?

            [min_distance, closest_item, cluster]
          }

          closest = distances.min_by{ |d| d.nil? ? Float::INFINITY : d[0] }

          next if closest.nil?

          do_forall_linked_items_of(closest[1]){ |linked_item| empty_cluster.data_items << closest[2].data_items.delete(linked_item) }
        }
      end

      def stop_criteria_met
        centroids_converged_or_in_loop(Math.sqrt(@iteration).to_i) && # This check should stay first since it keeps track of the centroid movements..
          @limit_violation_count.zero? && # Do not converge if a decision is taken due to limit violation.
          @max_balance_violation.to_f <= 0.05 + (@iteration.to_f / @max_iterations)**8
      end

      private

      def calculate_local_speeds
        # TODO: Following speed approximation is not efficient, needs to be improved
        # TODO: Following speed approximation is done with respect to a fixed depot
        # (first one) it needs to be generalised to multi-depot case...
        # (maybe with max_by over duration or min_by over calculated speed)
        # TODO: check the effect of 100 in min_by(100), if decreasing it improves the speed approximation or the performance

        local_max_speed = 60 / 3.6 # meters per second
        local_min_speed = 5 / 3.6 # meters per second

        @data_set.data_items.each{ |a|
          a[4][:local_speed] ||= # [[calculated_speed, local_min_speed].max, local_max_speed].min
            [
              [
                @data_set.data_items.select{ |b|
                  (a[4][:duration_from_and_to_depot][0] - b[4][:duration_from_and_to_depot][0]).abs > 1 && Helper.flying_distance(a, b) > 5
                }.min_by(100){ |b|
                  Helper.flying_distance(a, b)
                }.collect{ |b|
                  Helper.flying_distance(a, b) / (a[4][:duration_from_and_to_depot][0] - b[4][:duration_from_and_to_depot][0]).abs # m/s (eucledian)
                }.min(2).sum * 1.1, # duration_from_and_to_depot is two-way, instead of multiplication with 2, take the sum of the first two
                local_min_speed
              ].max,
              local_max_speed
            ].min
        }
      end

      def do_forall_linked_items_of(item)
        linked_item = nil
        until linked_item == item
          linked_item = (linked_item && linked_item[4][:linked_item]) || item[4][:linked_item] || item
          yield(linked_item)
        end
      end

      def mark_the_items_which_needs_to_stay_at_the_top
        @data_set.data_items.each{ |i| i[4][:needs_to_stay_at_the_top] = false }
        @vehicles.flat_map{ |c| c[:capacities].keys }.uniq.each{ |unit|
          @data_set.data_items.max_by(@data_set.data_items.size * 0.005 + 1){ |i| i[3][unit].to_f }.each{ |data_item|
            data_item[4][:needs_to_stay_at_the_top] = true if data_item[3][unit]
          }
        }
        @needs_to_stay_at_the_top = @data_set.data_items.count{ |i| i[4][:needs_to_stay_at_the_top] }

        @data_set.data_items.select{ |i| i[4][:needs_to_stay_at_the_top] }.each{ |item|
          @data_set.data_items.insert(0, @data_set.data_items.delete(item))
        }
      end

      def updated_visit_densities
        # n_visits/m^2
        @centroids.collect.with_index{ |centroid, index|
          next if @clusters[index].data_items.empty?

          cp = centroid[4] # centroid properties
          cp[:area] = [Helper.approximate_polygon_area(Helper.approximate_quadrilateral_polygon(@clusters[index].data_items)), 1.0].max # m^2
          cp[:visit_count] = @clusters[index].data_items.sum{ |d_i| d_i[3][:visits] }
          cp[:visit_density] = cp[:visit_count] / cp[:area].to_f
        }
      end

      def update_approximate_area_and_speeds
        @density_cap = [@density_cap, updated_visit_densities.compact.median * @density_range_ratio].max

        @centroids.each_with_index{ |centroid, index|
          next if @clusters[index].data_items.empty?

          cp = centroid[4] # centroid properties
          min_speed_calc_size = (0.95 * @clusters[index].data_items.size).ceil
          max_speed_calc_size = (0.15 * @clusters[index].data_items.size).ceil
          cp[:min_speed] = @clusters[index].data_items.min_by(min_speed_calc_size){ |i| i[4][:local_speed] }.sum{ |i| i[4][:local_speed] }.to_f / min_speed_calc_size
          cp[:max_speed] = @clusters[index].data_items.max_by(max_speed_calc_size){ |i| i[4][:local_speed] }.sum{ |i| i[4][:local_speed] }.to_f / max_speed_calc_size
          speed_ratio = ([@density_cap - cp[:visit_density], 0].max / @density_cap.to_f)**@density_speed_conversion_power
          cp[:speed] = cp[:min_speed] + [cp[:max_speed] - cp[:min_speed], 0.0].max * speed_ratio
        }
      end

      def update_approximate_route_times
        return unless @cut_symbol

        update_approximate_area_and_speeds

        approximate_total_route_time = @centroids.select{ |c| c[4][:speed] }.sum{ |centroid|
          cp = centroid[4] # centroid properties
          cp[:route_time] = Helper.compute_approximate_route_time(cp[:area], cp[:visit_count], cp[:speed], cp[:total_work_days] / cp[:vehicle_count].to_f) * cp[:vehicle_count]
        }

        @approximate_total_route_time = (9 * @approximate_total_route_time + approximate_total_route_time) / 10.0 if approximate_total_route_time < @approximate_total_route_time
      end

      def compute_vehicle_work_time_with_depot_and_capacity
        coef = @centroids.map.with_index{ |centroid, index|
          @vehicles[index][:duration] / ([centroid[4][:duration_from_and_to_depot], 1].max * @vehicles[index][:total_work_days])
        }.min

        # TODO: The following filter is there to not to affect the existing functionality.
        # However, we should improve the functioanlity and make it less arbitrary.
        coef = [coef * 0.9, 1.0].min # To make sure the limit will not become 0

        min_capacity_offence_coeff = @centroids.min_by{ |c| c[4][:capacity_offence_coeff] }[4][:capacity_offence_coeff]

        @centroids.map.with_index{ |centroid, index|
          centroid[4][:capacity_offence_coeff] -= min_capacity_offence_coeff
          (@vehicles[index][:duration] - coef * centroid[4][:duration_from_and_to_depot] * @vehicles[index][:total_work_days]) * 0.98**centroid[4][:capacity_offence_coeff]
        }
      end

      def update_cut_limit_wrt_depot_and_route_time
        update_approximate_route_times

        return unless @cut_symbol == :duration

        # TODO: depot (commute) duration  effects the balance differently (and more directly and strongly)
        # Check if it is better to leave it like this or including it inside the total_route_time
        # so that it increases the total_load and shared amongs the clusters.

        vehicle_work_times = compute_vehicle_work_time_with_depot_and_capacity
        total_vehicle_work_time = vehicle_work_times.sum
        @centroids.size.times{ |index|
          @cut_limit[index][:limit] = (@total_cut_load + @approximate_total_route_time) * vehicle_work_times[index] / total_vehicle_work_time
        }
      end

      def update_strict_duration_limitation_wrt_depot
        return unless @cut_symbol

        @centroids.map.with_index{ |centroid, index|
          @strict_limitations[index][:duration] = @vehicles[index][:duration] - centroid[4][:duration_from_and_to_depot] * @vehicles[index][:total_work_days]
        }
      end

      def update_balance_coefficients
        return unless @cut_symbol

        update_cut_limit_wrt_depot_and_route_time

        balance_violations = @cut_limit.collect.with_index{ |c_l, index|
          # incase we want to take into account route_time for capacity checks,
          # protect the balance calculation
          route_time = @centroids[index][4][:route_time] if @cut_symbol == :duration
          (@centroids[index][3][@cut_symbol] + route_time.to_f) / c_l[:limit].to_f - 1.0
        }

        @logger&.debug '_____________________________________________________________________________________________________________'
        @logger&.debug balance_violations.sum.round(2)
        @logger&.debug Helper.colorize_balance_violations(balance_violations).join(', ')

        stepsize = 0.2 - 0.1 *  @iteration / @max_iterations.to_f # unitless coefficient for making the updates smaller
        max_correction = 1.05 + 0.95 * (@max_iterations - @iteration) / @max_iterations.to_f
        min_correction = 1.0 / max_correction

        @max_balance_violation = 0

        @number_of_clusters.times.each{ |index|
          # Skip capacity violating clusters even if they are under-loaded
          # otherwise, they will violate their capacity more
          next if !@clusters_with_limit_violation[index].empty? && balance_violations[index].negative?

          @max_balance_violation = [@max_balance_violation, balance_violations[index].abs].max # ignores capacity violating clusters!

          # TODO: if the violation is small don't bother updating the coeff ?
          # next if balance_violations[index].abs < @balance_violation_current_limit

          balance_correction = [[(1 + balance_violations[index])**stepsize, min_correction].max, max_correction].min

          # TODO: stepsize can evolve during the iterations like column-generation
          # it shouldn't lead to extreme zig-zagging but it shouldn't lead to
          # flat-lining either.

          @balance_coeff[index] *= balance_correction
          @balance_coeff.collect!{ |b_c| b_c / balance_correction }
        }

        # TODO: check if there is a better way to do stabilization
        # make balance coeff mean 1 to prevent them getting extremely big/small
        stabilization_coeff = 1.0 / @balance_coeff.mean
        @balance_coeff.collect!{ |b_c| stabilization_coeff * b_c }

        @logger&.debug "new balance_coeffs:\n#{@balance_coeff.collect{ |b_c| b_c.round(3) }.join(',  ')}"
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

        @logger&.debug "Iteration #{@iteration}: total centroid movement #{total_movement_meter.round} eucledian meters"

        @last_n_average_diffs.push total_movement_meter.to_f # add to the vector before convergence check in case other conditions are not satisfied

        # If convereged, we can stop
        return true if @last_n_average_diffs.last < @number_of_clusters * (20 + 80 * @iteration / @max_iterations)

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
        data_item[3].each{ |unit, value|
          @centroids[cluster_index][3][unit] += value.to_f
        }
      end

      def capactity_violation?(item, cluster_index)
        # TODO: correction of duration wrt to cluster "size" is needed for duration capacity
        # For this,
        # (1) we need to keep some info inside the centroid/cluster
        # The distance of the most distant point, the surface area (i.e., travel duration approximation for the cluster),
        # number of visits in this cluster at the end of last iteration.
        # Then for checking duration capacity violation,
        # if the item in consideration is more farther away then the current most distant point then update the "cluster_size" temporarily
        # if not, no update is needed
        # and then check the following
        # duration_from_to_depot x n_day + current_duration_load + cluster_size + duration_value > limit
        # (2) at the moment of actual affectation, we need to check again and make a correction of the info kept inside the cluster/centroid if needed
        # (3) at the end of iteration update the visit count
        # (4) modify update_cut_limit_wrt_depot_distance so that we always have an up-to-date distance into inside centroid
        item[3].any?{ |unit, _value|
          next unless @strict_limitations[cluster_index][unit]

          total_value = 0
          do_forall_linked_items_of(item){ |linked_item| total_value += linked_item[3][unit] }

          @centroids[cluster_index][3][unit] + total_value > @strict_limitations[cluster_index][unit]
        }
      end

      def compatible_items_multi_depot_selector(items_to_consider)
        closest_items = []
        @vehicles.length.times.each{ |margin|
          closest_items = items_to_consider.select{ |item|
            item[4][:duration_from_and_to_depot][@centroids.length] <= item[4][:duration_from_and_to_depot].sort[margin]
          }
          break unless closest_items.empty?
        }
        closest_items
      end

      def output_cluster_geojson
        # TODO: clean the geojson function and move them to helpers
        return unless @geojson_dump_folder

        @start_time ||= Time.now.strftime('%H:%M:%S').parameterize
        colorgenerator = ColorGenerator.new(saturation: 0.8, value: 1.0, seed: 1) if @geojson_colors.nil? # fix the seed so that color order is the same
        @geojson_colors ||= Array.new(@number_of_clusters){ "##{colorgenerator.create_hex}" }

        polygons = []
        points = []
        # cluster for each vehicle
        @clusters.each_with_index{ |cluster, c_index|
          polygons << collect_hulls(cluster, c_index)
          points << collect_points(cluster, c_index)
        }
        polygons.flatten!.compact!
        points.flatten!.compact!
        file_name = "generated_cluster_#{@start_time}_iteration_#{@iteration}".parameterize
        geojson = {
          type: 'FeatureCollection',
          features: polygons + points
        }

        File.write(File.join(@geojson_dump_folder, "#{file_name}.geojson"), geojson.to_json)

        # Generating the image takes long but for dev it is useful, should not be given as option.
        generate_cluster_images = false
        if generate_cluster_images
          image_folder_path = File.join(@geojson_dump_folder, @start_time)
          FileUtils.mkdir_p(image_folder_path)
          geojson = {
            type: 'FeatureCollection',
            features: polygons
          }
          g2i = Geojson2image::Convert.new(
            json: geojson.to_json,
            width: 1080,
            height: 1080,
            padding: 0,
            background: '#ffffff',
            fill: '#008000',
            stroke: '#006400',
            output: File.join(image_folder_path, "output-#{@iterations}.png")
          )
          begin
            g2i.to_image
            FileUtils.cp(File.join(image_folder_path, "output-#{@iterations}.png"), File.join(@geojson_dump_folder, 'output-latest.png'))
          rescue
            # skip image generation if there is a polygon with less then 2 points
            # Note: Doesn't have to be skipped but since the image is not necessary it doesn't worth the time.
          end
        end

        puts 'Clusters saved : ' + file_name
      end

      def collect_hulls(cluster, c_index)
        return [] if cluster.data_items.empty?

        color = @geojson_colors[c_index]

        vector = cluster.data_items.collect{ |item|
          [item[1], item[0]]
        }
        hull = Hull.get_hull(vector)
        return nil if hull.nil?

        totals = Hash.new(0)

        total_keys = cluster.data_items[0][3].keys - [:duration_from_and_to_depot, :matrix_index]
        cluster.data_items.each{ |d|
          total_keys.each{ |key| totals["total_#{key}"] += d[3][key].to_f if d[3] && d[3][key] &&  d[3][key].is_a?(Numeric) }
        }

        features = [
          {
            type: 'Feature',
            properties: {
              color: color,
              'marker-size': 'large',
              'marker-color': color,
              stroke: '#000000',
              'stroke-opacity': 0,
              'stroke-width': 10,
              name: "#{@centroids[c_index][4][:id]&.join(',')}_center",
              lat_lon: @centroids[c_index][0..1].join(','),
              lon_lat: @centroids[c_index][0..1].reverse.join(','),
              matrix_index: @centroids[c_index][3][:matrix_index],
              point_count: cluster.data_items.size,
              depot_distance: @centroids[c_index][3][:duration_from_and_to_depot],
              balance_coeff: @balance_coeff[c_index],
            }.merge(totals),
            geometry: {
              type: 'Point',
              coordinates: [@centroids[c_index][1], @centroids[c_index][0]]
            }
          },
          {
            type: 'Feature',
            properties: {
              color: color,
              fill: color,
              name: @centroids[c_index][4][:id]&.join(','),
              lat_lon: @centroids[c_index][0..1].join(','),
              lon_lat: @centroids[c_index][0..1].reverse.join(','),
              matrix_index: @centroids[c_index][3][:matrix_index],
              point_count: cluster.data_items.size,
              depot_distance: @centroids[c_index][3][:duration_from_and_to_depot],
              balance_coeff: @balance_coeff[c_index],
            }.merge(totals),
            geometry: {
              type: 'Polygon',
              coordinates: [hull + [hull.first]]
            }
          }
        ]

        features
      end

      def collect_points(cluster, c_index)
        color = @geojson_colors[c_index]
        cluster.data_items.collect{ |item|
          {
            type: 'Feature',
            properties: {
              color: color,
              'marker-size': 'small',
              'marker-color': color,
              name: item[2],
              lat_lon: item[0..1].join(','),
              lon_lat: item[0..1].reverse.join(','),
              distance: @distance_function.call(item, @centroids[c_index]),
              distance_balanced: distance(item, @centroids[c_index], c_index),
            }.merge(item[3]).merge(item[4].reject{ |k| k == :linked_item }),
            geometry: {
              type: 'Point',
              coordinates: [item[1], item[0]]
            }
          }
        }
      end
    end
  end
end
