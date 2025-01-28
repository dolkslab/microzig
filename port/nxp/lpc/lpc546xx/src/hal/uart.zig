const std = @import("std");
const micro: type = @import("microzig");
const interrupt = micro.interrupt;
// pub const chip = struct {
//     const inner = @import("../chips/LPC54628.zig");
//     pub const types = inner.types;
//     pub usingnamespace @field(inner.devices, "LPC54628");
// };

const chip = micro.chip;
const cpu = micro.cpu;
const pad = @import("pad.zig");
const power_reset = @import("power_reset.zig");
const flexcomm = @import("flexcomm.zig");
const misc_math = @import("../util/misc_math.zig");

const USARTMmio = chip.types.peripherals.USART0;

// possibly split this into multiple drivers, for blocking interrupt etc.

/// Uart driver type. Keeps track of assigned pins and flexcomm nr. Supports:
/// - Configuration of the peripheral for a given Mode, see the struct below
/// - interface for enabling and disabling interrupts for associated with the driver instance.
/// - Low level abstractions over register interface to check FIFO level, and to push and pull data.
/// - Polling mode (blocking) interfaces for reading and writing slices of data. Also includes std.io.genericWriter and genericReader interfaces for these modes.
/// - Interrupt driven mode using callbacks to define functionality.
pub const Uart = struct {
    mmio: *volatile USARTMmio,
    flexcomm_nr: flexcomm.Flexcomm,

    rx_pin: pad.Pad,
    tx_pin: pad.Pad,

    isr_writer_callback: ?WriterCallback,
    isr_reader_callback: ?ReaderCallback,

    pub fn lock(self: *const Uart) void {
        interrupt.disable(self.flexcomm_nr.irqn());
    }

    pub fn unlock(self: *const Uart) void {
        interrupt.enable(self.flexcomm_nr.irqn());
    }

    pub fn is_locked(self: *const Uart) void {
        interrupt.is_enabled(self.flexcomm_nr.irqn());
    }

    /// GenericWriter and Reader interfaces for blocking read and write
    pub const Writer = std.io.GenericWriter(*const Uart, TransmitError, generic_writer_fn);
    pub const Reader = std.io.GenericReader(*const Uart, RecieveError, generic_reader_fn);

    pub fn writer(self: *const Uart) Writer {
        return .{ .context = self };
    }

    pub fn reader(self: *const Uart) Reader {
        return .{ .context = self };
    }

    /// Initialize the driver for a given UART mode
    pub fn init(self: *Uart, baud_rate: u32, mode: Mode) void {
        self.flexcomm_nr.enable_ahb_clock();

        // select the UART function for this Flexcomm perihperal
        self.flexcomm_nr.set_function(.USART);
        // calculate the clock dividers to obtained the requested baud rate.
        const clock_ratio = misc_math.clock_divider(48_000_000, baud_rate);
        const clock_dividers = calc_uart_clock_dividers(clock_ratio);

        // for now the UART peripheral is hardcoded to use the FRO_HF clock,
        // since this clock is available for both the FRG and

        if (clock_dividers.Fmult == 0) {
            self.flexcomm_nr.set_clock_source(.FRO_HF_DIV);
        } else {
            self.flexcomm_nr.set_clock_source(.FRG_CLOCK_OUTPUT);
            chip.peripherals.SYSCON.FRGCLKSEL.modify(.{ .SEL = .FRO_HF });
            chip.peripherals.SYSCON.FRGCTRL.modify(.{
                .DIV = 255,
                .MULT = clock_dividers.Fmult,
            });
        }

        // Configure the uart to the requested mode.
        self.mmio.CFG.write(.{
            // actual configuration options
            .ENABLE = .DISABLED,
            .DATALEN = @enumFromInt(@as(u2, @truncate(mode.data_len - 7))),
            .PARITYSEL = @enumFromInt(@intFromEnum(mode.parity)),
            .STOPLEN = @enumFromInt(@as(u1, @truncate(mode.n_stop_bits - 1))),
            .CTSEN = .DISABLED,

            // mental disorders
            .MODE32K = .DISABLED,
            .LINMODE = .DISABLED,
            .SYNCEN = .ASYNCHRONOUS_MODE,
            .CLKPOL = .FALLING_EDGE,
            .LOOP = .NORMAL,
            .SYNCMST = .SLAVE,
            .reserved18 = 0,
            .AUTOADDR = .DISABLED,
            .OESEL = .STANDARD,
            .OEPOL = .LOW,
            .RXPOL = .STANDARD,
            .TXPOL = .STANDARD,
            .OETA = .DISABLED,
            .reserved2 = 0,
            .reserved11 = 0,
            .reserved14 = 0,
            .padding = 0,
        });

        // Set the BRGVAL clock divider and oversample rate
        self.mmio.BRG.modify(.{ .BRGVAL = clock_dividers.Bdiv });
        self.mmio.OSR.modify(.{ .OSRVAL = clock_dividers.OSR });

        // enable and clear the FIFOs
        self.mmio.FIFOCFG.modify(.{
            .ENABLETX = .ENABLED,
            .ENABLERX = .ENABLED,
            .EMPTYTX = 1,
            .EMPTYRX = 1,
        });

        // setup the FIFO level triggers to default values
        // (1 in RX buffer or 0 in TX buffer)
        self.set_trigger_config(.{});

        // clear all interrupts
        self.mmio.INTENCLR.modify(.{
            .TXIDLECLR = 1,
            .DELTACTSCLR = 1,
            .TXDISCLR = 1,
            .DELTARXBRKCLR = 1,
            .STARTCLR = 1,
            .FRAMERRCLR = 1,
            .PARITYERRCLR = 1,
            .RXNOISECLR = 1,
            .ABERRCLR = 1,
        });
        self.mmio.FIFOINTENCLR.write_raw(0xF);

        self.rx_pin.init_with_config(.{ .mode = .FLOAT });
        self.tx_pin.init_with_config(.{ .mode = .FLOAT });

        self.mmio.CFG.modify(.{ .ENABLE = .ENABLED });
    }

    pub fn set_trigger_config(self: *const Uart, cfg: TriggerConfig) void {
        self.mmio.FIFOTRIG.write(.{
            .TXLVLENA = @enumFromInt(@intFromBool(cfg.tx_enabled)),
            .RXLVLENA = @enumFromInt(@intFromBool(cfg.rx_enabled)),
            .TXLVL = cfg.tx_level,
            .RXLVL = @as(u4, @truncate(cfg.rx_level - 1)),
            .reserved8 = 0,
            .reserved16 = 0,
            .padding = 0,
        });
    }

    /// Checks if the transmit buffer is able to recieve a word
    pub fn can_push(self: *const Uart) bool {
        return self.mmio.FIFOSTAT.read().TXNOTFULL != 0;
    }

    /// Checks if the transmit buffer is empty
    pub fn is_push_queue_empty(self: *const Uart) bool {
        // transmit fifo completely empty
        return self.mmio.FIFOSTAT.read().TXEMPTY != 0;
    }

    /// Get the exact number of words that can be pushed into the transmit buffer
    pub fn can_push_count(self: *const Uart) u5 {
        const FIFO_BUFSIZE: u5 = 16;
        return FIFO_BUFSIZE - self.mmio.FIFOSTAT.read().TXLVL;
    }

    /// Checks if the recieve buffer has a word ready to be read
    pub fn can_pull(self: *const Uart) bool {
        //recieve fifo not empty
        return self.mmio.FIFOSTAT.read().RXNOTEMPTY != 0;
    }

    /// Get the exact number of words that can be pulled from the recieve buffer
    pub fn can_pull_count(self: *const Uart) u5 {
        return self.mmio.FIFOSTAT.read().TXLVL;
    }

    /// Push a word into the transmit buffer. T corresponds to the number of bits
    /// per word the UART was configured for.
    pub fn push(self: *const Uart, comptime T: type, value: T) void {
        self.mmio.FIFOWR.write_raw(@as(u32, value));
    }

    /// Pull a word out of the recieve buffer. T corresponds to the number of bits
    /// per word the UART was configured for.
    pub fn pull(self: *const Uart, comptime T: type) T {
        return @truncate(self.mmio.FIFORD.raw);
    }

    pub fn pull_with_errors(self: *const Uart, comptime T: type) RecieveError!T {
        const read_val: u32 = self.mmio.FIFORD.raw;

        const overrun_err: u1 = self.mmio.FIFOSTAT.read().RXERR;
        const err_bits: u4 = overrun_err + @as(u4, @truncate(read_val >> 12)) & 0b1110;
        if (err_bits == 0) {
            return @truncate(read_val);
        } else if (err_bits >= 8) {
            return RecieveError.NoiseError;
        } else if (err_bits >= 4) {
            return RecieveError.ParityError;
        } else if (err_bits >= 2) {
            return RecieveError.FramingError;
        } else {
            return RecieveError.OverrunError;
        }
    }

    pub fn clear_errors(self: *const Uart) void {
        self.mmio.FIFOSTAT.write_raw(0b11);
        self.mmio.STAT.modify(.{
            .FRAMERRINT = 1,
            .PARITYERRINT = 1,
            .RXNOISEINT = 1,
        });
    }

    /// Write a slice of data in polling mode (Blocking). Currently has no timeout.
    pub fn write_blocking(self: *const Uart, payload: []const u8) TransmitError!void {
        var tx_remaining: usize = payload.len - blk: {
            self.mmio.CTL.modify(.{ .TXDIS = .DISABLED });

            const tx_free = self.can_push_count();
            var bytes_pushed: u5 = 0;
            while (bytes_pushed < tx_free and bytes_pushed < payload.len) {
                self.push(u8, payload[bytes_pushed]);
                bytes_pushed += 1;
            }

            self.mmio.CTL.modify(.{ .TXDIS = .ENABLED });
            break :blk bytes_pushed;
        };

        while (tx_remaining > 0) {
            while (!self.can_push()) {
                // add an error timeout feature here
                cpu.nop();
            }

            self.push(u8, payload[payload.len - tx_remaining]);

            tx_remaining -= 1;
        }
    }

    fn generic_writer_fn(self: *const Uart, buffer: []const u8) TransmitError!usize {
        try self.write_blocking(buffer);

        return buffer.len;
    }

    /// Read a slice of data in polling mode (Blocking). This can return an error
    /// if the peripheral detects an error in the UART link.
    pub fn read_blocking(self: *const Uart, buffer: []u8) RecieveError!void {
        for (buffer) |*byte| {
            while (!self.can_pull()) {
                cpu.nop();
            }
            byte.* = try self.pull_with_errors(u8);
        }
    }

    pub fn generic_reader_fn(self: *const Uart, buffer: []u8) RecieveError!usize {
        try self.read_blocking(buffer);

        return buffer.len;
    }

    pub fn interrupt_transmit_start(self: *Uart, callback: WriterCallback) void {
        // lock the driver while we modify interrupt stuff.
        self.lock();
        defer self.unlock();

        cpu.compiler_barrier();
        self.isr_writer_callback = callback;

        // enable the interrupt for TXLVL
        self.mmio.FIFOINTENSET.modify(.{ .TXLVL = .{ .value = .ENABLED } });
    }

    pub fn is_interrupt_transmit_in_progress(self: *const Uart) bool {
        return self.isr_writer_callback != null;
    }

    pub fn interrupt_transmit_end(self: *Uart) void {
        // lock the driver while we modify interrupt stuff.
        self.lock();
        defer self.unlock();

        cpu.compiler_barrier();

        // disable the TXLVL interrupt
        self.mmio.FIFOINTENCLR.write_raw(4);
        self.isr_writer_callback = null;
    }

    pub fn interrupt_recieve_start(self: *Uart, callback: ReaderCallback) void {
        // lock the driver while we modify interrupt stuff.
        self.lock();
        defer self.unlock();

        cpu.compiler_barrier();
        self.isr_reader_callback = callback;

        // enable the interrupt for RXLVL
        self.mmio.FIFOINTENSET.modify(.{ .RXLVL = .{ .value = .ENABLED } });
    }

    pub fn is_interrupt_recieve_in_progress(self: *const Uart) bool {
        return self.isr_reader_callback != null;
    }

    pub fn interrupt_recieve_end(self: *Uart) void {
        // lock the driver while we modify interrupt stuff.
        self.lock();
        defer self.unlock();

        cpu.compiler_barrier();

        // disable the TXLVL interrupt
        self.mmio.FIFOINTENCLR.write_raw(8);
        self.isr_reader_callback = null;
    }

    pub fn isr_worker(self: *Uart) void {
        while (self.can_push()) {
            if (self.isr_writer_callback) |writer_callback| {
                self.push(u8, writer_callback.call());
            } else {
                break;
            }
        }

        while (self.can_pull()) {
            if (self.isr_reader_callback) |reader_callback| {
                reader_callback.call(self.pull_with_errors(u8));
            } else {
                break;
            }
        }
        return;
    }

    pub fn isr_wrapper(self: *Uart) interrupt.Handler {
        const ret = .{ .C = struct {
            fn wrapper() callconv(.C) void {
                @call(.always_inline, isr_worker, .{self});
            }
        }.wrapper };
        return ret;
    }
};

