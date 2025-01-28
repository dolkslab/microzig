const std = @import("std");
const micro: type = @import("microzig");
const chip: type = micro.chip;
const cpu: type = micro.cpu;
const power = @import("libpower.zig");

/// Setup the PLL of the CPU for high speed operation
pub fn init_syspll(freq_out: comptime_int) void {
    // this could be configurable in the future
    const freq_in = 12_000_000;

    comptime {
        if (freq_out < 4_300_000 or freq_out > 220_000_000)
            @compileError("Core clock must be between 4.3Mhz and 220Mhz!");
    }
    const syscon = chip.peripherals.SYSCON;

    // Make sure we are on the 12MHZ internal oscilator
    syscon.MAINCLKSELA.modify(.{ .SEL = .FRO_12_MHZ });
    syscon.MAINCLKSELB.modify(.{ .SEL = .MAINCLKSELA });

    // And that the clock divider is set to 12
    syscon.AHBCLKDIV.modify(.{ .DIV = 0 });

    const pll_settings = comptime calc_pll_settings(freq_in, freq_out);
    //@compileLog(pll_settings);

    // Use the ROM power API to set the voltage for frequency
    power.POWER_SetVoltageForFreq(@as(u64, freq_out));

    // Get the proper timing for the flash accelerator and set it.
    const flashtim = comptime get_flashtim(freq_out);
    // doing this the old fashioned way since the SVD is wrong
    syscon.FLASHCFG.raw |= @as(u32, flashtim) << 12;

    // Power on the PLL so we can modify its registers
    syscon.PDRUNCFGCLR0.modify(.{
        .PDEN_SYS_PLL = 1,
        .PDEN_VD3 = 1,
    });

    // Select the internal 12Mhz oscilator as the clock source.
    syscon.SYSPLLCLKSEL.modify(.{ .SEL = .FRO_12_MHZ });

    // Set the PLL band settings (idk what this actually does lol).
    syscon.SYSPLLCTRL.modify(.{
        .SELR = pll_settings.SELR,
        .SELI = pll_settings.SELI,
        .SELP = pll_settings.SELP,
        .BYPASS = .DISABLED,
    });

    // Finally we set the encoded values for N, M and P.
    syscon.SYSPLLNDEC.modify(.{
        .NDEC = pll_settings.NDEC,
        .NREQ = 1,
    });

    syscon.SYSPLLMDEC.modify(.{
        .MDEC = pll_settings.MDEC,
        .MREQ = 1,
    });

    syscon.SYSPLLPDEC.modify(.{
        .PDEC = pll_settings.PDEC,
        .PREQ = 1,
    });

    // Wait until the output of the internal oscilator is stable before switching to it.
    while (syscon.SYSPLLSTAT.read().LOCK == 0) {
        cpu.nop();
    }
}

/// Calculate the register values that need to be loaded into the syspll
/// registers to achieve a certain frequency. Calculates the optimal N, M and P divider values,
/// determines band select settings and encodes the N, M and P divider values.
/// Meant to be executed during compile time.
fn calc_pll_settings(f_in: comptime_int, f_out: comptime_int) PllSettings {
    // Encoding the values requires some loops that take more than 1000 jumps
    // during compilation, so we have to increase the default quota.
    @setEvalBranchQuota(0x10000);

    // Calculate raw pll divider values.
    const pll_raw = get_pll_raw(f_in, f_out);
    // determine the pll band settings. These depend on M
    const band_settings = calc_band_settings(pll_raw.M);
    return .{
        .SELR = band_settings.SELR,
        .SELI = band_settings.SELI,
        .SELP = band_settings.SELP,
        // Encode N, M and P.
        .NDEC = calc_ndec(pll_raw.N),
        .MDEC = calc_mdec(pll_raw.M),
        .PDEC = calc_pdec(pll_raw.P),
    };
}

const Fcco_min = 275_000_000;
const Fcco_max = 550_000_000;

fn get_flashtim(f_out: comptime_int) u4 {
    const f_out_mhz =
        std.math.divCeil(comptime_int, f_out, 1_000_000) catch unreachable;
    return switch (f_out_mhz) {
        0...12 => 0,
        13...24 => 1,
        25...36 => 2,
        37...60 => 3,
        61...96 => 4,
        97...120 => 5,
        121...144 => 6,
        145...168 => 7,
        169...180 => 8,
        181...220 => 7,
        else => 7,
    };
}

const PllRaw = struct {
    N: comptime_int = 1,
    M: comptime_int = 1,
    P: comptime_int = 1,
};

