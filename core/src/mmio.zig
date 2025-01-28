const std = @import("std");
const assert = std.debug.assert;

pub fn Mmio(comptime PackedT: type) type {
    const size = @bitSizeOf(PackedT);
    if ((size % 8) != 0)
        @compileError("size must be divisible by 8!");

    if (!std.math.isPowerOfTwo(size / 8))
        @compileError("size must encode a power of two number of bytes!");

    const IntT = std.meta.Int(.unsigned, size);

    if (@sizeOf(PackedT) != (size / 8))
        @compileError(std.fmt.comptimePrint("IntT and PackedT must have the same size!, they are {} and {} bytes respectively", .{ size / 8, @sizeOf(PackedT) }));

    return extern struct {
        const Self = @This();

        raw: IntT,

        pub const underlying_type = PackedT;

        pub inline fn read(addr: *volatile Self) PackedT {
            return @bitCast(addr.raw);
        }

        pub inline fn write(addr: *volatile Self, val: PackedT) void {
            comptime {
                assert(@bitSizeOf(PackedT) == @bitSizeOf(IntT));
            }
            addr.write_raw(@bitCast(val));
        }

        pub fn write_raw(addr: *volatile Self, val: IntT) void {
            addr.raw = val;
        }

        pub inline fn modify(addr: *volatile Self, fields: anytype) void {
            var val = read(addr);
            inline for (@typeInfo(@TypeOf(fields)).Struct.fields) |field| {
                @field(val, field.name) = @field(fields, field.name);
            }
            write(addr, val);
        }

        pub inline fn toggle(addr: *volatile Self, fields: anytype) void {
            var val = read(addr);
            inline for (@typeInfo(@TypeOf(fields)).Struct.fields) |field| {
                @field(val, field.name) = @field(val, field.name) ^ @field(fields, field.name);
            }
            write(addr, val);
        }

        /// Write to the raw register (as unsigned integer), only affecting the bits where mask = 1
        pub fn write_raw_masked(addr: *volatile Self, mask: IntT, value: IntT) void {
            const reg = addr.raw;
            write_raw(addr, (reg & ~mask) | (value & mask));
        }

        /// Set a single bit at an offset.
        pub fn set_bit(addr: *volatile Self, offset: anytype, value: bool) void {
            addr.write_raw_masked(@as(IntT, 1) << offset, @as(IntT, @intFromBool(value)) << offset);
        }
    };
}