pub fn create(flexcomm_inst: flexcomm.Flexcomm, rx_pin: pad.Pad, tx_pin: pad.Pad) Uart {
    return Uart{
        .flexcomm_nr = flexcomm_inst,
        .mmio = @ptrCast(flexcomm_inst.mmio_ptr()),
        .rx_pin = rx_pin,
        .tx_pin = tx_pin,
        .isr_writer_callback = null,
        .isr_reader_callback = null,
    };
}

pub const WriterCallback = struct {
    function: *const fn (context: ?*anyopaque) u8,
    context: ?*anyopaque,
    pub fn create(comptime T: type, function: *const fn (context: ?*T) u8, context: *T) WriterCallback {
        return WriterCallback{ .function = @ptrCast(function), .context = context };
    }

    pub fn call(callback: WriterCallback) u8 {
        return callback.function(callback.context);
    }
};

pub const ReaderCallback = struct {
    function: *const fn (context: ?*anyopaque, data: RecieveError!u8) void,
    context: ?*anyopaque,
    pub fn create(comptime T: type, function: *const fn (context: ?*T, data: RecieveError!u8) void, context: *T) ReaderCallback {
        return ReaderCallback{ .function = @ptrCast(function), .context = context };
    }

    pub fn call(callback: ReaderCallback, data: RecieveError!u8) void {
        return callback.function(callback.context, data);
    }
};

