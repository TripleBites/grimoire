#pragma once

/******************************************************************************
* ternary.hpp - bit-packed ternary {-1, 0, +1} vectors, matrices and kernels.
*
* Single header, C++11, no dependencies beyond the standard library.
*
* ENCODING
*   Every trit is stored as one bit in each of two bitplanes:
*
*       value | nz | sign
*       ------+----+-----
*         0   | 0  |  0
*        +1   | 1  |  0
*        -1   | 1  |  1
*
*   nz   = 1 when the trit is nonzero.
*   sign = 1 when the trit is negative. (This is flipped from the first draft,
*          where 1 meant +1. With 1 = negative the sign bit behaves like an
*          ordinary sign bit: multiplying two trits XORs their signs.)
*
* INVARIANTS (every function here keeps them; every kernel relies on them)
*   I1. sign is a subset of nz. The fourth state (nz=0, sign=1) never occurs.
*       So each value has exactly one bit pattern, which is what makes memcmp
*       equality and deterministic files possible.
*   I2. Padding bits are zero in both planes. Padding = bits past the end of a
*       vector in its last word, or past the last column in a row's last word.
*       This lets kernels process whole words without masking the tail.
*
*   Handy identity that follows from I1:   value = nz - 2 * sign
*
* CONFIGURATION (define before including)
*   TERNARY_WORD_BITS            64 (default) or 32. On 32-bit ARM a 64-bit
*                                word is two registers; measure both.
*   TERNARY_NO_BUILTIN_POPCOUNT  Force the portable popcount.
******************************************************************************/

#include <cassert>
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <vector>

#ifndef TERNARY_WORD_BITS
#define TERNARY_WORD_BITS 64
#endif

namespace ternary
{

/******************************************************************************
* Word type and small helpers
******************************************************************************/
#if TERNARY_WORD_BITS == 64
typedef uint64_t word_t;
static const unsigned WORD_SHIFT = 6;
#elif TERNARY_WORD_BITS == 32
typedef uint32_t word_t;
static const unsigned WORD_SHIFT = 5;
#else
#error "TERNARY_WORD_BITS must be 32 or 64"
#endif

static const size_t WORD_BITS = TERNARY_WORD_BITS;
static const size_t WORD_MASK = WORD_BITS - 1;

/* Number of words needed to hold `trits` trits (per plane). */
inline size_t WordsFor(size_t trits)
{
    return (trits + WORD_MASK) >> WORD_SHIFT;
}

/* Mask of the valid (non-padding) bits in the LAST word of a `trits`-long run. */
inline word_t TailMask(size_t trits)
{
    const size_t rem = trits & WORD_MASK;
    return rem ? (word_t(1) << rem) - 1 : ~word_t(0);
}

inline int Popcount(word_t x)
{
#if (defined(__GNUC__) || defined(__clang__)) && !defined(TERNARY_NO_BUILTIN_POPCOUNT)
    #if TERNARY_WORD_BITS == 64
    return __builtin_popcountll(x);
    #else
    return __builtin_popcount(x);
    #endif
#else
    /* Classic SWAR popcount: sum bits in 2-, 4-, then 8-bit fields, then add
       the bytes together with one multiply. */
    #if TERNARY_WORD_BITS == 64
    x = x - ((x >> 1) & 0x5555555555555555ULL);
    x = (x & 0x3333333333333333ULL) + ((x >> 2) & 0x3333333333333333ULL);
    x = (x + (x >> 4)) & 0x0F0F0F0F0F0F0F0FULL;
    return int((x * 0x0101010101010101ULL) >> 56);
    #else
    x = x - ((x >> 1) & 0x55555555U);
    x = (x & 0x33333333U) + ((x >> 2) & 0x33333333U);
    x = (x + (x >> 4)) & 0x0F0F0F0FU;
    return int((x * 0x01010101U) >> 24);
    #endif
#endif
}

/******************************************************************************
* Spans: non-owning (nz, sign, size) triples.
*
* Kernels take spans, so the same code runs on a TritBuffer, on one row of a
* TritMatrix, or on memory you manage yourself. They are three words wide;
* pass them by value.
******************************************************************************/
struct ConstTritSpan
{
    const word_t* nz;
    const word_t* sign;
    size_t        size;     /* in trits */

