//basic blinky example

const std = @import("std");
const microzig = @import("microzig");
const hal = microzig.hal;

const led_gpio = hal.gpio.create(2, 2);

pub fn main() !void {
    led_gpio.init(true);

    var a: u32 = 0;

    while (true) : (a +%= 1) {
        if (a % 10000000 == 0) {
            led_gpio.toggle();
        }
    }
}
