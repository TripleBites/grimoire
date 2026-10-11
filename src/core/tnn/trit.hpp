#pragma once

#include <vector>
#include <cstdint>
#include <cstddef>

/***************************************************************
* nz = Value to indicate if the ternary value is nonzero (0 or -1 / +1)
*       0 = 0
*       1 = -1/+1
* sign = Value to indicate if the ternary value sign (-1 or +1)
*       0 = -1
*       1 = +1
****************************************************************/
namespace trit
{
    class Buffer
    {
        private:
            uint64_t bit_count;
            std::vector<uint64_t> nz;
            std::vector<uint64_t> sign;
        public:
            Buffer(uint64_t bit_count)
                :   bit_count(bit_count),
                    nz((bit_count + 63) / 64),
                    sign((bit_count + 63) / 64)
            {
            }

            bool GetNonzero(size_t i) const
            { 
                return (nz[i >> 6] >> (i & 63)) & 1;
            }
            bool GetSign(size_t i) const
            { 
                return (sign[i >> 6] >> (i & 63)) & 1;
            }
            void SetSign(size_t i)
            {
                sign[i >> 6] |= (1ULL << (i & 63));
            }
            void SetNonzero(size_t i)
            {
                nz[i >> 6] |= (1ULL << (i & 63));
            }
            void Clear(size_t i)
            { 
                nz[i >> 6] &= ~(1ULL << (i & 63));
                sign[i >> 6] &= ~(1ULL << (i & 63));
            }
    };
}