    ConstTritSpan(const word_t* nz_plane, const word_t* sign_plane, size_t trit_count)
        :   nz(nz_plane), sign(sign_plane), size(trit_count)
    {
    }

    size_t Words() const { return WordsFor(size); }
};

struct TritSpan
{
    word_t* nz;
    word_t* sign;
    size_t  size;           /* in trits */

    TritSpan(word_t* nz_plane, word_t* sign_plane, size_t trit_count)
        :   nz(nz_plane), sign(sign_plane), size(trit_count)
    {
    }

    size_t Words() const { return WordsFor(size); }

    operator ConstTritSpan() const { return ConstTritSpan(nz, sign, size); }
};

/******************************************************************************
* Single-trit access. Not for hot loops; the kernels below work a word at a
* time. These exist for setup, debugging and tests.
******************************************************************************/
inline int GetTrit(const word_t* nz, const word_t* sign, size_t i)
{
    const size_t w = i >> WORD_SHIFT;
    const size_t s = i & WORD_MASK;
    const int    n = int((nz[w]   >> s) & 1);
    const int    g = int((sign[w] >> s) & 1);
    return n - 2 * g;                               /* identity from I1 */
}

/* v must be -1, 0 or +1. Overwrites whatever was there, in one step. */
inline void SetTrit(word_t* nz, word_t* sign, size_t i, int v)
{
    assert(v >= -1 && v <= 1);
    const size_t w   = i >> WORD_SHIFT;
    const word_t bit = word_t(1) << (i & WORD_MASK);
    nz[w]   = (nz[w]   & ~bit) | (v != 0 ? bit : word_t(0));
    sign[w] = (sign[w] & ~bit) | (v <  0 ? bit : word_t(0));
}

/******************************************************************************
* Word-level kernels
******************************************************************************/

/* Dot product of two ternary runs of `words` words each.
*
*   m = a.nz & b.nz            positions where BOTH are nonzero. Everything
*                              else contributes 0 to the sum.
*   (a.sign ^ b.sign) & m      of those, the positions where the signs differ.
*                              Those contribute -1; the rest of m contribute +1.
*
*   dot = (#same) - (#differ) = popcount(m) - 2 * popcount(differ)
*
* Two popcounts and three logic ops per word. Padding is zero in nz (I2), so it
* drops out of m and whole words can be processed without a tail mask. */
inline int32_t DotWords(const word_t* a_nz, const word_t* a_sign,
                        const word_t* b_nz, const word_t* b_sign,
                        size_t words)
{
    int32_t both   = 0;
    int32_t differ = 0;
    for (size_t w = 0; w < words; ++w)
    {
        const word_t m = a_nz[w] & b_nz[w];
        both   += Popcount(m);
        differ += Popcount((a_sign[w] ^ b_sign[w]) & m);
    }
    return both - 2 * differ;
}

/* Move the trits selected by `mask` one step toward +1, saturating:
*       -1 -> 0,   0 -> +1,   +1 -> +1
*
*   In (nz, sign) terms: (1,1)->(0,0), (0,0)->(1,0), (1,0)->(1,0).
*   The new nz bit is 1 unless the trit was -1, i.e. it is ~sign.
*   The new sign bit is always 0.
*
* `mask` must not select padding bits. */
inline void StepUpWord(word_t& nz, word_t& sign, word_t mask)
{
    nz   = (nz & ~mask) | (~sign & mask);
    sign = sign & ~mask;
}

/* Move the trits selected by `mask` one step toward -1, saturating:
*       +1 -> 0,   0 -> -1,   -1 -> -1
*
*   In (nz, sign) terms: (1,0)->(0,0), (0,0)->(1,1), (1,1)->(1,1).
*   The result is -1 unless the trit was +1. "Was +1" is (nz & ~sign), so
*   "result is -1" is ~(nz & ~sign) = (~nz | sign). A result of -1 sets both
*   bits, a result of 0 clears both, so nz and sign get the same new bit.
*
* `mask` must not select padding bits. */
inline void StepDownWord(word_t& nz, word_t& sign, word_t mask)
{
    const word_t t = (~nz | sign) & mask;
    nz   = (nz   & ~mask) | t;
    sign = (sign & ~mask) | t;
}

/******************************************************************************
* Span-level queries
******************************************************************************/
inline int32_t Dot(ConstTritSpan a, ConstTritSpan b)
{
    assert(a.size == b.size);
    return DotWords(a.nz, a.sign, b.nz, b.sign, a.Words());
}

/* Number of nonzero trits. sparsity = 1 - CountNonzero / size. */
inline size_t CountNonzero(ConstTritSpan a)
{
    size_t count = 0;
    for (size_t w = 0, words = a.Words(); w < words; ++w)
    {
        count += size_t(Popcount(a.nz[w]));
    }
    return count;
}

/* Sum of all trits: (#nonzero) - 2 * (#negative), the per-trit identity
   value = nz - 2 * sign added up over the whole run. */
inline int32_t Sum(ConstTritSpan a)
{
    int32_t nonzero  = 0;
    int32_t negative = 0;
    for (size_t w = 0, words = a.Words(); w < words; ++w)
    {
        nonzero  += Popcount(a.nz[w]);
        negative += Popcount(a.sign[w]);
    }
    return nonzero - 2 * negative;
}

/* True if both invariants hold. Call it in asserts after any code that writes
   the planes directly. */
inline bool IsCanonical(ConstTritSpan a)
{
    const size_t words = a.Words();
    for (size_t w = 0; w < words; ++w)
    {
        if (a.sign[w] & ~a.nz[w])
        {
            return false;                                   /* I1 broken */
        }
    }
    if (words > 0 && (a.nz[words - 1] & ~TailMask(a.size)))
    {
        return false;                                       /* I2 broken */
    }
    return true;
}

/* Value equality. A plain memcmp is only correct because of I1 and I2. */
inline bool Equal(ConstTritSpan a, ConstTritSpan b)
{
    if (a.size != b.size)
    {
        return false;
    }
    const size_t bytes = a.Words() * sizeof(word_t);
    return bytes == 0
        || (std::memcmp(a.nz, b.nz, bytes) == 0 && std::memcmp(a.sign, b.sign, bytes) == 0);
}

/* Set every trit to v, keeping padding zero. */
inline void Fill(TritSpan a, int v)
{
    assert(v >= -1 && v <= 1);
    const size_t words = a.Words();
    if (words == 0)
    {
        return;
    }
    const word_t nz_word   = (v != 0) ? ~word_t(0) : word_t(0);
    const word_t sign_word = (v <  0) ? ~word_t(0) : word_t(0);
    for (size_t w = 0; w < words; ++w)
    {
        a.nz[w]   = nz_word;
        a.sign[w] = sign_word;
    }
    const word_t tail = TailMask(a.size);
    a.nz[words - 1]   &= tail;
    a.sign[words - 1] &= tail;
}

/******************************************************************************
* TritBuffer: an owning ternary vector (activations, biases, one-off vectors).
******************************************************************************/
class TritBuffer
{
    private:
        size_t              size_;
        std::vector<word_t> nz_;
        std::vector<word_t> sign_;
    public:
        /* All trits start at 0. */
        explicit TritBuffer(size_t trit_count = 0)
            :   size_(trit_count),
                nz_(WordsFor(trit_count)),
                sign_(WordsFor(trit_count))
        {
        }

