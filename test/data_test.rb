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

class ClusteringTest < Minitest::Test
  def test_data_with_matrix
    clusterer, data_set = Instance.two_clusters_4_items_with_matrix
    clusterer.vehicles.first[:depot] = {}

    assert_raises ArgumentError do
      clusterer.build(data_set, :visits)
    end

    clusterer.vehicles.first[:depot] = {
      matrix_index: 0,
      coordinates: [45.604784, 4.758965]
    } # back to normal vehicles
    data_set.data_items.first[4].delete(:matrix_index)
    assert_raises ArgumentError do
      clusterer.build(data_set, :visits)
    end
  end
end
