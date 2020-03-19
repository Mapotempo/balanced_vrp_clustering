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

class FunctionsTest < Minitest::Test
  include OverloadableFunctions

  def test_compatible_characteristics
    assert compatible_characteristics?({ v_id: [], skills: [], days: ['all_days'] }, { v_id: [], skills: [], days: ['all_days'] })

    # v_id
    refute compatible_characteristics?({ v_id: ['v1'], skills: [], days: ['all_days'] }, { v_id: [], skills: [], days: ['all_days'] })
    assert compatible_characteristics?({ v_id: ['v1'], skills: [], days: ['all_days'] }, { v_id: ['v1'], skills: [], days: ['all_days'] })
    assert compatible_characteristics?({ v_id: [], skills: [], days: ['all_days'] }, { v_id: ['v1'], skills: [], days: ['all_days'] })

    # skills
    refute compatible_characteristics?({ v_id: [], skills: ['sk1'], days: ['all_days'] }, { v_id: [], skills: [], days: ['all_days'] })
    assert compatible_characteristics?({ v_id: [], skills: ['sk1'], days: ['all_days'] }, { v_id: [], skills: ['sk1'], days: ['all_days'] })
    assert compatible_characteristics?({ v_id: [], skills: [], days: ['all_days'] }, { v_id: [], skills: ['sk1'], days: ['all_days'] })

    # days
    refute compatible_characteristics?({ v_id: [], skills: [], days: ['other_days'] }, { v_id: [], skills: [], days: ['all_days'] })
    refute compatible_characteristics?({ v_id: [], skills: [], days: ['monday', 'tuesday'] }, { v_id: [], skills: [], days: ['wednesday', 'thursday'] })
    assert compatible_characteristics?({ v_id: [], skills: [], days: ['monday', 'tuesday'] }, { v_id: [], skills: [], days: ['tuesday', 'thursday'] })
  end

  def test_compute_limits
    clusterer, data_items = Instance.two_clusters_4_items

    strict_limit, cut_limit = compute_limits(:visits, 1.0, clusterer.vehicles_infos, data_items.data_items)
    (0..clusterer.vehicles_infos.size - 1).each{ |cluster_index|
      assert_equal 0, strict_limit[cluster_index][:duration]
      assert_equal 6, strict_limit[cluster_index][:visits]
      assert_equal 2, cut_limit[:limit]
    }
  end

  def test_compute_limits_with_work_time
    clusterer, data_items = Instance.two_clusters_4_items
    clusterer.vehicles_infos[0][:total_work_time] = 1
    clusterer.vehicles_infos[1][:total_work_time] = 3

    strict_limit, cut_limit = compute_limits(:visits, 1.0, clusterer.vehicles_infos, data_items.data_items)
    (0..clusterer.vehicles_infos.size - 1).each{ |cluster_index|
      assert_equal clusterer.vehicles_infos[cluster_index][:total_work_time], strict_limit[cluster_index][:duration]
      assert_equal 6, strict_limit[cluster_index][:visits]
      assert_equal clusterer.vehicles_infos[cluster_index][:total_work_time], cut_limit[cluster_index][:limit]
    }
  end
end
