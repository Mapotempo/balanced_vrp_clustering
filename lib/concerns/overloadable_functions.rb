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
    return false if !service_chars[:v_id].empty? && (service_chars[:v_id] & vehicle_chars[:v_id]).empty?

    # if the service needs a skill that the vehicle doesn't have
    return false if !(service_chars[:skills] - vehicle_chars[:skills]).empty?

    # if service and vehicle have no matching days
    return false if (service_chars[:days] & vehicle_chars[:days]).empty?

    true # if not, they are compatible
  end

  def compute_distance_from_and_to_depot(vehicles_infos, data_set, matrix)
    data_set.data_items.each{ |point|
      point[4][:duration_from_and_to_depot] = []
    }

    vehicles_infos.each{ |vehicle_info|
      if matrix # matrix_index
        single_index_array = vehicle_info[:depot]
        point_indices = data_set.data_items.map{ |point| point[4][:matrix_index] }
        time_matrix_from_depot = Helper.unsquared_matrix(matrix, single_index_array, point_indices)
        time_matrix_to_depot = Helper.unsquared_matrix(matrix, point_indices, single_index_array)
      else
        single_location_array = [vehicle_info[:depot]]
        locations = data_set.data_items.collect{ |point| [point[0], point[1]] }
        time_matrix_from_depot = OptimizerWrapper.router.matrix(OptimizerWrapper.config[:router][:url], :car, [:time], single_location_array, locations).first
        time_matrix_to_depot = OptimizerWrapper.router.matrix(OptimizerWrapper.config[:router][:url], :car, [:time], locations, single_location_array).first
      end

      data_set.data_items.each_with_index{ |point, index|
        point[4][:duration_from_and_to_depot] << time_matrix_from_depot[0][index] + time_matrix_to_depot[index][0]
      }
    }
  end

  def compute_limits(cut_symbol, cut_ratio, vehicles_infos, data_items, entity = :vehicle)
    cumulated_metrics = Hash.new(0)

    data_items.each{ |item|
      item[3].each{ |key, value|
        cumulated_metrics[key] += value
      }
    }

    strict_limits = vehicles_infos.collect{ |cluster|
      s_l = { duration: cluster[:total_work_time], visits: cumulated_metrics[:visits] }
      cumulated_metrics.each{ |unit, _total_metric|
        s_l[unit] = ((cluster[:capacities].any?{ |capacity| capacity[:unit_id] == unit }) ? cluster[:capacities].find{ |capacity| capacity[:unit_id] == unit }[:limit] : 0)
      }
      s_l
    }

    total_work_time = vehicles_infos.map{ |cluster| cluster[:total_work_time] }.reduce(&:+).to_f
    metric_limits = if entity == :vehicle && total_work_time.positive?
      vehicles_infos.collect{ |cluster|
        { limit: cut_ratio * (cumulated_metrics[cut_symbol].to_f * (cluster[:total_work_time] / total_work_time)) }
      }
    else
      { limit: cut_ratio * (cumulated_metrics[cut_symbol] / vehicles_infos.size) }
    end

    [strict_limits, metric_limits]
  end
end
