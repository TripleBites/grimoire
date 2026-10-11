// mnist.hpp - single-header MNIST (IDX format) loader. C++11, no dependencies.
//
// Expects the four *uncompressed* files:
//   train-images-idx3-ubyte   train-labels-idx1-ubyte   (60,000 samples)
//   t10k-images-idx3-ubyte    t10k-labels-idx1-ubyte    (10,000 samples)
//
// IDX layout (all header integers are 32-bit BIG-endian):
//   images: [magic 0x00000803][count][rows][cols][count*rows*cols bytes]
//   labels: [magic 0x00000801][count][count bytes]
// Pixels are uint8, row-major, 0 = background, 255 = full ink.
// The magic's low bytes encode the type: 0x08 = unsigned byte, 0x03/0x01 = number
// of dimensions.
//
// Usage:
//   mnist::Dataset train;
//   std::string err;
//   if (!mnist::load("train-images-idx3-ubyte", "train-labels-idx1-ubyte", train, &err)) {
//       std::fprintf(stderr, "%s\n", err.c_str());
//       return 1;
//   }
//   const uint8_t* px = train.image(0);   // 784 bytes
//   uint8_t label     = train.labels[0];  // 0..9

#pragma once

#include <cstddef>
#include <cstdint>
#include <cstdio>
#include <string>
#include <vector>

namespace dataset {
namespace mnist {

// All images live in one contiguous buffer: image i starts at i * image_size().
struct Dataset {
    uint32_t count;
    uint32_t rows;
    uint32_t cols;
    std::vector<uint8_t> pixels; // count * rows * cols
    std::vector<uint8_t> labels; // count

    Dataset() : count(0), rows(0), cols(0) {}