        size_t Size()  const { return size_; }
        size_t Words() const { return nz_.size(); }

        int Get(size_t i) const
        {
            assert(i < size_);
            return GetTrit(nz_.data(), sign_.data(), i);
        }
        void Set(size_t i, int v)
        {
            assert(i < size_);
            SetTrit(nz_.data(), sign_.data(), i, v);
        }

        TritSpan      Span()       { return TritSpan(nz_.data(), sign_.data(), size_); }
        ConstTritSpan Span() const { return ConstTritSpan(nz_.data(), sign_.data(), size_); }

        /* Lets a TritBuffer be passed straight to any kernel. */
        operator TritSpan()            { return Span(); }
        operator ConstTritSpan() const { return Span(); }
};

/******************************************************************************
* TritMatrix: an owning rows x cols ternary matrix (weights).
*
* LAYOUT
*   Structure of arrays: one contiguous block per plane, row-major.
*   Each row is padded up to a whole number of words (the "stride"), so
*
*       row r starts at word  r * WordsPerRow()   in both planes
*       trit (r, c) is bit    c & WORD_MASK       of word  r * stride + (c >> WORD_SHIFT)
*
*   Because every row starts on a word boundary, row r is a valid span of
*   `cols` trits, and Dot(row, x) is the same kernel as vector-vector Dot.
*   The cost is up to WORD_BITS - 1 padding trits per row.
*
*   For a dense layer use rows = outputs, cols = inputs, so the forward pass
*   is one contiguous sweep per output neuron.
******************************************************************************/
class TritMatrix
{
    private:
        size_t              rows_;
        size_t              cols_;
        size_t              stride_;    /* words per row; declared before the planes on purpose */
        std::vector<word_t> nz_;
        std::vector<word_t> sign_;
    public:
        TritMatrix()
            :   rows_(0), cols_(0), stride_(0)
        {
        }

