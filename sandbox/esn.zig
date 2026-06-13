// esn.zig - Echo State Network for time-series prediction
// Compile: zig build-exe esn.zig -O ReleaseFast

const std = @import("std");
const math = std.math;
const rand = std.crypto.random;

pub const ESN = struct {
    allocator: std.mem.Allocator,

    // Dimensions
    input_size: usize,
    reservoir_size: usize,
    output_size: usize,

    // Reservoir state (current activation)
    state: []f32,

    // Weight matrices (fixed after init)
    Win: []f32, // input_size x reservoir_size (stored as [reservoir][input])
    W: []f32, // reservoir_size x reservoir_size

    // Trainable readout weights
    Wout: []f32, // output_size x reservoir_size

    // Hyperparameters
    spectral_radius: f32, // < 1.0 for echo state property
    input_scaling: f32,
    leaking_rate: f32, // 0 < alpha <= 1

    pub fn init(
        allocator: std.mem.Allocator,
        in_size: usize,
        res_size: usize,
        out_size: usize,
        radius: f32,
        in_scale: f32,
        leak: f32,
    ) !ESN {
        var esn = ESN{
            .allocator = allocator,
            .input_size = in_size,
            .reservoir_size = res_size,
            .output_size = out_size,
            .state = try allocator.alloc(f32, res_size),
            .Win = try allocator.alloc(f32, res_size * in_size),
            .W = try allocator.alloc(f32, res_size * res_size),
            .Wout = try allocator.alloc(f32, out_size * res_size),
            .spectral_radius = radius,
            .input_scaling = in_scale,
            .leaking_rate = leak,
        };

        // Initialize state to zero
        @memset(esn.state, 0);

        // Random init for Win and W
        initRandomMatrix(esn.Win, res_size * in_size);
        initRandomMatrix(esn.W, res_size * res_size);

        // Scale input weights
        for (esn.Win) |*w| w.* = (rand.float(f32) * 2 - 1) * in_scale;

        // Scale reservoir weights to desired spectral radius
        scaleSpectralRadius(esn.W, res_size, radius);

        return esn;
    }

    pub fn deinit(self: *ESN) void {
        self.allocator.free(self.state);
        self.allocator.free(self.Win);
        self.allocator.free(self.W);
        self.allocator.free(self.Wout);
    }

    // tanh activation with numerical stability
    fn tanh(x: f32) f32 {
        return math.tanh(x);
    }

    // Update reservoir state: x(t+1) = (1-a)*x(t) + a*tanh(W*x(t) + Win*u(t))
    pub fn update(self: *ESN, input: []const f32) void {
        const r = self.reservoir_size;
        const i_size = self.input_size;

        // Compute W * state + Win * input
        for (0..r) |i| {
            var sum: f32 = 0;

            // Reservoir feedback
            for (0..r) |j| {
                sum += self.W[i * r + j] * self.state[j];
            }

            // Input injection
            for (0..i_size) |k| {
                sum += self.Win[i * i_size + k] * input[k];
            }

            // Leaky integrator update
            self.state[i] = (1 - self.leaking_rate) * self.state[i] + self.leaking_rate * tanh(sum);
        }
    }

    // Read output: y = Wout * state
    pub fn read(self: *const ESN, output: []f32) void {
        for (0..self.output_size) |i| {
            var sum: f32 = 0;
            for (0..self.reservoir_size) |j| {
                sum += self.Wout[i * self.reservoir_size + j] * self.state[j];
            }
            output[i] = sum;
        }
    }

    // Train using ridge regression on collected states
    pub fn train(
        self: *ESN,
        states: []const f32, // [timesteps x reservoir_size]
        targets: []const f32, // [timesteps x output_size]
        timesteps: usize,
        reg_lambda: f32, // Ridge regularization
    ) !void {
        const r = self.reservoir_size;
        const o = self.output_size;

        // X'X + lambda*I
        var XtX = try self.allocator.alloc(f32, r * r);
        defer self.allocator.free(XtX);

        // X'Y
        var XtY = try self.allocator.alloc(f32, r * o);
        defer self.allocator.free(XtY);

        // Compute XtX
        @memset(XtX, 0);
        for (0..r) |i| {
            for (0..r) |j| {
                var sum: f32 = 0;
                for (0..timesteps) |t| {
                    sum += states[t * r + i] * states[t * r + j];
                }
                XtX[i * r + j] = sum;
            }
        }

        // Add regularization to diagonal
        for (0..r) |i| {
            XtX[i * r + i] += reg_lambda;
        }

        // Compute XtY
        @memset(XtY, 0);
        for (0..r) |i| {
            for (0..o) |j| {
                var sum: f32 = 0;
                for (0..timesteps) |t| {
                    sum += states[t * r + i] * targets[t * o + j];
                }
                XtY[i * o + j] = sum;
            }
        }

        // Solve (X'X) * Wout' = X'Y using Gaussian elimination
        // For production, use a proper linear algebra library
        solveLinearSystem(XtX, XtY, self.Wout, r, o);
    }

    fn solveLinearSystem(A: []f32, B: []f32, X: []f32, n: usize, m: usize) void {
        // Simple Gaussian elimination with partial pivoting
        // In production, replace with LAPACK or similar
        var aug = A; // In-place for simplicity

        // Forward elimination
        for (0..n) |col| {
            // Partial pivot
            var max_row = col;
            var max_val = @abs(aug[col * n + col]);
            for (col + 1..n) |row| {
                const val = @abs(aug[row * n + col]);
                if (val > max_val) {
                    max_val = val;
                    max_row = row;
                }
            }

            // Swap rows
            if (max_row != col) {
                for (0..n) |k| {
                    const tmp = aug[col * n + k];
                    aug[col * n + k] = aug[max_row * n + k];
                    aug[max_row * n + k] = tmp;
                }
                for (0..m) |k| {
                    const tmp = B[col * m + k];
                    B[col * m + k] = B[max_row * m + k];
                    B[max_row * m + k] = tmp;
                }
            }

            // Eliminate column
            for (col + 1..n) |row| {
                const factor = aug[row * n + col] / aug[col * n + col];
                for (col..n) |k| {
                    aug[row * n + k] -= factor * aug[col * n + k];
                }
                for (0..m) |k| {
                    B[row * m + k] -= factor * B[col * m + k];
                }
            }
        }

        // Back substitution
        for (0..m) |j| {
            for (0..n) |i| {
                const row = n - 1 - i;
                var sum: f32 = B[row * m + j];
                for (row + 1..n) |k| {
                    sum -= aug[row * n + k] * X[k * m + j];
                }
                X[row * m + j] = sum / aug[row * n + row];
            }
        }
    }
};