    std::size_t image_size() const { return static_cast<std::size_t>(rows) * cols; }
    const uint8_t* image(std::size_t i) const { return pixels.data() + i * image_size(); }
};

namespace detail {

// Closes the FILE on every return path.
struct File {
    std::FILE* fp;
    explicit File(const std::string& path) : fp(std::fopen(path.c_str(), "rb")) {}
    ~File() { if (fp) std::fclose(fp); }
    File(const File&) = delete;
    File& operator=(const File&) = delete;
};

// Assembles the value byte by byte, so it is correct on any host endianness.
inline bool read_u32_be(std::FILE* fp, uint32_t& out) {
    unsigned char b[4];
    if (std::fread(b, 1, 4, fp) != 4) return false;
    out = (static_cast<uint32_t>(b[0]) << 24) | (static_cast<uint32_t>(b[1]) << 16) |
          (static_cast<uint32_t>(b[2]) << 8)  |  static_cast<uint32_t>(b[3]);
    return true;
}

inline bool fail(std::string* err, const std::string& msg) {
    if (err) *err = msg;
    return false;
}

inline bool check_magic(uint32_t magic, uint32_t expected, const std::string& path, std::string* err) {
    if (magic == expected) return true;
    if ((magic >> 16) == 0x1f8b) // gzip signature
        return fail(err, path + ": still gzip-compressed, gunzip it first");
    return fail(err, path + ": bad magic number (not an IDX file of the expected type)");
}

} // namespace detail

// Loads an image file and its matching label file.
// max_items = 0 loads everything; otherwise only the first max_items samples.
// On failure returns false, leaves `out` untouched and writes a message to *err.
inline bool load(const std::string& images_path, const std::string& labels_path,
                 Dataset& out, std::string* err = nullptr, uint32_t max_items = 0) {
    using detail::fail;

    detail::File img(images_path);
    if (!img.fp) return fail(err, "cannot open " + images_path);
    detail::File lbl(labels_path);
    if (!lbl.fp) return fail(err, "cannot open " + labels_path);

    uint32_t magic = 0, n_img = 0, rows = 0, cols = 0;
    if (!detail::read_u32_be(img.fp, magic) || !detail::read_u32_be(img.fp, n_img) ||
        !detail::read_u32_be(img.fp, rows)  || !detail::read_u32_be(img.fp, cols))
        return fail(err, images_path + ": truncated header");
    if (!detail::check_magic(magic, 0x00000803u, images_path, err)) return false;

    uint32_t n_lbl = 0;
    if (!detail::read_u32_be(lbl.fp, magic) || !detail::read_u32_be(lbl.fp, n_lbl))
        return fail(err, labels_path + ": truncated header");
    if (!detail::check_magic(magic, 0x00000801u, labels_path, err)) return false;

    if (n_img != n_lbl)
        return fail(err, "image count and label count differ (mismatched file pair?)");
    if (rows == 0 || cols == 0 || rows > 4096 || cols > 4096)
        return fail(err, images_path + ": implausible image dimensions");

    uint32_t count = n_img;
    if (max_items != 0 && max_items < count) count = max_items;

    // Guard the allocation size: matters on 32-bit targets and corrupt headers.
    const std::size_t image_size = static_cast<std::size_t>(rows) * cols;
    if (count > static_cast<std::size_t>(-1) / image_size)
        return fail(err, images_path + ": dataset too large for this platform");
    const std::size_t total = static_cast<std::size_t>(count) * image_size;

    Dataset tmp;
    tmp.count = count;
    tmp.rows = rows;
    tmp.cols = cols;
    tmp.pixels.resize(total);
    tmp.labels.resize(count);

    if (total != 0 && std::fread(tmp.pixels.data(), 1, total, img.fp) != total)
        return fail(err, images_path + ": truncated pixel data");
    if (count != 0 && std::fread(tmp.labels.data(), 1, count, lbl.fp) != count)
        return fail(err, labels_path + ": truncated label data");

    out.count = tmp.count;
    out.rows = tmp.rows;
    out.cols = tmp.cols;
    out.pixels.swap(tmp.pixels);
    out.labels.swap(tmp.labels);
    return true;
}

// ---- Conversions -----------------------------------------------------------

// uint8 [0,255] -> float [0,1].
inline void to_float(const uint8_t* src, std::size_t n, float* dst) {
    for (std::size_t i = 0; i < n; ++i) dst[i] = src[i] * (1.0f / 255.0f);
}

// uint8 -> {-1, 0, +1}:   p < lo -> -1,   lo <= p <= hi -> 0,   p > hi -> +1.
// With the defaults, background is -1, ink is +1 and anti-aliased edges are 0.
// Pass lo = 0 to get a sparse {0, +1} encoding instead (background becomes 0).
inline void to_ternary(const uint8_t* src, std::size_t n, int8_t* dst,
                       uint8_t lo = 64, uint8_t hi = 192) {
    for (std::size_t i = 0; i < n; ++i)
        dst[i] = static_cast<int8_t>((src[i] > hi) - (src[i] < lo));
}

// Ternarizes the whole dataset into one flat buffer (same indexing as Dataset::pixels).
inline std::vector<int8_t> to_ternary_all(const Dataset& ds, uint8_t lo = 64, uint8_t hi = 192) {
    std::vector<int8_t> out(ds.pixels.size());
    to_ternary(ds.pixels.data(), ds.pixels.size(), out.data(), lo, hi);
    return out;
}

// ---- Debug -----------------------------------------------------------------

// Prints image i as ASCII art with its label. Quick check that loading worked.
inline void print_ascii(const Dataset& ds, std::size_t i, std::FILE* fp = stdout) {
    if (i >= ds.count) return;
    static const char shades[] = " .:-=+*#%@"; // 10 levels
    const uint8_t* p = ds.image(i);
    std::fprintf(fp, "label: %u\n", static_cast<unsigned>(ds.labels[i]));
    for (uint32_t r = 0; r < ds.rows; ++r) {
        for (uint32_t c = 0; c < ds.cols; ++c)
            std::fputc(shades[p[r * ds.cols + c] * 10 / 256], fp);
        std::fputc('\n', fp);
    }
}

} // namespace mnist
} // namespace dataset