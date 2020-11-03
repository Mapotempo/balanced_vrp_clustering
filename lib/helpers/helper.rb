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

require 'awesome_print'

module Helper
  R = 6_378_137 # Earth's radius in meters

  L = 111_321   # Length of a degree (of lon and lat) in meters

  RADIANS_IN_A_DEGREE = Math::PI / 180.0

  BALANCE_VIOLATION_COLOR_LIMITS = [
    [0.50, 'red'],
    [0.25, 'purple'],
    [0.10, 'blue'],
    [0.05, 'white'],
    [0.00, 'green']
  ].freeze

  def self.fixnum_max
    (2**(0.size * 8 - 2) - 1)
  end

  def self.fixnum_min
    -(2**(0.size * 8 - 2))
  end

  def self.deg2rad(degree)
    # Converts degrees to radians
    degree * RADIANS_IN_A_DEGREE
  end

  def self.approximate_polygon_area(coordinates)
    # A rudimentary way to calculate area (m^2) from coordinates.
    # When the shape is vaguely convex, it gives okay results.
    # https://stackoverflow.com/a/32912727/1200528
    return 0.0 unless coordinates.size > 2

    area = 0.0
    coor_p = coordinates.first
    coordinates[1..-1].each{ |coor|
      area += deg2rad(coor[1] - coor_p[1]) * (2 + Math.sin(deg2rad(coor_p[0])) + Math.sin(deg2rad(coor[0])))
      coor_p = coor
    }

    (area * R**2 / 2).abs
  end

  def self.approximate_quadrilateral_polygon(coordinates)
    # Approximates the tetragon of a coordinate list.
    # First two very distant points (c1 and c2) are selected based on a
    # random distant point crand and c0.
    # Then two more points (c3 and c4) are selected on each side of the
    # line created by c1-c2 to maximize the coverage.

    # c1 and c2 are approximately the most distant two points.
    crand = coordinates[rand(coordinates.size)]
    c0 = coordinates.max_by{ |c_i| Helper.flying_distance(crand, c_i) }
    c1 = coordinates.max_by{ |c_i| Helper.flying_distance(c0, c_i) }
    c2 = coordinates.max_by{ |c_i| Helper.flying_distance(c1, c_i) }

    # find two points (c3 and c4) on each side of the line passing through c1 and c2
    # which are the farthest away from the line.
    c3 = c4 = nil
    max_distance = { up: 0, down: 0 }
    coordinates.each{ |c_i|
      position, distance_to_line = position_and_distance_to_line(c1, c2, c_i)

      if position.positive? && distance_to_line > max_distance[:up]
        max_distance[:up] = distance_to_line
        c3 = c_i
      elsif position.negative? && distance_to_line > max_distance[:down]
        max_distance[:down] = distance_to_line
        c4 = c_i
      end
    }

    # in case it is a triangle compact it
    [c1, c3, c2, c4, c1].compact
  end

  def self.position_and_distance_to_line(l_begin, l_end, point)
    # position and aproximate distance of a point to the line passing through points (l_begin, l_end)
    lat_diff = l_end[0] - l_begin[0]
    lon_diff = l_end[1] - l_begin[1]

    [
      position = lat_diff * (point[1] - l_begin[1]) - lon_diff * (point[0] - l_begin[0]),
      position.abs / Math.sqrt(lat_diff**2 + lon_diff**2)
    ]
  end

  def self.compute_approximate_route_time(area, visit_count, speed, total_work_days)
    # Based on Equation (6) of doi:10.1016/j.cor.2004.07.001

    k1 = 0.765    # a coefficient that depends on the distance metric and routing strategy
    k2 = 1.45     # is a corrective coefficient (route factor) reflecting the road network impedance
    k0 = k1 * k2

    total_work_days * k0 * Math.sqrt(area * visit_count / total_work_days**1.5) / speed.to_f
  end

  def self.flying_distance(loc_a, loc_b)
    return 0.0 unless loc_a[0] && loc_b[0]

    if (loc_a[0] - loc_b[0]).abs < 30 && [loc_a[0].abs, loc_b[0].abs].max + (loc_a[1] - loc_b[1]).abs < 100
      # These limits ensures that relative error cannot be much greather than 2%
      # For a distance like Bordeaux - Berlin, relative error between
      # euclidean_distance and flying_distance is 0.1%.
      # That is no need for trigonometric calculation.
      return euclidean_distance(loc_a, loc_b)
    end

    deg2rad_loc_a_lat = deg2rad(loc_a[0])
    deg2rad_loc_b_lat = deg2rad(loc_b[0])

    intermediate = Math.sin((deg2rad_loc_b_lat - deg2rad_loc_a_lat) / 2)**2 +
                   Math.sin((deg2rad(loc_b[1]) - deg2rad(loc_a[1])) / 2)**2 * Math.cos(deg2rad_loc_b_lat) * Math.cos(deg2rad_loc_a_lat)

    R * 2 * Math.atan2(Math.sqrt(intermediate), Math.sqrt(1 - intermediate))
  end

  def self.euclidean_distance(loc_a, loc_b)
    return 0.0 unless loc_a[0] && loc_b[0]

    delta_lat = loc_a[0] - loc_b[0]
    delta_lon = (loc_a[1] - loc_b[1]) * Math.cos(deg2rad((loc_a[0] + loc_b[0]) / 2.0)) # Correct the length of a lon difference with cosine of avereage latitude

    L * Math.sqrt(delta_lat**2 + delta_lon**2)
  end

  def self.unsquared_matrix(matrix, a_indices, b_indices)
    a_indices.map{ |a|
      b_indices.map { |b|
        matrix[b][a]
      }
    }
  end

  def self.check_if_projection_inside_the_line_segment(point_coord, line_beg_coord, line_end_coord, margin)
    # margin: if (0 > margin > 1), the percentage of the line segment that will be considered as "outside"
    # margin: if (margin < 0), the percentage that the "inside" zone is extended
    # [0, 1]: coordinates [lat, lon] or [lon, lat]
    line_direction = [0, 1].collect{ |i| line_end_coord[i] - line_beg_coord[i] }
    point_direction = [0, 1].collect{ |i| point_coord[i] - line_beg_coord[i] }

    projection_scaler = [0, 1].sum{ |i| line_direction[i] * point_direction[i] } / [0, 1].sum{ |i| line_direction[i]**2 }
    # If projection_scaler
    # >1:        the projection is after the line segment end
    # <0:        it is before the line segment begin
    # otherwise: it is on the line segment define by begin_coord end end_coord

    # If the following holds, it is inside the margin of the line segment
    projection_scaler >= 0 + 0.5 * margin && projection_scaler <= 1 - 0.5 * margin
  end

  def self.colorize_balance_violations(balance_violations)
    balance_violations.collect{ |i|
      i = i.round(2)

      color_index = 0
      BALANCE_VIOLATION_COLOR_LIMITS.each{ |cl|
        break if i.abs >= cl[0]

        color_index += 1
      }

      i.to_s.send("#{BALANCE_VIOLATION_COLOR_LIMITS[color_index][1]}#{i.negative? ? 'ish' : ''}")
    }
  end

  def self.output_cluster_stats(centroids, logger = nil)
    # TODO: improve this function with a file option and csv output instead of csv_string
    return unless logger

    csv_string = CSV.generate do |csv|
      csv << %w[
        zone
        nb_vehicles
        capacities
        skills
        nb_visits
        total_duration(excel_format)
        total_visit_duration
        total_intra_zone_route_duration
        total_depot_route_duration
      ]

      centroids.each_with_index{ |c, i|
        csv << [
          i + 1,
          c[4][:vehicle_count],
          c[4][:capacities],
          c[4][:skills],
          c[4][:visit_count],
          (c[3][:duration] + c[4][:route_time] + c[4][:duration_from_and_to_depot] * c[4][:total_work_days]) / 86400,
          c[3][:duration] / 86400,
          c[4][:route_time] / 86400,
          (c[4][:duration_from_and_to_depot] * c[4][:total_work_days]) / 86400
        ]
      }
    end

    logger&.debug "cluster_stats:\n" + csv_string
  end
