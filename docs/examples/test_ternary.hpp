/******************************************************************************
* test_ternary.cpp - checks every kernel in ternary.hpp against a plain
* one-int8-per-trit implementation, at sizes on both sides of word boundaries.
*
* Build and run:
*   g++ -std=c++11 -Wall -Wextra -O2 test_ternary.cpp -o test_ternary && ./test_ternary
*
* Also worth running with:
*   -DTERNARY_WORD_BITS=32
*   -DTERNARY_NO_BUILTIN_POPCOUNT
*   -fsanitize=address,undefined
******************************************************************************/

#include "ternary.hpp"

#include <cmath>
#include <cstdio>
#include <random>
#include <vector>

using namespace ternary;

static int g_checks   = 0;
static int g_failures = 0;

#define CHECK(cond)                                                         \
    do                                                                      \
    {                                                                       \
        ++g_checks;                                                         \
        if (!(cond))                                                        \
        {                                                                   \
            ++g_failures;                                                   \
            std::printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond);     \
        }                                                                   \
    } while (0)

typedef std::vector<int8_t> Ref;            /* the reference: one int8 per trit */

/* Sizes chosen to sit on and around 32- and 64-bit word boundaries. */
static const size_t SIZES[] = { 0, 1, 2, 5, 31, 32, 33, 63, 64, 65, 127, 128, 129, 200, 257 };
static const size_t NUM_SIZES = sizeof(SIZES) / sizeof(SIZES[0]);

static Ref RandomTrits(size_t n, std::mt19937& rng)
{
    std::uniform_int_distribution<int> dist(-1, 1);
    Ref v(n);
    for (size_t i = 0; i < n; ++i)
    {
        v[i] = int8_t(dist(rng));
    }
    return v;
}

static void Load(TritSpan dst, const Ref& src)
{
    for (size_t i = 0; i < src.size(); ++i)
    {
        SetTrit(dst.nz, dst.sign, i, src[i]);
    }
}

static bool Matches(ConstTritSpan a, const Ref& ref)
{
    if (a.size != ref.size())
    {
        return false;
    }
    for (size_t i = 0; i < ref.size(); ++i)
    {
        if (GetTrit(a.nz, a.sign, i) != ref[i])
        {
            return false;
        }
    }
    return true;
}

static int Clamp(int v)
{
    return v < -1 ? -1 : (v > 1 ? 1 : v);
}

/*****************************************************************************/
static void TestHelpers(std::mt19937& rng)
{
    CHECK(WordsFor(0) == 0);
    CHECK(WordsFor(1) == 1);
    CHECK(WordsFor(WORD_BITS) == 1);
    CHECK(WordsFor(WORD_BITS + 1) == 2);

    CHECK(TailMask(1) == word_t(1));
    CHECK(TailMask(3) == word_t(7));
    CHECK(TailMask(WORD_BITS) == ~word_t(0));
    CHECK(TailMask(WORD_BITS + 2) == word_t(3));

    CHECK(Popcount(word_t(0)) == 0);
    CHECK(Popcount(~word_t(0)) == int(WORD_BITS));
    for (int t = 0; t < 2000; ++t)
    {
        const word_t x = word_t((uint64_t(rng()) << 32) | uint64_t(rng()));
        int naive = 0;
        for (size_t b = 0; b < WORD_BITS; ++b)
        {
            naive += int((x >> b) & 1);
        }
        CHECK(Popcount(x) == naive);
    }
}

/*****************************************************************************/
static void TestBuffer(std::mt19937& rng)
{
    for (size_t s = 0; s < NUM_SIZES; ++s)
    {
        const size_t n = SIZES[s];
        TritBuffer   buf(n);
        CHECK(buf.Size() == n);
        CHECK(buf.Words() == WordsFor(n));
        CHECK(IsCanonical(buf));
        CHECK(CountNonzero(buf) == 0);              /* starts all zero */

        const Ref ref = RandomTrits(n, rng);
        Load(buf, ref);
        CHECK(Matches(buf, ref));
        CHECK(IsCanonical(buf));

        /* Every one of the 9 old -> new transitions, in a single Set call,
           without disturbing any other trit. */
        Ref cur = ref;
        for (size_t i = 0; i < n; ++i)
        {
            for (int v = -1; v <= 1; ++v)
            {
                buf.Set(i, v);
                cur[i] = int8_t(v);
                CHECK(buf.Get(i) == v);
            }
            buf.Set(i, ref[i]);
            cur[i] = ref[i];
        }
        CHECK(Matches(buf, cur));
        CHECK(IsCanonical(buf));
    }
}

