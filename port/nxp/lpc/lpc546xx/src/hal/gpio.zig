const micro = @import("microzig");
//const chip = @import("../chips/LPC54628.zig").devices.LPC54628;
const chip = micro.chip;
const pad = @import("pad.zig");
const power_reset = @import("power_reset.zig");

const gpio_periph = chip.peripherals.GPIO;

pub const Gpio = struct {
    pad: pad.Pad,

    pub fn init(self: *const Gpio, dir: bool) void {
        self.init_with_config(dir, .{});
    }

    pub fn init_with_config(self: *const Gpio, dir: bool, config: pad.Config) void {
        power_reset.AHBClock.enable(port_to_ahbclock(self.pad.port));
        self.pad.init_with_config(config);
        self.set_dir(dir);
    }

    pub fn set_dir(self: *const Gpio, dir: bool) void {
        gpio_periph.DIR[self.pad.port]


        .set_bit(self.pad.num, dir);
    }

    pub fn write(self: *const Gpio, high: bool) void {
        const B = self.get_gpio_B_reg();
        B.* = @intFromBool(high);
    }

    pub fn toggle(self: *const Gpio) void {
        gpio_periph.NOT[self.pad.port].raw = @as(u32, 1) << self.pad.num;
    }

    pub fn read(self: *const Gpio) bool {
        const B = self.get_gpio_B_reg();
        return B.* != 0;
    }

    pub fn read_u1(self: *const Gpio) u1 {
        const B = self.get_gpio_B_reg();
        return @as(u1, B.*);
    }

    // idk why but regz doesn't like the 2D array for the GPIO Byte registers,
    // so it pretends they don't exist. So here is a another jank pointer hack
    // to get around it. I mean this is basically what arrays are anyway execpt
    // memora non safetyora.
    inline fn get_gpio_B_reg(self: *const Gpio) *volatile u8 {
        const gpio_base: usize = @intFromPtr(gpio_periph);
        const offset: usize = ((@as(u32, self.pio.num) + (32 * (@as(usize, self.pio.port)))));
        return @ptrFromInt(gpio_base + offset);
    }
};

/// Create a GPIO pin at port/num. Can be used at comptime.
pub fn create(port: u3, num: u5) Gpio {
    return Gpio{
        // The GPIO function is always on func zero
        .pad = pad.create(port, num, 0),
    };
}

fn port_to_ahbclock(port: u3) power_reset.AHBClock {
    return switch (port) {
        0 => power_reset.AHBClock.GPIO0,
        1 => power_reset.AHBClock.GPIO1,
        2 => power_reset.AHBClock.GPIO2,
        3 => power_reset.AHBClock.GPIO3,
        4 => power_reset.AHBClock.GPIO4,
        5 => power_reset.AHBClock.GPIO5,
        // we already check this input elsewhere, so this is unreachable
        else => unreachable,
    };
}
