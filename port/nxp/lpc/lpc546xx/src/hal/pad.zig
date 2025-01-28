//! Definitions and methods for configuring pins on this device to specific
//! functions and modes. TODO: make a big table or something for predefined pins

const micro = @import("microzig");
const std = @import("std");
const chip = micro.chip;

/// A pin Type that can be used to configure a pin to a certain function and mode.
/// This is used by all pin types, for GPIO use the GPIO type that wraps this
pub const Pad = packed struct(u14) {
    port: u3,
    num: u5,
    func: u4,
    type: PinType,

    /// Initialize this pin with a custom configuration
    pub fn init_with_config(self: *const Pad, config: Config) void {
        // Enable the clock to  the IOCON  block
        chip.peripherals.SYSCON.AHBCLKCTRLSET[0].modify(.{ .CLK_SET = 1 << 13 });
        const pin_iocon = get_iocon(self.port, self.num);
        pin_iocon.* = switch (self.type) {
            PinType.digital => Universalconfig{
                .FUNC = self.func,
                .MODE = @intFromEnum(config.mode),
                .I2CSLEW = 0,
                .INVERT = @intFromEnum(config.invert),
                .DIGIMODE = @intFromEnum(config.digimode),
                .FILTEROFF = @intFromEnum(config.filter),
                .SLEW_I2CDRIVE = @intFromEnum(config.slew),
                .OD_I2CFILTEROFF = @intFromEnum(config.open_drain),
            },
            PinType.i2c => Universalconfig{
                .FUNC = self.func,
                .MODE = 0,
                .I2CSLEW = @intFromEnum(config.i2c_slew),
                .INVERT = @intFromEnum(config.invert),
                .DIGIMODE = @intFromEnum(config.digimode),
                .FILTEROFF = @intFromEnum(config.filter),
                .SLEW_I2CDRIVE = @intFromEnum(config.i2c_drive),
                .OD_I2CFILTEROFF = @intFromEnum(config.i2c_filter),
            },
            PinType.analog => Universalconfig{
                .FUNC = self.func,
                .MODE = @intFromEnum(config.mode),
                .I2CSLEW = 0,
                .INVERT = @intFromEnum(config.invert),
                .DIGIMODE = @intFromEnum(config.digimode),
                .FILTEROFF = @intFromEnum(config.filter),
                .SLEW_I2CDRIVE = 0,
                .OD_I2CFILTEROFF = @intFromEnum(config.open_drain),
            },
        };

        // Disable the IOCON block to save power i guess
        chip.peripherals.SYSCON.AHBCLKCTRLCLR[0].modify(.{ .CLK_CLR = 1 << 13 });
    }

    /// Initialize this pin with the default configuration (floating)
    pub fn init(self: Pad) void {
        self.init_with_config(.{});
    }
};

/// Create a pin type from the port, pin number on this port and the function
/// These settings will only be applied after calling init() on this pin.
pub fn create(port: u3, pin: u5, func: u4) Pad {
    if (@inComptime()) {
        comptime {
            // Check that the port number is not higher than the max, which is 5.
            std.debug.assert(port <= 5);
        }
    } // else it should probably return an error or something
    return Pad{
        .port = port,
        .num = pin,
        .func = func,
        .type = PinType.from_num(port, pin),
    };
}

