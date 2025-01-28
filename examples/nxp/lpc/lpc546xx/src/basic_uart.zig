const std = @import("std");
const microzig = @import("microzig");

const hal = microzig.hal;

const led_gpio = hal.gpio.create(2, 2);
var UART0 = hal.uart.create(
    .FC0,
    hal.pad.create(0, 30, 1),
    hal.pad.create(0, 29, 1),
);

pub fn main() !void {
    led_gpio.init(true);

    var a: u32 = 0;

    UART0.init(
        115200,
        .{},
    );

    while (true) : (a +%= 1) {
        if (a % 10000000 == 0) {
            led_gpio.toggle();
            UART0.writer().print("hello world !\n", .{}) catch unreachable;
            //UART0.push(u8, 'a');
        }
    }
}