/*****************************************************************************/
static void TestQueries(std::mt19937& rng)
{
    for (size_t s = 0; s < NUM_SIZES; ++s)
    {
        const size_t n = SIZES[s];
        for (int rep = 0; rep < 20; ++rep)
        {
            const Ref ra = RandomTrits(n, rng);
            const Ref rb = RandomTrits(n, rng);
            TritBuffer a(n), b(n);
            Load(a, ra);
            Load(b, rb);

            int32_t dot = 0, sum = 0;
            size_t  nonzero = 0;
            for (size_t i = 0; i < n; ++i)
            {
                dot     += ra[i] * rb[i];
                sum     += ra[i];
                nonzero += (ra[i] != 0);
            }
            CHECK(Dot(a, b) == dot);
            CHECK(Dot(b, a) == dot);
            CHECK(Dot(a, a) == int32_t(nonzero));       /* x . x = number of nonzeros */
            CHECK(Sum(a) == sum);
            CHECK(CountNonzero(a) == nonzero);

            /* Equality: equal to a rebuilt copy, unequal after any one change. */
            TritBuffer c(n);
            Load(c, ra);
            CHECK(Equal(a, c));
            if (n > 0)
            {
                const size_t i = size_t(rng()) % n;
                c.Set(i, Clamp(ra[i] + 1) == ra[i] ? ra[i] - 1 : ra[i] + 1);
                CHECK(!Equal(a, c));
            }
            TritBuffer longer(n + 1);
            CHECK(!Equal(a, longer));
        }

        for (int v = -1; v <= 1; ++v)
        {
            TritBuffer f(n);
            Load(f, RandomTrits(n, rng));
            Fill(f, v);
            CHECK(Matches(f, Ref(n, int8_t(v))));
            CHECK(IsCanonical(f));                       /* padding stayed zero */
            CHECK(Sum(f) == v * int32_t(n));
        }
    }

    /* IsCanonical must reject both kinds of violation. */
    {
        TritBuffer b(10);
        b.Span().sign[0] = 1;                            /* sign without nz */
        CHECK(!IsCanonical(b));
    }
    {
        TritBuffer b(10);
        b.Span().nz[0] = word_t(1) << 10;                /* bit in the padding */
        CHECK(!IsCanonical(b));
    }
}

/*****************************************************************************/
static void TestStepWords(std::mt19937& rng)
{
    for (int rep = 0; rep < 500; ++rep)
    {
        const Ref    ref  = RandomTrits(WORD_BITS, rng);
        const word_t mask = word_t((uint64_t(rng()) << 32) | uint64_t(rng()));

        TritBuffer up(WORD_BITS), down(WORD_BITS);
        Load(up, ref);
        Load(down, ref);
        StepUpWord(up.Span().nz[0], up.Span().sign[0], mask);
        StepDownWord(down.Span().nz[0], down.Span().sign[0], mask);

        for (size_t i = 0; i < WORD_BITS; ++i)
        {
            const bool selected = ((mask >> i) & 1) != 0;
            CHECK(up.Get(i)   == (selected ? Clamp(ref[i] + 1) : ref[i]));
            CHECK(down.Get(i) == (selected ? Clamp(ref[i] - 1) : ref[i]));
        }
        CHECK(IsCanonical(up));
        CHECK(IsCanonical(down));
    }
}

