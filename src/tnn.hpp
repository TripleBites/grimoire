#pragma once

#include "ternary.hpp"
#include <memory>

#if defined(__GNUC__) || defined(__clang__)
  #define TNN_RESTRICT __restrict__
  static inline uint32_t popcnt64(uint64_t x) { return (uint32_t)__builtin_popcountll(x); }
#else
  #define TNN_RESTRICT
  static inline uint32_t popcnt64(uint64_t x) {          // SWAR fallback
      x = x - ((x >> 1) & 0x5555555555555555ULL);
      x = (x & 0x3333333333333333ULL) + ((x >> 2) & 0x3333333333333333ULL);
      x = (x + (x >> 4)) & 0x0F0F0F0F0F0F0F0FULL;
      return (uint32_t)((x * 0x0101010101010101ULL) >> 56);
  }
#endif

class Tnn
{
    private:

        struct LayerDesc
        {
            TritBuffer bias;
            TritBuffer weights;
            TritBuffer activations;
        };

        struct Network
        {
            std::vector<LayerDesc> layer_descriptions;
        };

    public:

        uint64_t forward(const uint64_t input)
        {

        }
};