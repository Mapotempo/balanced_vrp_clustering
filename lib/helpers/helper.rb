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

module Helper
  def self.flying_distance(loc_a, loc_b)
    return 0.0 unless loc_a[0] && loc_b[0]

    if (loc_a[0] - loc_b[0]).abs < 30 && [loc_a[0].abs, loc_b[0].abs].max + (loc_a[1] - loc_b[1]).abs < 100
      # These limits ensures that relative error cannot be much greather than 2%
      # For a distance like Bordeaux - Berlin, relative error between
      # euclidean_distance and flying_distance is 0.1%.
      # That is no need for trigonometric calculation.
      return euclidean_distance(loc_a, loc_b)
    end

    r = 6378137 # Earth's radius in meters
    deg2rad_lat_a = loc_a[0] * Math::PI / 180
    deg2rad_lat_b = loc_b[0] * Math::PI / 180
    deg2rad_lon_a = loc_a[1] * Math::PI / 180
    deg2rad_lon_b = loc_b[1] * Math::PI / 180
    lat_distance = deg2rad_lat_b - deg2rad_lat_a
    lon_distance = deg2rad_lon_b - deg2rad_lon_a

    intermediate = Math.sin(lat_distance / 2) * Math.sin(lat_distance / 2) + Math.cos(deg2rad_lat_a) * Math.cos(deg2rad_lat_b) *
                   Math.sin(lon_distance / 2) * Math.sin(lon_distance / 2)

    r * 2 * Math.atan2(Math.sqrt(intermediate), Math.sqrt(1 - intermediate))
  end

  def self.euclidean_distance(loc_a, loc_b)
    return 0.0 unless loc_a[0] && loc_b[0]

    delta_lat = loc_a[0] - loc_b[0]
    delta_lon = (loc_a[1] - loc_b[1]) * Math.cos((loc_a[0] + loc_b[0]) * Math::PI / 360.0) # Correct the length of a lon difference with cosine of avereage latitude

    111321 * Math.sqrt(delta_lat**2 + delta_lon**2) # 111321 is the length of a degree (of lon and lat) in meters
  end

  def self.unsquared_matrix(matrix, a_indices, b_indices)
    a_indices.map{ |a|
      b_indices.map { |b|
        matrix[b][a]
      }
    }
  end
end