/*****************************************************************************/
static void TestMatrix(std::mt19937& rng)
{
    static const size_t DIMS[][2] = {
        { 0, 0 }, { 0, 7 }, { 3, 0 }, { 1, 1 }, { 3, 5 }, { 7, 64 }, { 5, 65 },
        { 64, 3 }, { 65, 33 }, { 70, 130 }, { 10, 784 }
    };
    const size_t num_dims = sizeof(DIMS) / sizeof(DIMS[0]);

    for (size_t d = 0; d < num_dims; ++d)
    {
        const size_t rows = DIMS[d][0];
        const size_t cols = DIMS[d][1];

        TritMatrix W(rows, cols);
        CHECK(W.Rows() == rows && W.Cols() == cols);
        CHECK(W.WordsPerRow() == WordsFor(cols));
        CHECK(W.CountNonzero() == 0);

        const Ref ref = RandomTrits(rows * cols, rng);  /* row-major reference */
        size_t    nonzero = 0;
        for (size_t r = 0; r < rows; ++r)
        {
            for (size_t c = 0; c < cols; ++c)
            {
                W.Set(r, c, ref[r * cols + c]);
                nonzero += (ref[r * cols + c] != 0);
            }
        }
        bool all_match = true;
        for (size_t r = 0; r < rows; ++r)
        {
            for (size_t c = 0; c < cols; ++c)
            {
                all_match = all_match && (W.Get(r, c) == ref[r * cols + c]);
            }
            /* Row(r) is the same data seen as a vector of `cols` trits. */
            all_match = all_match
                && Matches(W.Row(r), Ref(ref.begin() + long(r * cols), ref.begin() + long((r + 1) * cols)));
        }
        CHECK(all_match);
        CHECK(W.IsCanonical());
        CHECK(W.CountNonzero() == nonzero);

        /* MatVec, Ternarize and Forward against the reference. */
        const Ref  rx = RandomTrits(cols, rng);
        TritBuffer x(cols);
        Load(x, rx);

        std::vector<int32_t> expect(rows, 0);
        for (size_t r = 0; r < rows; ++r)
        {
            for (size_t c = 0; c < cols; ++c)
            {
                expect[r] += ref[r * cols + c] * rx[c];
            }
        }
        std::vector<int32_t> got(rows + 1, 12345);      /* +1: canary past the end */
        MatVec(W, x, got.data());
        bool matvec_ok = (got[rows] == 12345);
        for (size_t r = 0; r < rows; ++r)
        {
            matvec_ok = matvec_ok && (got[r] == expect[r]);
        }
        CHECK(matvec_ok);

        for (int32_t theta = 0; theta <= 3; ++theta)
        {
            Ref want(rows);
            for (size_t r = 0; r < rows; ++r)
            {
                want[r] = int8_t(expect[r] > theta ? 1 : (expect[r] < -theta ? -1 : 0));
            }

            TritBuffer a(rows), b(rows);
            Load(a, RandomTrits(rows, rng));            /* stale contents must be overwritten */
            Load(b, RandomTrits(rows, rng));
            Ternarize(expect.data(), theta, a);
            Forward(W, x, theta, b);
            CHECK(Matches(a, want));
            CHECK(Matches(b, want));
            CHECK(IsCanonical(a));
            CHECK(IsCanonical(b));
        }

        /* Fill keeps every row's padding clean. */
        W.Fill(-1);
        CHECK(W.IsCanonical());
        CHECK(W.CountNonzero() == rows * cols);
    }

    /* Writing one row must not leak into its neighbours. */
    {
        TritMatrix W(3, 70);
        Fill(W.Row(1), 1);
        CHECK(CountNonzero(W.Row(0)) == 0);
        CHECK(CountNonzero(W.Row(1)) == 70);
        CHECK(CountNonzero(W.Row(2)) == 0);
    }
}

/*****************************************************************************/
/* The ternary Bop rule, written the obvious way for one weight. */
static int NaiveBop(int w, float m, const BopParams& p)
{
    if (w ==  1 && m >  p.tau_prune) { return 0; }
    if (w == -1 && m < -p.tau_prune) { return 0; }
    if (w ==  0 && m >  p.tau_grow)  { return -1; }
    if (w ==  0 && m < -p.tau_grow)  { return 1; }
    return w;
}