/// Calculate the raw(unencoded) multiplier and divider values to make
/// the PLL output a given output frequency based off of an input frequency
fn get_pll_raw(f_in: comptime_int, f_out: comptime_int) PllRaw {
    // clock ratio as a float
    const clock_ratio = (@as(comptime_float, @floatFromInt(f_out)) /
        @as(comptime_float, @floatFromInt(f_in)));

    // Maximum value for N is 256 as per the device manual
    const N_max: comptime_int = 256;

    // The current controlled oscilator (cco) must remain between 275 and 550 Mhz
    // By bounding the post divider P we can ensure that we always stay within this range.
    // This also has the benefit of narrowing our search space, so thats nice.
    // Minimum value for P such that Fcco >= 275Mhz
    const P_min: comptime_int = std.math.divCeil(comptime_int, Fcco_min, 2 * f_out) catch unreachable;
    // Maximum value for P such that Fcco <= 550Mhz
    const P_max: comptime_int = Fcco_max / (2 * f_out);

    var chosen_pll_raw: PllRaw = .{};
    // Just set the error to something big
    var chosen_freq_error: comptime_float = 100000000;

    var N = 1;
    // labeled loop so we can break out of it from the inner loop if required
    N_loop: while (N <= N_max) {
        var P = P_min;
        while (P <= P_max) {
            // Get the rounded value of M to produce an output frequency as close to F_out as possible
            const M: comptime_float = @round(clock_ratio *
                @as(comptime_float, @floatFromInt(N * P)));
            // compute the error
            const freq_error = @abs(f_out - f_in * (M / @as(comptime_float, @floatFromInt(N * P))));

            // If the error is smaller than the previous best we use these values as our best from now on
            if (freq_error < chosen_freq_error) {
                chosen_freq_error = freq_error;
                chosen_pll_raw = .{
                    .N = N,
                    .M = @as(comptime_int, @intFromFloat(M)),
                    .P = P,
                };
            }
            // If the error is less than 1 Hz then we're probably right on the money, so we can break out of the loop.
            if (chosen_freq_error < 1) {
                // Notice how zigs labeled blocks allow us to elegantly jump out of the outer loop here
                // No extra bool required :)
                break :N_loop;
            }
            P += 1;
        }
        N += 1;
    }

    return chosen_pll_raw;
}

/// Calculate the PLL band settings based on M. This is directly translated
/// from the psuedocode in the manual.
fn calc_band_settings(M: comptime_int) struct {
    SELR: u4,
    SELI: u6,
    SELP: u5,
} {
    var SELR: u4 = 0;
    var SELI: u6 = 0;
    var SELP: u5 = 0;

    if (M < 60) {
        SELP = (M >> 1) + 1;
    } else {
        SELP = 31;
    }

    if (M > 16384) {
        SELI = 1;
    } else if (M > 8192) {
        SELI = 2;
    } else if (M > 2048) {
        SELI = 4;
    } else if (M >= 501) {
        SELI = 8;
    } else if (M >= 60) {
        SELI = 4 * (1024 / (M + 9));
    } else {
        SELI = (M & 0x3C) + 4;
    }
    SELR = 0;
    return .{
        .SELR = SELR,
        .SELI = SELI,
        .SELP = SELP,
    };
}

/// encode the M value. This is directly translated from the psuedocode in the
/// device manual
fn calc_mdec(M: comptime_int) u17 {
    return switch (M) {
        0 => 0x1FFFF,
        1 => 0x18003,
        2 => 0x10003,
        else => blk: {
            const M_max = 0x8000;
            var x = 0x4000;
            for (M..M_max + 1) |_| {
                x = (((x ^ (x >> 1)) & 1) << 14) | ((x >> 1) & 0x3FFF);
            }
            break :blk x;
        },
    };
}

/// encode the N value. This is directly translated from the psuedocode in the
/// device manual
fn calc_ndec(N: comptime_int) u10 {
    return switch (N) {
        0 => 0x3FF,
        1 => 0x302,
        2 => 0x202,
        else => blk: {
            const N_max = 0x100;
            var x = 0x80;
            for (N..N_max + 1) |_| {
                x = (((x ^ (x >> 2) ^ (x >> 3) ^ (x >> 4)) &
                    1) << 7) | ((x >> 1) & 0x7F);
            }
            break :blk x;
        },
    };
}

/// encode the P value. This is directly translated from the psuedocode in the
/// device manual
fn calc_pdec(P: comptime_int) u7 {
    return switch (P) {
        0 => 0x7F,
        1 => 0x62,
        2 => 0x42,
        else => blk: {
            const P_max = 0x20;
            var x = 0x10;
            for (P..P_max + 1) |_| {
                x = (((x ^ (x >> 2)) & 1) << 4) | ((x >> 1) & 0xF);
            }
            break :blk x;
        },
    };
}

const PllSettings = struct {
    SELR: u4,
    SELI: u6,
    SELP: u5,
    NDEC: u10,
    MDEC: u17,
    PDEC: u7,
};
