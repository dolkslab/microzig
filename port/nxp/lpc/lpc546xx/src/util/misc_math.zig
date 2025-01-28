const std = @import("std");


pub fn divClosest(comptime T: type, numerator: T, denominator: T) !T {
    const biggerT = std.meta.Int(.unsigned, @bitSizeOf(T) + 1);
    const a = denominator >> 1;
    const big_numerator: biggerT = @as(biggerT, numerator) + @as(biggerT, a);

    const result: biggerT = try std.math.divTrunc(
        biggerT,
        big_numerator,
        @as(biggerT, denominator),
    );

    return @truncate(result);
}

pub const ufp24_8: type = u32;

pub fn clock_divider(in_clock: u32, out_clock: u32) types.ufp24_8 {
    const res_64: u64 = (@as(u64, in_clock) * 0x100) / out_clock;
    return @truncate(res_64);
}