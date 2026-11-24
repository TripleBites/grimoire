#pragma once

// ternary_tensor.hpp — minimal 2D ternary tensor {-1, 0, +1}
// Storage: two bitplanes per row, packed into 64-bit words.
//   nz   bit = 1 -> value is nonzero
//   sign bit = 1 -> value is negative (only meaningful where nz = 1)
// Each row is padded to a whole number of words, so rows never share a word.

#include <iostream>
#include <bit>        // std::popcount, std::countr_zero (C++20)
#include <cassert>
#include <cmath>
#include <cstdint>
#include <span>
#include <vector>

namespace ternary {

    class Tensor {
    public:
        static constexpr int kBits = 64;

        Tensor() = default;
        Tensor(int rows, int cols)
            : rows_(rows), cols_(cols),
            wpr_((cols + kBits - 1) / kBits),
            nz_(std::size_t(rows) * wpr_, 0),
            sign_(std::size_t(rows) * wpr_, 0) {}

        int rows() const { return rows_; }
        int cols() const { return cols_; }
        int words_per_row() const { return wpr_; }

        // ---- element access ---------------------------------------------------
        int8_t get(int r, int c) const {
            auto [w, m] = locate(r, c);
            if (!(nz_[w] & m)) return 0;
            return (sign_[w] & m) ? -1 : 1;
        }

        void set(int r, int c, int8_t v) {
            assert(v >= -1 && v <= 1);
            auto [w, m] = locate(r, c);
            nz_[w]   = v != 0 ? (nz_[w] | m)   : (nz_[w] & ~m);
            sign_[w] = v <  0 ? (sign_[w] | m) : (sign_[w] & ~m);
        }

        // Raw row access for kernels / serialization.
        const uint64_t* nz_row(int r)   const { return nz_.data()   + std::size_t(r) * wpr_; }
        const uint64_t* sign_row(int r) const { return sign_.data() + std::size_t(r) * wpr_; }

        // ---- quantization -----------------------------------------------------
        // BitNet-style "absmean": scale = mean(|w|); q = clamp(round(w/scale), -1, 1).
        // Returns the scale so you can dequantize: w ≈ scale * q.
        static Tensor quantize(std::span<const float> w, int rows, int cols,
                                    float* out_scale = nullptr) {
            assert(w.size() == std::size_t(rows) * cols);
            double sum = 0;
            for (float x : w) sum += std::fabs(x);
            float scale = float(sum / double(w.size()));
            if (scale == 0.f) scale = 1.f;

            Tensor t(rows, cols);
            for (int r = 0; r < rows; ++r)
                for (int c = 0; c < cols; ++c) {
                    float q = std::round(w[std::size_t(r) * cols + c] / scale);
                    t.set(r, c, int8_t(q > 1 ? 1 : q < -1 ? -1 : q));
                }
            if (out_scale) *out_scale = scale;
            return t;
        }

        // ---- kernels ------------------------------------------------------------
        // y = W * x with float activations. No multiplies: add where +1, subtract where -1.
        // Iterates only over set bits, so sparse rows are cheap.
        void matvec(std::span<const float> x, std::span<float> y) const {
            assert(int(x.size()) == cols_ && int(y.size()) == rows_);
            for (int r = 0; r < rows_; ++r) {
                const uint64_t* nz = nz_row(r);
                const uint64_t* sg = sign_row(r);
                float acc = 0.f;
                for (int w = 0; w < wpr_; ++w) {
                    uint64_t pos = nz[w] & ~sg[w];
                    uint64_t neg = nz[w] &  sg[w];
                    const float* xb = x.data() + w * kBits;
                    while (pos) { acc += xb[std::countr_zero(pos)]; pos &= pos - 1; }
                    while (neg) { acc -= xb[std::countr_zero(neg)]; neg &= neg - 1; }
                }
                y[r] = acc;
            }
        }

        // Dot product of row r with row s of another ternary tensor (same cols).
        // Pure bitwise: both-nonzero lanes count +1 if signs match, -1 if they differ.
        int dot_row(int r, const Tensor& other, int s) const {
            assert(other.cols_ == cols_);
            const uint64_t *an = nz_row(r), *as = sign_row(r);
            const uint64_t *bn = other.nz_row(s), *bs = other.sign_row(s);
            int acc = 0;
            for (int w = 0; w < wpr_; ++w) {
                uint64_t both = an[w] & bn[w];
                uint64_t diff = as[w] ^ bs[w];
                acc += std::popcount(both & ~diff) - std::popcount(both & diff);
            }
            return acc;
        }

    private:
        std::pair<std::size_t, uint64_t> locate(int r, int c) const {
            assert(r >= 0 && r < rows_ && c >= 0 && c < cols_);
            return { std::size_t(r) * wpr_ + c / kBits, uint64_t(1) << (c % kBits) };
        }

        int rows_ = 0, cols_ = 0, wpr_ = 0;
        std::vector<uint64_t> nz_, sign_;   // padding bits stay 0 -> contribute nothing
    };
}