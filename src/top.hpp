#pragma once
#include <cstdint>
#include <cstddef>
#include <vector>
#include <random>

struct TopConfig {
    float gamma = 1e-4f;         // EMA adaptivity rate (paper: 1e-4, decayed over training)
    float tau   = 1e-8f;         // threshold on |m|  (scale depends on your gradient magnitude!)
    bool  reset_on_move = true;  // zero the EMA after a step so a *new* consistent signal is
                                 // needed to keep moving (prevents +1 -> 0 -> -1 cascades)
};

class TernaryOptimizer {
public:
    TernaryOptimizer(size_t n, TernaryOptimizer cfg = {}) : cfg_(cfg), w_(n, 0), m_(n, 0.f) {}

    // Random init; p_zero = probability of a 0 weight.
    void init_random(uint64_t seed, float p_zero = 1.f / 3.f) {
        std::mt19937_64 rng(seed);
        std::uniform_real_distribution<float> u(0.f, 1.f);
        for (auto& w : w_) {
            float r = u(rng);
            w = (r < p_zero) ? 0 : (r < p_zero + (1.f - p_zero) * 0.5f ? -1 : +1);
        }
    }

    // g = dL/dw evaluated AT the current ternary weights (no STE needed for weights).
    // Returns the number of weights that moved (use it to log the flip rate).
    size_t step(const float* g) {
        const float gam = cfg_.gamma, tau = cfg_.tau;
        size_t moved = 0;
        for (size_t i = 0; i < w_.size(); ++i) {
            float   m = (1.f - gam) * m_[i] + gam * g[i];
            int8_t  w = w_[i];
            if (m > tau && w > -1) {            // consistent positive gradient -> decrease w
                --w; ++moved; if (cfg_.reset_on_move) m = 0.f;
            } else if (m < -tau && w < 1) {     // consistent negative gradient -> increase w
                ++w; ++moved; if (cfg_.reset_on_move) m = 0.f;
            }
            m_[i] = m; w_[i] = w;
        }
        return moved;
    }

    void set_gamma(float g) { cfg_.gamma = g; }
    void set_tau(float t)   { cfg_.tau = t; }

    const int8_t* weights() const { return w_.data(); }
    size_t size() const { return w_.size(); }

private:
    TopConfig            cfg_;
    std::vector<int8_t>  w_;   // {-1,0,+1}; later: pack 2 bits/weight
    std::vector<float>   m_;   // the only optimizer state (later: int16 + shift-based gamma)
};

// Multiply-free ternary dense layer: y[j] = sum_{w=+1} x[i] - sum_{w=-1} x[i]
// W is row-major [out x in].
inline void ternary_dense_forward(const int8_t* W, const float* x, float* y,
                                  size_t in, size_t out) {
    for (size_t j = 0; j < out; ++j) {
        float acc = 0.f;
        const int8_t* row = W + j * in;
        for (size_t i = 0; i < in; ++i) {
            if (row[i] > 0) acc += x[i];
            else if (row[i] < 0) acc -= x[i];
        }
        y[j] = acc;
    }
}