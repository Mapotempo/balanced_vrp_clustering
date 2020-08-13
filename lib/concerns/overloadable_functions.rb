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

    data_set.data_items.each{ |point|
      point[4][:duration_from_and_to_depot] = []
    }

    vehicles.each{ |vehicle_info|
      if matrix
        single_index_array = [vehicle_info[:depot][:matrix_index]]
        point_indices = data_set.data_items.map{ |point| point[4][:matrix_index] }
        time_matrix_from_depot = Helper.unsquared_matrix(matrix, single_index_array, point_indices)
        time_matrix_to_depot = Helper.unsquared_matrix(matrix, point_indices, single_index_array)
      else
        items_locations = data_set.data_items.collect{ |point| [point[0], point[1]] }
        time_matrix_from_depot = [items_locations.collect{ |item_location|
          Helper.euclidean_distance(vehicle_info[:depot][:coordinates], item_location)
        }]
        time_matrix_to_depot = items_locations.collect{ |item_location|
          [Helper.euclidean_distance(item_location, vehicle_info[:depot][:coordinates])]
        }
      end

      data_set.data_items.each_with_index{ |point, index|
        point[4][:duration_from_and_to_depot] << time_matrix_from_depot[0][index] + time_matrix_to_depot[index][0]
      }
    }
  end

  def compute_limits(cut_symbol, cut_ratio, vehicles, data_items)
    strict_limits = vehicles.collect{ |vehicle|
      s_l = { duration: vehicle[:duration] } # incase duration is not supplied inside the capacities
      vehicle[:capacities].each{ |unit, limit|
        s_l[unit] = limit
      }
      vehicle[:duration] = s_l[:duration] # incase duration is only supplied inside the capacities
      s_l
    }

    if cut_symbol
      total_quantity = Hash.new(0)

      (@unit_symbols || (cut_symbol && [cut_symbol]))&.each{ |unit|
        total_quantity[unit] = data_items.sum{ |item| item[3][unit].to_f }
      }

      total_capacity = vehicles.sum{ |vehicle| vehicle[:capacities][cut_symbol].to_f }
      metric_limits = vehicles.collect{ |vehicle|
        vehicle_share = total_capacity.positive? ? vehicle[:capacities][cut_symbol] / total_capacity : 1.0 / vehicles.size
        { limit: cut_ratio * total_quantity[cut_symbol] * vehicle_share }
      }
    end

    [strict_limits, metric_limits]
  end
end
