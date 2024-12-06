/*
 * Copyright (c) 2020 BlueRock Security, Inc.
 * This software is distributed under the terms of the BedRock Open-Source License.
 * See the LICENSE-BedRock file in the repository root for details.
 */
template<typename Data>
class Map {
  class iterator {
    template<typename Key>
    friend class ::Map;
  };
};

template class Map<int>;