pub const TransmitError = error{
    Timeout,
    BufferFull,
};

pub const RecieveError = error{
    OverrunError,
    ParityError,
    FramingError,
    NoiseError,
    Timeout,
};

pub const Mode = struct {
    const Parity = enum(u2) {
        NONE = 0,
        EVEN = 2,
        ODD = 3,
    };
    // Lenght of a single data word, usually 8. Can be 7, 8 or 9.
    data_len: u4 = 8,
    // Parity type. Usually none, can be none, even or odd.
    parity: Parity = .NONE,
    // number of stop bits. Usually 1. Can be 1 or 2.
    n_stop_bits: u2 = 1,
};

pub const TriggerConfig = packed struct {
    rx_enabled: bool = true,
    rx_level: u5 = 1,
    tx_enabled: bool = true,
    tx_level: u4 = 0,
};

/// Function to calculate clock divider for a given baud rate
/// This could probably be replaced by a table that works for just the common baud rates
/// but oh well.
fn calc_uart_clock_dividers(ratio: misc_math.ufp24_8) struct {
    Bdiv: u16,
    OSR: u4,
    Fmult: u8,
} {
    var chosen_osr: u5 = 16;
    var chosen_fmult: u32 = @intCast(calc_frg_clock_divider(ratio, chosen_osr));

    var fractional: u32 = (@as(u32, 256) + chosen_fmult) * @as(u32, @intCast(chosen_osr));
    var chosen_bdiv: u32 = misc_math.divClosest(u32, ratio, fractional) catch unreachable;
    var approx_ratio: u32 = fractional * chosen_bdiv;
    var chosen_error: i64 = @as(i64, approx_ratio) - @as(i64, ratio);

    var osr: u5 = 15;
    while (osr >= 10) {
        const fmult: u32 = @intCast(calc_frg_clock_divider(ratio, osr));
        fractional = (@as(u32, 256) + chosen_fmult) * osr;
        const bdiv: u32 = misc_math.divClosest(u32, ratio, fractional) catch unreachable;
        approx_ratio = fractional * bdiv;

        const err: i64 = @as(i64, approx_ratio) - @as(i64, ratio);

        if (@abs(err) < @abs(chosen_error)) {
            chosen_error = err;
            chosen_bdiv = bdiv;
            chosen_osr = osr;
            chosen_fmult = fmult;
        }

        osr -= 1;
    }

    return .{
        .Bdiv = @truncate(chosen_bdiv - 1),
        .OSR = @truncate(chosen_osr - 1),
        .Fmult = @truncate(chosen_fmult),
    };
}

