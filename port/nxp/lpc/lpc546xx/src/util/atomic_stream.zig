const std = @import("std");

/// Circular buffer that can (hopefully) be re read and written from two different contexts.
/// Useful for e.g. writing to a buffer that is then read in interrupt handler.
/// Should be moved to a better place
pub const AtomicStream = struct {
    _buffer: []u8,

    _read_index: usize = 0,
    _write_index: usize = 0,

    _push_count: usize = 0,
    _pop_count: usize = 0,

    /// Inits this stream around the given buffer
    pub fn init(buffer: []u8) AtomicStream {
        return AtomicStream{
            ._buffer = buffer,
        };
    }

    /// Return the capacity of the wrapped buffer
    pub fn capacity(self: *const AtomicStream) usize {
        return self._buffer.len;
    }

    /// Atomicially(?) calculates the lenght of this buffer
    pub fn len(self: *const AtomicStream) usize {
        // lets see how this works
        const tmp: usize = @atomicLoad(usize, &self._push_count, std.builtin.AtomicOrder.acquire) -%
            @atomicLoad(usize, &self._pop_count, std.builtin.AtomicOrder.acquire);
        return tmp;
    }

    pub fn available_space(self: *const AtomicStream) usize {
        return self.capacity() - self.len();
    }

    pub fn has_space(self: *const AtomicStream, space: usize) bool {
        return self.available_space() >= space;
    }

    pub fn is_full(self: *const AtomicStream) bool {
        return self.len() == self.capacity();
    }

    pub fn is_empty(self: *const AtomicStream) bool {
        return self.len() == 0;
    }

    pub fn write(self: *AtomicStream, value: u8) Error!void {
        if (self.is_full()) return Error.Full;

        self._buffer[self._write_index] = value;
        // it is ok for the pop and push count to wrap.
        self._write_index = wrap_write_idx: {
            // lets assume someone isnt trying to make this buffer the size of the entire adress space...
            const tmp: usize = self._write_index + 1;
            if (tmp == self.capacity()) {
                break :wrap_write_idx 0;
            } else {
                break :wrap_write_idx tmp;
            }
        };
        _ = @atomicRmw(usize, &self._push_count, std.builtin.AtomicRmwOp.Add, @as(usize, 1), std.builtin.AtomicOrder.release);
    }

    pub fn write_slice(self: *AtomicStream, slice: []const u8) Error!void {
        if (!self.has_space(slice.len)) return Error.Full;

        _ = @atomicRmw(usize, &self._push_count, std.builtin.AtomicRmwOp.Add, slice.len, std.builtin.AtomicOrder.release);

        for (slice) |value| {
            self._buffer[self._write_index] = value;
            // We have to update this after every byte written since we assume this context can get interrupted
            // at any point by another that reads from this stream.

            self._write_index = wrap_write_idx: {
                // lets assume someone isnt trying to make this buffer the size of the entire adress space...
                const tmp: usize = self._write_index + 1;
                if (tmp == self.capacity()) {
                    break :wrap_write_idx 0;
                } else {
                    break :wrap_write_idx tmp;
                }
            };
        }
    }

    pub fn read(self: *AtomicStream) Error!u8 {
        if (self.is_empty()) return Error.ReadLength;

        const value: u8 = self._buffer[self._read_index];
        // it is ok for the pop and push count to wrap.
        _ = @atomicRmw(usize, &self._pop_count, std.builtin.AtomicRmwOp.Add, @as(usize, 1), std.builtin.AtomicOrder.release);

        self._read_index = wrap_read_idx: {
            // lets assume someone isnt trying to make this buffer the size of the entire adress space...
            const tmp: usize = self._read_index + 1;
            if (tmp == self.capacity()) {
                break :wrap_read_idx 0;
            } else {
                break :wrap_read_idx tmp;
            }
        };

        return value;
    }

    pub fn peek_last(self: *AtomicStream) Error!u8 {
        if (self.is_empty()) return Error.ReadLength;

        return self._buffer[self._write_index - 1];
    }

    pub fn read_slice(self: *AtomicStream, slice: []u8) Error!void {
        if (slice.len > self.len()) return Error.ReadLength;

        _ = @atomicRmw(usize, &self._pop_count, std.builtin.AtomicRmwOp.Add, slice.len, std.builtin.AtomicOrder.release);

        for (slice) |*value| {
            value.* = self._buffer[self._read_index];

            self._read_index = wrap_read_idx: {
                // lets assume someone isnt trying to make this buffer the size of the entire adress space...
                const tmp: usize = self._read_index + 1;
                if (tmp == self.capacity()) {
                    break :wrap_read_idx 0;
                } else {
                    break :wrap_read_idx tmp;
                }
            };
        }
    }

    pub const Error = error{
        Full,
        ReadLength,
    };
};

test AtomicStream {
    var buf: [8]u8 = undefined;
    var stream = AtomicStream.init(&buf);

    try stream.write(1);
    try stream.write(2);

    try std.testing.expect((try stream.read()) == 1);
    try std.testing.expect((try stream.read()) == 2);

    try std.testing.expect(stream.len() == 0);
    try std.testing.expect(stream._push_count == 2);
    try std.testing.expect(stream._pop_count == 2);

    const dummy_input: [8]u8 = .{ 56, 34, 23, 65, 21, 87, 69, 8 };

    try stream.write_slice(&dummy_input);

    try std.testing.expect(stream.available_space() == 0);

    try std.testing.expectError(AtomicStream.Error.Full, stream.write(69));

    var dummy_output: [8]u8 = undefined;
    var too_long = [9]u8{ 1, 2, 3, 4, 5, 6, 7, 8, 9 };

    try std.testing.expectError(AtomicStream.Error.ReadLength, stream.read_slice(&too_long));

    try stream.read_slice(&dummy_output);

    try std.testing.expectError(AtomicStream.Error.ReadLength, stream.read());

    try std.testing.expect(std.mem.eql(u8, &dummy_input, &dummy_output));

    try std.testing.expectError(AtomicStream.Error.Full, stream.write_slice(&too_long));

    stream._push_count = @as(usize, 0) -% 1;
    stream._pop_count = @as(usize, 0) -% 1;
    try stream.write(69);
    try std.testing.expect(stream._push_count == 0);
    try std.testing.expect(try stream.read() == 69);
    try std.testing.expect(stream.len() == 0);
}
