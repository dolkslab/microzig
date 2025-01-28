const std = @import("std");
const micro = @import("microzig");

const chip = micro.chip;
const syscon = chip.peripherals.SYSCON;

pub const AHBClock = enum(u8) {
    ROM = 1,
    SRAM1 = 3,
    SRAM2,
    SRAM3,
    FLASH = 7,
    FMC,
    EEPROM,
    SPIFI,
    INPUTMUX,
    IOCON = 13,
    GPIO0,
    GPIO1,
    GPIO2,
    GPIO3,
    PINT,
    GINT,
    DMA,
    CRC,
    WWDT,
    RTC,
    ADC0 = 27,

    MRT = 32,
    RIT,
    SCT0,
    MCAN0 = 32 + 7,
    MCAN1,
    UTICK = 32 + 10,
    FLEXCOMM0,
    FLEXCOMM1,
    FLEXCOMM2,
    FLEXCOMM3,
    FLEXCOMM4,
    FLEXCOMM5,
    FLEXCOMM6,
    FLEXCOMM7,
    DMIC,
    CTIMER2 = 32 + 22,
    USB0D = 32 + 25,
    CTIMER0,
    CTIMER1,

    LCD = 64 + 2,
    SDIO,
    USB1H,
    USB1D,
    USB1RAM,
    EMC,
    ETH,
    GPIO4,
    GPIO5,
    AES,
    OTP = 64 + 12,
    RNG,
    FLEXCOMM8,
    FLEXCOMM9,
    USB0HMR,
    USB0HSL,
    SHA0,
    SC0,
    SC1,

    // pub fn enable_on_boot(clock: AHBClock, store: u32) void {
    //     //const i = @intFromEnum(clock) / @as(u8, 32);
    //     const bit: u32 = 1 << (@intFromEnum(clock) % @as(u8, 32));
    //     store = bit;
    // }

    // pub fn enable_set_boot_clocks() void {
    //     for (0.., ahb_clocks_to_enable) |i, value| {
    //         chip.peripherals.SYSCON.AHBCLKCTRLSET[i].write_raw(value);
    //
    // }

    pub fn enable(clock: AHBClock) void {
        chip.peripherals.SYSCON.AHBCLKCTRLSET[@intFromEnum(clock) / 32]
            .write_raw(@as(u32, 1) << @as(u5, @truncate(@intFromEnum(clock))));
    }

    pub fn disable(clock: AHBClock) void {
        chip.peripherals.SYSCON.AHBCLKCTRLCLR[@intFromEnum(clock) / 32]
            .write_raw(@as(u32, 1) << @as(u5, @truncate(@intFromEnum(clock))));
    }
};
