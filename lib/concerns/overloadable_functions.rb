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
require 'active_support/concern'

module OverloadableFunctions
  extend ActiveSupport::Concern

  def compatible_characteristics?(service_chars, vehicle_chars)
    # Compatile service and vehicle
    # if the vehicle cannot serve the service due to sticky_vehicle_id
    return false if !service_chars[:v_id].empty? && (service_chars[:v_id] & vehicle_chars[:id]).empty?

    # if the service needs a skill that the vehicle doesn't have
    return false if !(service_chars[:skills] - vehicle_chars[:skills]).empty?

    # if service and vehicle have no matching days
    return false if (service_chars[:day_skills] & vehicle_chars[:day_skills]).empty?

    true # if not, they are compatible
  end

  def compute_distance_from_and_to_depot(vehicles, data_set, matrix)
    return if data_set.data_items.all?{ |item| item[4][:duration_from_and_to_depot] }

    if matrix # matrix_index
      single_index_array = vehicles.first[:depot]
      point_indices = data_set.data_items.map{ |point| point[4][:matrix_index] }
      time_matrix_from_depot = Helper.unsquared_matrix(matrix, single_index_array, point_indices)
      time_matrix_to_depot = Helper.unsquared_matrix(matrix, point_indices, single_index_array)
    else
      items_locations = data_set.data_items.collect{ |point| [point[0], point[1]] }
      time_matrix_from_depot = [items_locations.collect{ |item_location|
        Helper.euclidean_distance(vehicles.first[:depot], item_location)
      }]
      time_matrix_to_depot = items_locations.collect{ |item_location|
        [Helper.euclidean_distance(item_location, vehicles.first[:depot])]
      }
    end

    data_set.data_items.each_with_index{ |point, index|
      point[4][:duration_from_and_to_depot] = time_matrix_from_depot[0][index] + time_matrix_to_depot[index][0]
    }
  end

  def compute_limits(cut_symbol, cut_ratio, vehicles, data_items, entity = :vehicle)
    cumulated_metrics = Hash.new(0)

    (@unit_symbols || (cut_symbol && [cut_symbol]))&.each{ |unit|
      cumulated_metrics[unit] = data_items.sum{ |item| item[3][unit].to_f }
    }

    strict_limits = vehicles.collect{ |vehicle|
      s_l = { duration: vehicle[:duration] } # incase capacity for duration is not supplied
      vehicle[:capacities].each{ |unit, limit|
        s_l[unit] = limit
      }
      s_l
    }

    total_duration = vehicles.sum{ |vehicle| vehicle[:duration].to_f }
    metric_limits = if entity == :vehicle && total_duration.positive?
                      vehicles.collect{ |vehicle|
                        { limit: cut_ratio * cumulated_metrics[cut_symbol] * vehicle[:duration] / total_duration }
                      }
                    else
                      { limit: cut_ratio * cumulated_metrics[cut_symbol] / vehicles.size }
                    end

    [strict_limits, metric_limits]
  end
end
