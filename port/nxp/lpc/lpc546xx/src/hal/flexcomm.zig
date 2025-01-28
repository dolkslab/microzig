const micro: type = @import("microzig");
// pub const chip = struct {
//     const inner = @import("../chips/LPC54628.zig");
//     pub const types = inner.types;
//     pub usingnamespace @field(inner.devices, "LPC54628");
// };
const chip = micro.chip;
const power_reset = @import("power_reset.zig");

const flexcomm_mmio_type = chip.types.peripherals.FLEXCOMM0;

pub const Function = enum(u3) {
    NONE = 0,
    USART = 1,
    SPI = 2,
    I2C = 3,
    I2S_TX = 4,
    I2S_RX = 5,
};

pub const ClockSource = enum(u3) {
    ///  FRO 12 MHz (fro_12m)
    FRO_12_MHZ = 0x0,
    ///  FRO HF DIV (fro_hf_div)
    FRO_HF_DIV = 0x1,
    ///  Audio PLL clock (audio_pll_clk)
    AUDIO_PLL_OUTPUT = 0x2,
    ///  MCLK pin input, when selected in IOCON (mclk_in)
    MCLK_INPUT = 0x3,
    ///  FRG clock, the output of the fractional rate generator (frg_clk)
    FRG_CLOCK_OUTPUT = 0x4,
    ///  None, this may be selected in order to reduce power when no output is needed.
    NONE = 0x7,
};

pub const Flexcomm = enum(u4) {
    FC0,
    FC1,
    FC2,
    FC3,
    FC4,
    FC5,
    FC6,
    FC7,
    FC8,
    FC9,

    pub fn mmio_ptr(flx: Flexcomm) *volatile chip.types.peripherals.FLEXCOMM0 {
        return switch (flx) {
            // this was the best way i could think of doing this without doing
            // more jank pointer math.
            .FC0 => chip.peripherals.FLEXCOMM0,
            .FC1 => chip.peripherals.FLEXCOMM1,
            .FC2 => chip.peripherals.FLEXCOMM2,
            .FC3 => chip.peripherals.FLEXCOMM3,
            .FC4 => chip.peripherals.FLEXCOMM4,
            .FC5 => chip.peripherals.FLEXCOMM5,
            .FC6 => chip.peripherals.FLEXCOMM6,
            .FC7 => chip.peripherals.FLEXCOMM7,
            .FC8 => chip.peripherals.FLEXCOMM8,
            .FC9 => chip.peripherals.FLEXCOMM9,
        };
    }

    pub fn irqn(flx: Flexcomm) micro.interrupt.Irqn {
        return @enumFromInt(@as(i8, @intFromEnum(flx)) +
            @intFromEnum(micro.interrupt.Irqn.FLEXCOMM0));
    }

    pub fn set_function(flx: Flexcomm, func: Function) void {
        var flexcomm_mmio = mmio_ptr(flx);

        //const enum_converted: flexcomm_mmio_type.PSELID.underlying_type.PERSEL = @enumFromInt(@intFromEnum(func));

        flexcomm_mmio.PSELID.write_raw_masked(0b111, @intFromEnum(func));
    }

    // pub fn set_function_from_mmio(peripheral_mmio: anytype) void {
    //     const peripheral_as_flexcomm: *volatile chip.types.peripherals.FLEXCOMM0 = @ptrCast(peripheral_mmio);
    //     const function: u3 = switch (@TypeOf(peripheral_mmio)) {
    //         chip.types.peripherals.USART0 => 1,
    //         chip.types.peripherals.SPI0 => 2,
    //         chip.types.peripherals.I2C0 => 3,
    //         chip.types.peripherals.I2S0 => 4,
    //         else => 0,
    //     };

    //     // TODO check if the peripheral actually supports the selected mode,
    //     // TODO return an error on uhh error

    //     peripheral_as_flexcomm.PSELID.modify(.{ .PERSEL = .{ .raw = function } });
    // }

    pub fn set_clock_source(flx: Flexcomm, clk_src: ClockSource) void {
        // chip.peripherals.SYSCON.FCLKSEL[@intFromEnum(flx)].modify(.{
        //     .SEL = .{ .raw = @intFromEnum(clk_src) },
        // });

        chip.peripherals.SYSCON.FCLKSEL[@intFromEnum(flx)]
            .write_raw_masked(0b111, @intFromEnum(clk_src));
    }

    pub fn enable_ahb_clock(flx: Flexcomm) void {
        var ahbclock: power_reset.AHBClock = undefined;
        if (@intFromEnum(flx) < 8) {
            ahbclock = @enumFromInt(@intFromEnum(power_reset.AHBClock.FLEXCOMM0) +
                @intFromEnum(flx));
        } else {
            ahbclock = @enumFromInt(@intFromEnum(power_reset.AHBClock.FLEXCOMM8) +
                @intFromEnum(flx));
        }
        ahbclock.enable();
    }
};