static void TestBop(std::mt19937& rng)
{
    BopParams p;
    p.gamma     = 0.2f;
    p.tau_prune = 0.05f;
    p.tau_grow  = 0.15f;

    std::uniform_real_distribution<float> grad(-1.0f, 1.0f);
    size_t seen[4] = { 0, 0, 0, 0 };        /* +1->0, -1->0, 0->-1, 0->+1 */

    /* Dense-gradient version, vector and matrix entry points. */
    for (size_t s = 0; s < NUM_SIZES; ++s)
    {
        const size_t rows = 3;
        const size_t cols = SIZES[s];
        const size_t n    = rows * cols;

        Ref        ref = RandomTrits(n, rng);
        TritMatrix W(rows, cols);
        for (size_t i = 0; i < n; ++i)
        {
            W.Set(i / cols, i % cols, ref[i]);
        }
        std::vector<float> m(n, 0.0f), m_ref(n, 0.0f), g(n);

        for (int step = 0; step < 30; ++step)
        {
            size_t expect_changed = 0;
            for (size_t i = 0; i < n; ++i)
            {
                g[i]     = grad(rng);
                m_ref[i] = (1.0f - p.gamma) * m_ref[i] + p.gamma * g[i];
                const int before = ref[i];
                const int after  = NaiveBop(before, m_ref[i], p);
                if (after != before)
                {
                    ++expect_changed;
                    ++seen[before == 1 ? 0 : (before == -1 ? 1 : (after == -1 ? 2 : 3))];
                }
                ref[i] = int8_t(after);
            }
            const size_t changed = BopStep(W, m.data(), g.data(), p);
            CHECK(changed == expect_changed);

            bool same = true;
            for (size_t i = 0; i < n; ++i)
            {
                same = same && (W.Get(i / cols, i % cols) == ref[i]);
                same = same && (std::fabs(m[i] - m_ref[i]) <= 1e-6f);
            }
            CHECK(same);
            CHECK(W.IsCanonical());
        }
    }
    CHECK(seen[0] > 0 && seen[1] > 0 && seen[2] > 0 && seen[3] > 0);   /* all four moves exercised */

    /* Outer-product version must match the dense version fed g = delta * x. */
    for (size_t s = 0; s < NUM_SIZES; ++s)
    {
        const size_t rows = 4;
        const size_t cols = SIZES[s];
        const size_t n    = rows * cols;

        TritMatrix A(rows, cols), B(rows, cols);
        const Ref  init = RandomTrits(n, rng);
        for (size_t i = 0; i < n; ++i)
        {
            A.Set(i / cols, i % cols, init[i]);
            B.Set(i / cols, i % cols, init[i]);
        }
        std::vector<float> ma(n, 0.0f), mb(n, 0.0f), g(n), delta(rows);

        for (int step = 0; step < 30; ++step)
        {
            const Ref  rx = RandomTrits(cols, rng);
            TritBuffer x(cols);
            Load(x, rx);
            for (size_t r = 0; r < rows; ++r)
            {
                delta[r] = grad(rng);
                for (size_t c = 0; c < cols; ++c)
                {
                    g[r * cols + c] = delta[r] * float(rx[c]);
                }
            }
            const size_t ca = BopStep(A, ma.data(), g.data(), p);
            const size_t cb = BopStepOuter(B, mb.data(), delta.data(), x, p);
            CHECK(ca == cb);

            bool same = true;
            for (size_t r = 0; r < rows; ++r)
            {
                same = same && Equal(A.Row(r), B.Row(r));
            }
            for (size_t i = 0; i < n; ++i)
            {
                same = same && (std::fabs(ma[i] - mb[i]) <= 1e-6f);
            }
            CHECK(same);
            CHECK(B.IsCanonical());
        }
    }

    /* Hand-checked cases with gamma = 1, so m is exactly the gradient. */
    {
        BopParams q;
        q.gamma     = 1.0f;
        q.tau_prune = 0.1f;
        q.tau_grow  = 0.5f;

        /*                 w:   +1     +1     -1     -1      0      0      0     +1     -1   */
        const int   w0[]   = {   1,     1,    -1,    -1,     0,     0,     0,     1,    -1 };
        const float g0[]   = { 0.2f, 0.05f, -0.2f,  0.9f,  0.3f,  0.6f, -0.6f, -0.9f, -0.05f };
        const int   want[] = {   0,     1,     0,    -1,     0,    -1,     1,     1,    -1 };
        /* notes:            pruned  weak   pruned  wrong  in the  grown  grown  wrong  weak
                                                    way    band                  way          */
        const size_t n = sizeof(w0) / sizeof(w0[0]);

        TritBuffer         w(n);
        std::vector<float> m(n, 0.0f);
        for (size_t i = 0; i < n; ++i)
        {
            w.Set(i, w0[i]);
        }
        const size_t changed = BopStep(w, m.data(), g0, q);
        CHECK(changed == 4);
        for (size_t i = 0; i < n; ++i)
        {
            CHECK(w.Get(i) == want[i]);
        }
    }

    /* The reason for two thresholds: a steady push that is strong enough to
       prune but not to grow parks the weight at 0 instead of flipping it. */
    {
        BopParams q;
        q.gamma     = 1.0f;
        q.tau_prune = 0.1f;
        q.tau_grow  = 0.5f;

        TritBuffer w(1);
        float      m = 0.0f;
        const float g = 0.3f;
        w.Set(0, 1);
        for (int step = 0; step < 10; ++step)
        {
            BopStep(w, &m, &g, q);
        }
        CHECK(w.Get(0) == 0);

        /* With equal thresholds the same push carries it straight through. */
        q.tau_grow = q.tau_prune;
        w.Set(0, 1);
        m = 0.0f;
        BopStep(w, &m, &g, q);
        CHECK(w.Get(0) == 0);
        BopStep(w, &m, &g, q);
        CHECK(w.Get(0) == -1);
    }
}