/// Global variable to store the clock rate of the FRG clock, since there is only one
var frg_clock: ?u9 = null;
fn calc_frg_clock_divider(ratio: u32, OSR: u8) u9 {
    // This is a shitty function sorry
    // It finds the optimal value of fmult to get
    // as close to an integer multiple of the given ratio as possible
    // ratio is in 24.8 fixed point

    // I just bruteforced it, there are just not that many datapoints here to
    // justify a more elaborate search method, and I couldn't think of a smart
    // way to do this

    if (frg_clock) |fmult| {
        return fmult;
    }

    var chosen_fmult: u9 = 0;
    var chosen_error: u32 = ratio & 0xff;

    // If the ratio is an integer mulitple we don't need to use the frg
    if (chosen_error == 0) {
        return 0;
    }

    var fmult: u9 = 1;
    while (fmult < 255) {
        const err: u32 = blk: {
            const tmp_error: u32 = ((0x100 * @as(u32, ratio)) / ((0x100 + @as(u32, fmult)) * @as(u32, OSR))) & 0xff;
            if (tmp_error < 128) {
                break :blk tmp_error;
            } else {
                break :blk 0x100 - tmp_error;
            }
        };

        if (err < chosen_error) {
            chosen_error = err;
            chosen_fmult = fmult;
        }

        fmult += 1;
    }

    return chosen_fmult;
}