fn initRandomMatrix(data: []f32, len: usize) void {
    for (0..len) |i| {
        data[i] = rand.float(f32) * 2 - 1;
    }
}

fn scaleSpectralRadius(W: []f32, size: usize, target_radius: f32) void {
    // Approximate scaling: divide by estimated max eigenvalue
    // For production, use power iteration
    var max_row_sum: f32 = 0;
    for (0..size) |i| {
        var sum: f32 = 0;
        for (0..size) |j| {
            sum += @abs(W[i * size + j]);
        }
        if (sum > max_row_sum) max_row_sum = sum;
    }

    if (max_row_sum > 0) {
        const scale = target_radius / max_row_sum;
        for (W) |*w| w.* *= scale;
    }
}

// Example: Mackey-Glass chaotic time series prediction
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // ESN config: 1 input, 100 reservoir neurons, 1 output
    var esn = try ESN.init(allocator, 1, 100, 1, 0.9, 0.5, 0.3);
    defer esn.deinit();

    // Generate synthetic training data (sine wave for demo)
    const train_len = 1000;
    const washout = 100;

    var states = try allocator.alloc(f32, (train_len - washout) * 100);
    defer allocator.free(states);
    var targets = try allocator.alloc(f32, (train_len - washout) * 1);
    defer allocator.free(targets);

    // Run washout to forget initial state
    var input = [1]f32{0};
    for (0..washout) |_| {
        input[0] = rand.float(f32); // Random washout input
        esn.update(&input);
    }

    // Collect states
    var state_idx: usize = 0;
    for (0..train_len - washout) |t| {
        input[0] = @sin(@as(f32, @floatFromInt(t)) * 0.1);
        esn.update(&input);

        // Store state
        for (0..100) |i| {
            states[state_idx * 100 + i] = esn.state[i];
        }
        // Target is next value
        targets[state_idx] = @sin(@as(f32, @floatFromInt(t + 1)) * 0.1);
        state_idx += 1;
    }

    // Train
    try esn.train(states, targets, train_len - washout, 0.01);

    // Test
    var mse: f32 = 0;
    for (1000..1100) |t| {
        input[0] = @sin(@as(f32, @floatFromInt(t)) * 0.1);
        esn.update(&input);

        var output = [1]f32{0};
        esn.read(&output);

        const target = @sin(@as(f32, @floatFromInt(t + 1)) * 0.1);
        const err = output[0] - target;
        mse += err * err;
    }
    mse /= 100;

    std.debug.print("Test MSE: {d:.6}\n", .{mse});
}