        /* All trits start at 0. */
        TritMatrix(size_t rows, size_t cols)
            :   rows_(rows),
                cols_(cols),
                stride_(WordsFor(cols)),
                nz_(rows * stride_),
                sign_(rows * stride_)
        {
        }

        size_t Rows()        const { return rows_; }
        size_t Cols()        const { return cols_; }
        size_t WordsPerRow() const { return stride_; }

        int Get(size_t r, size_t c) const
        {
            assert(r < rows_ && c < cols_);
            return GetTrit(RowNz(r), RowSign(r), c);
        }
        void Set(size_t r, size_t c, int v)
        {
            assert(r < rows_ && c < cols_);
            SetTrit(RowNz(r), RowSign(r), c, v);
        }

        /* Raw row pointers for kernels. Writers must keep I1 and I2. */
        const word_t* RowNz(size_t r)   const { assert(r < rows_); return nz_.data()   + r * stride_; }
        const word_t* RowSign(size_t r) const { assert(r < rows_); return sign_.data() + r * stride_; }
        word_t*       RowNz(size_t r)         { assert(r < rows_); return nz_.data()   + r * stride_; }
        word_t*       RowSign(size_t r)       { assert(r < rows_); return sign_.data() + r * stride_; }

        ConstTritSpan Row(size_t r) const { return ConstTritSpan(RowNz(r), RowSign(r), cols_); }
        TritSpan      Row(size_t r)       { return TritSpan(RowNz(r), RowSign(r), cols_); }

        void Fill(int v)
        {
            for (size_t r = 0; r < rows_; ++r)
            {
                ternary::Fill(Row(r), v);
            }
        }

        size_t CountNonzero() const
        {
            size_t count = 0;
            for (size_t r = 0; r < rows_; ++r)
            {
                count += ternary::CountNonzero(Row(r));
            }
            return count;
        }

