/// Power Library API to power the PLLs.
pub extern fn POWER_SetPLL() void;

/// Power Library API to power the USB PHY.
pub extern fn POWER_SetUsbPhy() void;

/// Power Library API to enter different power mode.
pub extern fn POWER_EnterPowerMode(mode: u32, exclude_from_pd: u64) void;

/// Power Library API to enter sleep mode.
pub extern fn POWER_EnterSleep() void;

/// Power Library API to enter deep sleep mode.
pub extern fn POWER_EnterDeepSleep(exclude_from_pd: u64) void;

/// Power Library API to enter deep power down mode.
pub extern fn POWER_EnterDeepPowerDown(exclude_from_pd: u64) void;

/// Power Library API to choose normal regulation and set the voltage for
/// * the desired operating frequency.
pub extern fn POWER_SetVoltageForFreq(freq: u64) void;

/// Power Library API to return the library version.
pub extern fn POWER_GetLibVersion() u32;

// the magic number for the rom routine
const FROHF_ROM_API_ADDR = 0x030091DF;
/// Enable the FRO at either 48Mhz or 96Mhz. this is a ROM routine
pub fn set_fro_frequency(arg_iFreq: u32) callconv(.C) void {
    var iFreq = arg_iFreq;
    _ = &iFreq;
    @as(?*const fn (u32) callconv(.C) void, @ptrFromInt(FROHF_ROM_API_ADDR)).?(iFreq);
}
