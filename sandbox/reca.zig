// reca.zig - Reservoir Computing with Elementary Cellular Automata
// Uses Rule 90/150/102 as reservoir - all integer/bit ops, no FPU needed

const std = @import("std");

pub const ReCA = struct {
    allocator: std.mem.Allocator,
    ca_size: usize, // Width of CA grid
    time_steps: usize, // Temporal depth (how many CA steps per input)
    rule: u8, // Elementary CA rule (0-255)

    state: []u8, // Current CA state
    history: []u8, // Flattened space-time history

    // Input projection mask
    input_mask: []usize, // Which cells get input injection

    pub fn init(
        allocator: std.mem.Allocator,
        size: usize,
        steps: usize,
        r: u8,
    ) !ReCA {
        var reca = ReCA{
            .allocator = allocator,
            .ca_size = size,
            .time_steps = steps,
            .rule = r,
            .state = try allocator.alloc(u8, size),
            .history = try allocator.alloc(u8, size * steps),
            .input_mask = try allocator.alloc(usize, size / 4), // 25% input cells
        };

        @memset(reca.state, 0);
        @memset(reca.history, 0);

        // Random input projection
        var prng = std.rand.DefaultPrng.init(42);
        for (reca.input_mask) |*m| {
            m.* = prng.random().int(usize) % size;
        }

        return reca;
    }

    pub fn deinit(self: *ReCA) void {
        self.allocator.free(self.state);
        self.allocator.free(self.history);
        self.allocator.free(self.input_mask);
    }

    // Apply elementary CA rule to single cell
    fn applyRule(rule: u8, left: u8, center: u8, right: u8) u8 {
        const pattern = (left << 2) | (center << 1) | right;
        return (rule >> @intCast(pattern)) & 1;
    }

    // Step CA forward one tick with input injection
    pub fn step(self: *ReCA, input: f32) void {
        var new_state = try self.allocator.alloc(u8, self.ca_size);
        defer self.allocator.free(new_state);

        // Convert input to binary perturbation
        const input_bit: u8 = if (input > 0) 1 else 0;

        // Inject input at masked positions
        for (self.input_mask) |idx| {
            self.state[idx] ^= input_bit; // XOR injection
        }

        // Apply CA rule with periodic boundary
        for (0..self.ca_size) |i| {
            const left = if (i == 0) self.state[self.ca_size - 1] else self.state[i - 1];
            const center = self.state[i];
            const right = if (i == self.ca_size - 1) self.state[0] else self.state[i + 1];
            new_state[i] = applyRule(self.rule, left, center, right);
        }

        @memcpy(self.state, new_state);
    }

    // Run full reservoir cycle: input -> CA evolution -> feature vector
    pub fn activate(self: *ReCA, input: f32, features: []f32) void {
        // Reset for new input
        @memset(self.state, 0);

        // Initial injection
        for (self.input_mask) |idx| {
            self.state[idx] = if (input > 0) 1 else 0;
        }

        // Evolve CA for time_steps
        for (0..self.time_steps) |t| {
            // Store state in history
            for (0..self.ca_size) |i| {
                self.history[t * self.ca_size + i] = self.state[i];
            }

            // Step forward (no additional input after initial)
            var new_state = try self.allocator.alloc(u8, self.ca_size);
            defer self.allocator.free(new_state);

            for (0..self.ca_size) |i| {
                const left = if (i == 0) self.state[self.ca_size - 1] else self.state[i - 1];
                const right = if (i == self.ca_size - 1) self.state[0] else self.state[i + 1];
                new_state[i] = applyRule(self.rule, left, self.state[i], right);
            }
            @memcpy(self.state, new_state);
        }

        // Flatten space-time into feature vector
        // Use density of 1s in space-time windows as features
        const window_size = (self.ca_size * self.time_steps) / features.len;
        for (0..features.len) |f| {
            const start = f * window_size;
            var count: usize = 0;
            for (start..start + window_size) |i| {
                count += self.history[i];
            }
            features[f] = @as(f32, @floatFromInt(count)) / @as(f32, @floatFromInt(window_size));
        }
    }
};

// 5-bit memory task: remember which of 5 input channels was active
pub fn memoryTask() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    // Rule 90 (XOR) and Rule 150 (XOR of 3 neighbors) are good for computation
    var reservoir = try ReCA.init(allocator, 64, 16, 150);
    defer reservoir.deinit();

    // Training: 1000 random sequences
    const train_size = 1000;
    const feature_dim = 32; // Compressed CA space-time

    // Simple linear readout would go here
    // For now, demonstrate the reservoir activation

    var features = try allocator.alloc(f32, feature_dim);
    defer allocator.free(features);

    // Test input
    reservoir.activate(0.7, features);

    std.debug.print("Feature vector (first 10): ", .{});
    for (0..10) |i| {
        std.debug.print("{d:.2} ", .{features[i]});
    }
    std.debug.print("\n", .{});
}