/// A pin confonfiguration type, use this to configure a pin in a custom way
/// By default it initializes to a floating digital pin. Note that some fields
/// are only used by I2C or Analog/Digital pins, if these are not applicable,
/// they can be left default, they will not be applied by Pin.init.
pub const Config = packed struct(u10) {
    // Resistor config.
    const Mode = enum(u2) {
        ///  Inactive. Inactive (no pull-down/pull-up resistor enabled).
        FLOAT = 0x0,
        ///  Pull-down. Pull-down resistor enabled.
        PULL_DOWN = 0x1,
        ///  Pull-up. Pull-up resistor enabled.
        PULL_UP = 0x2,
        ///  Repeater. Repeater mode.
        REPEATER = 0x3,
    };

    // Slew rate select for I2C pins
    const I2CSlew = enum(u1) {
        ///  I2C mode.
        I2C_MODE = 0x0,
        ///  GPIO mode.
        GPIO_MODE = 0x1,
    };

    // Invert polarity
    const Invert = enum(u1) {
        ///  Disabled. Input function is not inverted.
        DISABLED = 0x0,
        ///  Enabled. Input is function inverted.
        ENABLED = 0x1,
    };
    //  Select Analog/Digital mode.
    const Digimode = enum(u1) {
        ///  Analog mode.
        ANALOG = 0x0,
        ///  Digital mode.
        DIGITAL = 0x1,
    };
    //  Controls input glitch filter.
    const Filter = enum(u1) {
        ///  Filter enabled. Noise pulses below approximately 10 ns are filtered out.
        ENABLED = 0x0,
        ///  Filter disabled. No input filtering is done.
        DISABLED = 0x1,
    };
    //  Controls the current sink capability of the pin.
    const I2CDrive = enum(u1) {
        ///  Low drive. Output drive sink is 4 mA. This is sufficient for standard and fast mode I2C.
        LOW = 0x0,
        ///  High drive. Output drive sink is 20 mA. This is needed for Fast Mode Plus I 2C. Refer to the appropriate specific device data sheet for details.
        HIGH = 0x1,
    };

    //  Driver slew rate (D pin only).
    const Slew = enum(u1) {
        ///  Standard mode, output slew rate control is enabled. More outputs can be switched simultaneously.
        STANDARD = 0x0,
        ///  Fast mode, slew rate control is disabled. Refer to the appropriate specific device data sheet for details.
        FAST = 0x1,
    };

    //  Configures I2C features for standard mode, fast mode, and Fast Mode Plus operation.
    const I2CFilter = enum(u1) {
        ///  Enabled. I2C 50 ns glitch filter enabled.
        ENABLED = 0x0,
        ///  Disabled. I2C 50 ns glitch filter disabled.
        DISABLED = 0x1,
    };
    //  Controls open-drain mode.
    const OpenDrain = enum(u1) {
        ///  Normal. Normal push-pull output
        NORMAL = 0x0,
        ///  Open-drain. Simulated open-drain output (high drive disabled).
        OPEN_DRAIN = 0x1,
    };

    /// Pull-up/pull-down resistor config
    mode: Mode = .FLOAT,

    ///  Slew rate of I2C pad (type I pins only).
    i2c_slew: I2CSlew = .GPIO_MODE,

    ///  Input polarity.
    invert: Invert = .DISABLED,

    ///  Select Analog/Digital mode.
    digimode: Digimode = .DIGITAL,

    ///  Controls input glitch filter.
    filter: Filter = .ENABLED,

    ///  Controls the current sink capability of the pin (for I type pins only).
    i2c_drive: I2CDrive = .LOW,

    ///  Driver slew rate (for D type pins only).
    slew: Slew = .STANDARD,

    ///  Configures I2C features for standard mode, fast mode, and Fast Mode Plus operation (for I type pins only).
    i2c_filter: I2CFilter = .ENABLED,

    ///  Controls open-drain mode (for A and D type pins only).
    open_drain: OpenDrain = .OPEN_DRAIN,
};

/// The type (Digital, I2C, Analog) of a given pin. The LPC546xx has these three different
/// types defined in hardware, and they have slightly different configuration registers
/// which makes dealing with them kind of a pain.
pub const PinType = enum(u2) {
    digital,
    i2c,
    analog,
    pub fn from_num(port: u3, pin: u5) PinType {
        const I_pins = [_]struct { u3, u5 }{
            .{ 0, 13 },
            .{ 0, 14 },
            .{ 3, 23 },
            .{ 3, 24 },
        };

        const A_pins = [_]struct { u3, u5 }{
            .{ 0, 10 },
            .{ 0, 11 },
            .{ 0, 12 },
            .{ 0, 15 },
            .{ 0, 16 },
            .{ 0, 31 },
            .{ 1, 0 },
            .{ 2, 0 },
            .{ 2, 1 },
            .{ 3, 21 },
            .{ 3, 22 },
            .{ 0, 23 },
        };

        return blk: {
            for (I_pins) |I_pin| {
                if (port == I_pin[0] and pin == I_pin[1]) {
                    break :blk PinType.i2c;
                }
            }

            for (A_pins) |A_pin| {
                if (port == A_pin[0] and pin == A_pin[1]) {
                    break :blk PinType.analog;
                }
            }

            break :blk PinType.digital;
        };
    }
};

/// a MMIO packed struct type for a pin IOCON register that is universal,
/// the code internally sets the fields to the correct value for a given pintype
const Universalconfig = packed struct(u32) {
    FUNC: u4,
    MODE: u2,
    I2CSLEW: u1,
    INVERT: u1,
    DIGIMODE: u1,
    FILTEROFF: u1,
    SLEW_I2CDRIVE: u1,
    OD_I2CFILTEROFF: u1,
    padding: u20 = 0,
};

// Some pointer trickery to be able to index into the iocon pin registers instead
// of having to use a gaint switch block haha.
fn get_iocon(port: u3, pin: u5) *volatile Universalconfig {
    //0x40001000 + (num +  32*port)*4
    const base: usize = @intFromPtr(chip.peripherals.IOCON);
    const offset: usize = ((@as(u32, pin) + (32 * (@as(usize, port))))) << 2;

    return @ptrFromInt(base + offset);
}

pub const PIO2_2_GPIO = create(2, 2, 0);
pub const PIO3_3_GPIO = create(3, 3, 0);
pub const PIO3_14_GPIO = create(3, 14, 0);