end

# Some functions for convenience
# In the same vein as active_support Enumerable.sum implementation
module Enumerable
  # Provide the average on an array
  #  [5, 15, 7].mean # => 9.0
  def mean(type = :arithmetic)
    return nil if empty?

    case type
    when :arithmetic
      inject(0) { |sum, x| sum + x } / size.to_f
    when :geometric
      # can overflow for large inputs
      reduce(:*)**(1.0 / size) if all?(&:positive?)
    else
      raise RuntimeError, "Unknown mean type: #{type}"
    end
  end

  # If the array has an odd number, then simply pick the one in the middle
  # If the array size is even, then we return the mean of the two middle.
  #  [5, 15, 7].median # => 7
  def median(already_sorted = false)
    return nil if empty?

    ret = already_sorted ? self : sort
    m_pos = size / 2 # no to_f!
    size.odd? ? ret[m_pos] : ret[m_pos - 1..m_pos].mean
  end

  # The mode is the single most popular item in the array.
  #  [5, 15, 10, 15].mode # => 15
  def mode
    modes(false)[0]
  end

  # In case there are multiple elements with the highest occurence
  #  [5, 15, 10, 10, 15].modes # => [10, 15]
  #  [5, 15, 10, 15].modes     # => [15] (Note that modes() returns an array)
  def modes(find_all = true)
    return nil if empty?

    histogram = each_with_object(Hash.new(0)) { |n, h| h[n] += 1 }
    modes = nil
    histogram.each_pair do |item, times|
      modes << item if find_all && !modes.nil? && times == modes[0]
      modes = [times, item] if (modes && times > modes[0]) || (modes.nil? && times > 1)
    end
    modes.nil? ? nil : modes[1...modes.size]
  end

  # group_by like counting routine for convenience
  def count_by(&block)
    self.group_by(&block)
        .map{ |key, items| [key, items&.count] }
        .to_h
  end

end