/*****************************************************************************/
static void TestPacking(std::mt19937& rng)
{
    CHECK(PackedBytes(size_t(0)) == 0);
    CHECK(PackedBytes(size_t(1)) == 1);
    CHECK(PackedBytes(size_t(5)) == 1);
    CHECK(PackedBytes(size_t(6)) == 2);
    CHECK(PackedBytes(size_t(784)) == 157);

    for (size_t s = 0; s < NUM_SIZES; ++s)
    {
        const size_t n   = SIZES[s];
        const Ref    ref = RandomTrits(n, rng);
        TritBuffer   a(n), b(n);
        Load(a, ref);
        Load(b, RandomTrits(n, rng));               /* stale contents must be overwritten */

        std::vector<uint8_t> bytes(PackedBytes(n) + 1, 0xAA);   /* +1: canary */
        Pack(a, bytes.data());
        CHECK(bytes[PackedBytes(n)] == 0xAA);

        bool in_range = true;
        for (size_t i = 0; i < PackedBytes(n); ++i)
        {
            in_range = in_range && (bytes[i] <= 242);
        }
        CHECK(in_range);

        CHECK(Unpack(bytes.data(), b));
        CHECK(Equal(a, b));
        CHECK(IsCanonical(b));

        /* Same values always give the same bytes. */
        std::vector<uint8_t> again(PackedBytes(n) + 1, 0xAA);
        Pack(b, again.data());
        CHECK(bytes == again);
    }

    /* Known encodings: digit = trit + 1, first trit least significant. */
    {
        TritBuffer t(5);
        uint8_t    byte = 0xFF;
        Pack(t, &byte);
        CHECK(byte == 121);                         /* 1 + 3 + 9 + 27 + 81 */
        Fill(t, 1);
        Pack(t, &byte);
        CHECK(byte == 242);
        Fill(t, -1);
        Pack(t, &byte);
        CHECK(byte == 0);
        t.Set(0, 1);                                /* +1, -1, -1, -1, -1 */
        Pack(t, &byte);
        CHECK(byte == 2);
    }

    /* Corrupt input is rejected. */
    {
        TritBuffer    t(5);
        const uint8_t bad = 243;
        CHECK(!Unpack(&bad, t));
    }

    /* Matrix round trip. */
    {
        const size_t rows = 10, cols = 784;
        TritMatrix   A(rows, cols), B(rows, cols);
        for (size_t r = 0; r < rows; ++r)
        {
            Load(A.Row(r), RandomTrits(cols, rng));
        }
        CHECK(PackedBytes(A) == rows * 157);
        std::vector<uint8_t> bytes(PackedBytes(A));
        Pack(A, bytes.data());
        CHECK(Unpack(bytes.data(), B));
        bool same = true;
        for (size_t r = 0; r < rows; ++r)
        {
            same = same && Equal(A.Row(r), B.Row(r));
        }
        CHECK(same);
        CHECK(B.IsCanonical());
    }
}

/*****************************************************************************/
int main()
{
    std::mt19937 rng(12345);

    TestHelpers(rng);
    TestBuffer(rng);
    TestQueries(rng);
    TestStepWords(rng);
    TestMatrix(rng);
    TestBop(rng);
    TestPacking(rng);

    std::printf("word bits: %d, checks: %d, failures: %d\n",
                int(WORD_BITS), g_checks, g_failures);
    return g_failures == 0 ? 0 : 1;
}