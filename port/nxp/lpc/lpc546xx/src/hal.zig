const std = @import("std");
const micro: type = @import("microzig");
const chip: type = micro.chip;
const cpu: type = micro.cpu;

const pll = @import("hal/pll.zig");
const power = @import("hal/libpower.zig");

pub const pad = @import("hal/pad.zig");
pub const gpio = @import("hal/gpio.zig");
pub const power_reset = @import("hal/power_reset.zig");
pub const uart = @import("hal/uart.zig");

// should be in a separate config file i guess.
pub const systick_hz = 1000;
// determine the max clock speed for this device
pub const cclk_hz = blk: {
    if (std.mem.eql(u8, micro.config.chip_name, "LPC54628")) {
        break :blk 220_000_000;
    } else if (std.mem.eql(u8, micro.config.chip_name, "LPC54616")) {
        break :blk 180_000_000;
    } else {
        break :blk 100_000_000;
    }
};

pub fn init() void {
    // For debugging purposes, go to halt if P1_22 is pulled high on reset (D7 on devboard)

    const p1_reset: u32 =
        chip.peripherals.SYSCON.PIORESCAP[1].raw;

    if ((p1_reset >> 22) & 1 == 1) {
        @panic("manual boot override");
    }
    // Start up  the  main pll and  set it  as the clock source
    pll.init_syspll(cclk_hz);
    chip.peripherals.SYSCON.MAINCLKSELB.modify(.{ .SEL = .SYSTEM_PLL_OUTPUT });

    // enable the systic at the configured tick rate
    //init_systick();
    init_fro_hf();
    //enable_fpu();
}

/// Enable the SysTick timer, to tike at systick_hz, adjust for the cclk_hz set in config
// fn init_systick() void {
//     // Load the value to count down from in the appropriate register
//     cpu.peripherals.SysTick.RVR.modify(
//         .{ .RELOAD = comptime @divFloor(cclk_hz, systick_hz) - 1 },
//     );

//     // Enable the systick with interrupt, with the main (AHB) clock source
//     cpu.peripherals.SysTick.CSR.raw = 7;
// }

// Enable the high frequency FRO. This is used as a clock for an number of peripherals
// (it is nice to divide)
fn init_fro_hf() void {
    power.set_fro_frequency(48_000_000);
    chip.peripherals.SYSCON.FROCTRL.modify(.{
        .SEL = 0,
        .WRTRIM = 1,
        .HSPDCLK = 1,
    });
}

pub fn enable_fpu() void {
    cpu.peripherals.SCB.CPACR.modify(.{
        .CP10 = .{ .raw = 3 },
        .CP11 = .{ .raw = 3 },
    });
    cpu.peripherals.SCB.FPCCR.raw = 0xc0000000;
}

// This function NEEDS to be inlined, as there is no stack for function returns yet...
pub inline fn extra_startup_logic() void {
    // Need to enable the RAM bank that the stack lives in...
    asm volatile (
        \\movs r0, #56;
        \\ldr r1, =0x40000220
        \\str r0, [r1]
        : // outputs
        : // inputs
        : "r0", "r1");
}