        bool IsCanonical() const
        {
            for (size_t r = 0; r < rows_; ++r)
            {
                if (!ternary::IsCanonical(Row(r)))
                {
                    return false;
                }
            }
            return true;
        }
};

/******************************************************************************
* Forward-pass kernels
******************************************************************************/

/* out[r] = dot(W[r, :], x)   for every row. `out` holds W.Rows() integers.
   Each result lies in [-cols, +cols]. */
inline void MatVec(const TritMatrix& W, ConstTritSpan x, int32_t* out)
{
    assert(x.size == W.Cols());
    const size_t words = W.WordsPerRow();
    for (size_t r = 0, rows = W.Rows(); r < rows; ++r)
    {
        out[r] = DotWords(W.RowNz(r), W.RowSign(r), x.nz, x.sign, words);
    }
}

/* Ternary activation with a dead zone of half-width theta (theta >= 0):
*
*       out[i] = +1 if in[i] >  theta
*                -1 if in[i] < -theta
*                 0 otherwise
*
* Builds each output word in two locals and stores it once, instead of doing
* a read-modify-write per trit. The comparisons are used as 0/1 values so the
* loop has no data-dependent branches. Rewriting whole words from zero also
* keeps I1 and I2 without any extra work. */
inline void Ternarize(const int32_t* in, int32_t theta, TritSpan out)
{
    assert(theta >= 0);
    size_t i = 0;
    for (size_t w = 0; i < out.size; ++w)
    {
        word_t       nz_word   = 0;
        word_t       sign_word = 0;
        const size_t left      = out.size - i;
        const size_t n         = left < WORD_BITS ? left : WORD_BITS;
        for (size_t k = 0; k < n; ++k, ++i)
        {
            const word_t pos = word_t(in[i] >  theta);
            const word_t neg = word_t(in[i] < -theta);
            nz_word   |= (pos | neg) << k;
            sign_word |= neg << k;
        }
        out.nz[w]   = nz_word;
        out.sign[w] = sign_word;
    }
}

/* One dense ternary layer: out = Ternarize(W * x, theta), without storing the
   integer pre-activations. Use MatVec + Ternarize instead when you need them
   (for example as the prediction in a predictive-coding error).

   `out` holds W.Rows() trits and must not alias `x`. */
inline void Forward(const TritMatrix& W, ConstTritSpan x, int32_t theta, TritSpan out)
{
    assert(x.size == W.Cols());
    assert(out.size == W.Rows());
    assert(theta >= 0);
    const size_t words = W.WordsPerRow();
    size_t r = 0;
    for (size_t w = 0; r < out.size; ++w)
    {
        word_t       nz_word   = 0;
        word_t       sign_word = 0;
        const size_t left      = out.size - r;
        const size_t n         = left < WORD_BITS ? left : WORD_BITS;
        for (size_t k = 0; k < n; ++k, ++r)
        {
            const int32_t s   = DotWords(W.RowNz(r), W.RowSign(r), x.nz, x.sign, words);
            const word_t  pos = word_t(s >  theta);
            const word_t  neg = word_t(s < -theta);
            nz_word   |= (pos | neg) << k;
            sign_word |= neg << k;
        }
        out.nz[w]   = nz_word;
        out.sign[w] = sign_word;
    }
}

/******************************************************************************
* Ternary Bop update
*
* Bop (Helwegen et al. 2019, Algorithm 2) for weights in {-1, +1}:
*
*       m <- (1 - gamma) * m + gamma * g
*       if |m| > tau and sign(m) == sign(w):   w <- -w
*
* A positive m means the loss falls if the weight gets smaller, so the weight
* is pushed toward -1; a negative m pushes it toward +1. A weight that already
* sits on the side m points away from has nowhere to go.
*
* THIS IS ONE POSSIBLE TERNARY RULE, NOT THE PAPER'S. With three states a
* "flip" becomes a single step, and the step out of zero gets its own
* threshold:
*
*       w = +1 and m >  tau_prune:   w <- 0
*       w = -1 and m < -tau_prune:   w <- 0
*       w =  0 and m >  tau_grow:    w <- -1
*       w =  0 and m < -tau_grow:    w <- +1
*
* Why two thresholds: m barely changes between consecutive steps (gamma is
* small), so with tau_grow == tau_prune a weight that is pushed to 0 gets
* pushed on to the opposite sign on the very next step. Zero is then only a
* stopover and the network ends up effectively binary. With
* tau_grow > tau_prune a weight stays at 0 for as long as
* tau_prune < |m| <= tau_grow, and that band is what produces sparsity.
*
* As in the paper, m is not reset when a weight changes.
******************************************************************************/
struct BopParams
{
    float gamma;        /* adaptivity rate of the moving average, in (0, 1] */
    float tau_prune;    /* |m| needed to move a nonzero weight to 0         */
    float tau_grow;     /* |m| needed to move a zero weight to -1 or +1     */
};

inline bool IsValid(const BopParams& p)
{
    /* Negative thresholds would let one weight be pushed both ways at once. */
    return p.gamma > 0.0f && p.gamma <= 1.0f && p.tau_prune >= 0.0f && p.tau_grow >= 0.0f;
}

/* Apply one word's worth of pushes and return how many trits changed.
   `up` and `down` must not overlap and must not select padding. */
inline size_t ApplyPushWord(word_t& nz, word_t& sign, word_t up, word_t down)
{
    /* Drop weights that are already at the end they are pushed toward, so the
       popcount counts real changes only. */
    down &= ~sign;                  /* sign = 1 means already -1    */
    up   &= ~(nz & ~sign);          /* nz & ~sign means already +1  */

    StepDownWord(nz, sign, down);
    StepUpWord(nz, sign, up);
    return size_t(Popcount(up | down));
}

/* One update over a run of weights. m and g hold one float per trit.
   Returns the number of weights that changed (the paper's flip count, worth
   logging: it is the main health signal for gamma and tau). */
inline size_t BopStep(TritSpan w, float* m, const float* g, const BopParams& p)
{
    assert(IsValid(p));
    const float keep    = 1.0f - p.gamma;
    size_t      changed = 0;
    size_t      i       = 0;
    for (size_t word = 0; i < w.size; ++word)
    {
        const word_t nz_word = w.nz[word];
        word_t       up      = 0;           /* trits pushed toward +1 */
        word_t       down    = 0;           /* trits pushed toward -1 */
        const size_t left    = w.size - i;
        const size_t n       = left < WORD_BITS ? left : WORD_BITS;
        for (size_t k = 0; k < n; ++k, ++i)
        {
            const float mi  = keep * m[i] + p.gamma * g[i];
            const float tau = ((nz_word >> k) & 1) ? p.tau_prune : p.tau_grow;
            m[i] = mi;
            down |= word_t(mi >  tau) << k;
            up   |= word_t(mi < -tau) << k;
        }
        changed += ApplyPushWord(w.nz[word], w.sign[word], up, down);
    }
    return changed;
}

/* Same, over a whole matrix. m and g are dense row-major arrays of
   W.Rows() * W.Cols() floats: element (r, c) is at r * W.Cols() + c.
   (Dense, with no per-row padding, unlike the trit planes.) */
inline size_t BopStep(TritMatrix& W, float* m, const float* g, const BopParams& p)
{
    size_t       changed = 0;
    const size_t cols    = W.Cols();
    for (size_t r = 0, rows = W.Rows(); r < rows; ++r)
    {
        changed += BopStep(W.Row(r), m + r * cols, g + r * cols, p);
    }
    return changed;
}

/* Bop update for ONE training sample, without building the gradient matrix.
*
* For a dense layer s = W * x, the gradient for one sample is an outer
* product:
*
*       dL/dW[r][c] = delta[r] * x[c]       where delta[r] = dL/ds[r]
*
* x[c] is a trit, so along row r the gradient only takes the values
* -delta[r], 0 and +delta[r]. That means the caller supplies one float per
* output (delta) plus the layer's input, instead of rows * cols floats.
* The result is identical to calling BopStep with g[r][c] = delta[r] * x[c].
*
* The sign convention is the caller's: delta must be the derivative of
* whatever is being MINIMISED with respect to the pre-activation. */
inline size_t BopStepOuter(TritSpan w, float* m, float delta, ConstTritSpan x, const BopParams& p)
{
    assert(IsValid(p));
    assert(w.size == x.size);
    const float keep    = 1.0f - p.gamma;
    const float step    = p.gamma * delta;      /* gamma * g where x = +1 */
    size_t      changed = 0;
    size_t      i       = 0;
    for (size_t word = 0; i < w.size; ++word)
    {
        const word_t nz_word = w.nz[word];
        const word_t x_nz    = x.nz[word];
        const word_t x_sign  = x.sign[word];
        word_t       up      = 0;
        word_t       down    = 0;
        const size_t left    = w.size - i;
        const size_t n       = left < WORD_BITS ? left : WORD_BITS;
        for (size_t k = 0; k < n; ++k, ++i)
        {
            /* x as -1.0, 0.0 or +1.0, from value = nz - 2 * sign */
            const float xi  = float(int((x_nz >> k) & 1) - 2 * int((x_sign >> k) & 1));
            const float mi  = keep * m[i] + step * xi;
            const float tau = ((nz_word >> k) & 1) ? p.tau_prune : p.tau_grow;
            m[i] = mi;
            down |= word_t(mi >  tau) << k;
            up   |= word_t(mi < -tau) << k;
        }
        changed += ApplyPushWord(w.nz[word], w.sign[word], up, down);
    }
    return changed;
}

/* Same, over a whole layer: delta holds W.Rows() floats, x holds W.Cols()
   trits, m is the dense row-major momentum array as in BopStep. */
inline size_t BopStepOuter(TritMatrix& W, float* m, const float* delta, ConstTritSpan x,
                           const BopParams& p)
{
    assert(x.size == W.Cols());
    size_t       changed = 0;
    const size_t cols    = W.Cols();
    for (size_t r = 0, rows = W.Rows(); r < rows; ++r)
    {
        changed += BopStepOuter(W.Row(r), m + r * cols, delta[r], x, p);
    }
    return changed;
}

/******************************************************************************
* Compact byte encoding for files
*
* In memory a trit costs 2 bits. On disk, five trits fit in one byte because
* 3^5 = 243 <= 256: that is 1.6 bits per trit against an ideal of
* log2(3) = 1.585. The byte holds the five trits as base-3 digits (digit =
* trit + 1), first trit in the least significant digit. A final short group
* is filled with zero trits. Output is plain bytes, so there is no byte-order
* question, and the same values always give the same bytes (I1).
*
* These only convert to and from a byte buffer; the file header (dimensions,
* version) and the I/O are left to the caller.
******************************************************************************/
inline size_t PackedBytes(size_t trits)
{
    return (trits + 4) / 5;
}

/* Writes PackedBytes(in.size) bytes to out. */
inline void Pack(ConstTritSpan in, uint8_t* out)
{
    for (size_t i = 0; i < in.size; i += 5)
    {
        unsigned byte = 0;
        for (size_t j = 5; j-- > 0; )
        {
            const int t = (i + j < in.size) ? GetTrit(in.nz, in.sign, i + j) : 0;
            byte = byte * 3 + unsigned(t + 1);
        }
        *out++ = uint8_t(byte);
    }
}

/* Reads PackedBytes(out.size) bytes from in. Returns false on a byte that is
   not a valid base-3 group (> 242), which means the data is corrupt. */
inline bool Unpack(const uint8_t* in, TritSpan out)
{
    const size_t bytes = out.Words() * sizeof(word_t);
    if (bytes > 0)
    {
        std::memset(out.nz, 0, bytes);
        std::memset(out.sign, 0, bytes);
    }
    for (size_t i = 0; i < out.size; i += 5)
    {
        unsigned byte = *in++;
        if (byte > 242)
        {
            return false;
        }
        for (size_t j = 0; j < 5 && i + j < out.size; ++j)
        {
            SetTrit(out.nz, out.sign, i + j, int(byte % 3) - 1);
            byte /= 3;
        }
    }
    return true;
}

/* Matrix versions: rows are packed one after another, each starting on a byte
   boundary, PackedBytes(cols) bytes per row. */
inline size_t PackedBytes(const TritMatrix& W)
{
    return W.Rows() * PackedBytes(W.Cols());
}

inline void Pack(const TritMatrix& W, uint8_t* out)
{
    const size_t row_bytes = PackedBytes(W.Cols());
    for (size_t r = 0, rows = W.Rows(); r < rows; ++r)
    {
        Pack(W.Row(r), out + r * row_bytes);
    }
}

inline bool Unpack(const uint8_t* in, TritMatrix& W)
{
    const size_t row_bytes = PackedBytes(W.Cols());
    for (size_t r = 0, rows = W.Rows(); r < rows; ++r)
    {
        if (!Unpack(in + r * row_bytes, W.Row(r)))
        {
            return false;
        }
    }
    return true;
}

} /* namespace ternary */