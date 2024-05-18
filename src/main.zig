const std = @import("std");
const debug = std.debug;
const builtin = @import("builtin");
const log = std.log;
const fmt = std.fmt;
const time = std.time;
const mem = std.mem;
const heap = std.heap;
const process = std.process;
const io = std.io;

const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const TokenIterator = std.mem.TokenIterator;
const ArrayList = std.ArrayList;

const ma = @cImport({
    @cInclude("miniaudio.h");
});

pub const std_options = .{
    .log_level = switch (builtin.mode) {
        .Debug => .debug,
        else => .info,
    },
};

pub fn main() !void {
    var gpa = heap.GeneralPurposeAllocator(.{}){};
    defer debug.assert(gpa.deinit() == .ok);
    const allocator = gpa.allocator();

    // read file path from commandline args
    //
    var args = try process.argsWithAllocator(allocator);
    defer args.deinit();
    _ = args.next();
    const sound_file_path = args.next() orelse return error.ArgsNotFound;
    log.info("sound file path: {s}", .{sound_file_path});

    // engine init
    //
    var engine = try Engine.init(allocator);
    defer engine.deinit();

    // sound init
    //
    var sound = try Sound.init(&engine, sound_file_path, .{ .streaming = true, .predecode = false, .pitch = true });
    defer sound.deinit();

    // sound start
    //
    try sound.start();

    // wait for instruction
    //
    while (true) {
        try io.getStdOut().writer().print("Press instruction: ", .{});
        var buffer: [100]u8 = undefined;
        const ins = try readline(&buffer);
        var ins_tks = mem.tokenizeAny(u8, ins, " \t");
        if (ins_tks.next()) |tk| {
            switch (tk[0]) {
                'q' => break,
                'p' => try sound.pauseOrResume(),
                'm' => sound.mute(),
                '0' => sound.incVolume(0.1),
                '9' => sound.incVolume(-0.1),
                'g' => gotoNextNthSecond(sound, &ins_tks),
                'G' => gotoNthSecond(sound, &ins_tks),
                'l' => setLoopPoint(sound, &ins_tks),
                'L' => sound.loop(),
                'i' => printInfo(sound),
                'j' => setPitch(sound, &ins_tks),
                'k' => setPan(sound, &ins_tks),
                'v' => setVolume(sound, &ins_tks),
                'd' => printDeviceInfoList(allocator),
                else => continue,
            }
        } else {
            continue;
        }
    }
}

fn printDeviceInfoList(allocator: Allocator) void {
    var context = Context.init(allocator) catch return;
    defer context.deinit();

    var device_info_list = context.getDeviceInfoList() catch return;
    defer device_info_list.deinit();

    for (device_info_list.playbacks.items) |dev| {
        // const id_str = try dev.idStr(allocator);
        // defer allocator.free(id_str);
        const id_str = "";

        log.info(
            \\
            \\ PLAYBACK
            \\     id                  : {any}
            \\     id(string)          : {s}
            \\     name                : {s}
            \\     is_default          : {any}
            \\     native_data_formats : {any}
        , .{ dev.id, id_str, dev.name, dev.is_default, dev.native_data_formats });
    }

    for (device_info_list.captures.items) |dev| {
        // const id_str = try dev.idStr(allocator);
        // defer allocator.free(id_str);
        const id_str = "";

        log.info(
            \\
            \\ CAPTURE
            \\     id                  : {any}
            \\     id(string)          : {s}
            \\     name                : {s}
            \\     is_default          : {any}
            \\     native_data_formats : {any}
        , .{ dev.id, id_str, dev.name, dev.is_default, dev.native_data_formats });
    }
}

fn setVolume(sound: Sound, ins_tks: *TokenIterator(u8, .any)) void {
    const volume_str = ins_tks.next() orelse return;
    const volume = fmt.parseFloat(f32, volume_str) catch return;
    sound.setVolume(volume);
}

fn setPitch(sound: Sound, ins_tks: *TokenIterator(u8, .any)) void {
    const pitch_str = ins_tks.next() orelse return;
    const pitch = fmt.parseFloat(f32, pitch_str) catch return;
    sound.setPitch(pitch);
}
fn setPan(sound: Sound, ins_tks: *TokenIterator(u8, .any)) void {
    const pan_str = ins_tks.next() orelse return;
    const pan = fmt.parseFloat(f32, pan_str) catch return;
    sound.setPan(pan);
}

fn setLoopPoint(sound: Sound, ins_tks: *TokenIterator(u8, .any)) void {
    const begin_time_str = ins_tks.next() orelse return;
    const end_time_str = ins_tks.next() orelse return;

    const begin_second = parseSeconds(begin_time_str) catch return;
    const end_second = parseSeconds(end_time_str) catch return;

    sound.setLoopPointInSecond(begin_second, end_second) catch return;
}

fn gotoNextNthSecond(sound: Sound, ins_tks: *TokenIterator(u8, .any)) void {
    const time_str = ins_tks.next() orelse return;
    const offset = fmt.parseInt(i64, time_str, 10) catch return;
    sound.gotoNextNthSecond(offset) catch return;
}

fn gotoNthSecond(sound: Sound, ins_tks: *TokenIterator(u8, .any)) void {
    const time_str = ins_tks.next() orelse return;
    const nth_second = parseSeconds(time_str) catch return;
    sound.gotoNthSecond(nth_second) catch return;
}

fn parseSeconds(time_str: []const u8) !u32 {
    var tks = mem.tokenizeScalar(u8, time_str, ':');
    const a = try parseIntForTime(tks.next() orelse return error.ParseSeconds);
    const b = tks.next();
    const c = tks.next();

    // 01:01:01
    //
    if (c) |second| {
        const nth_hour = a;
        if (nth_hour > 23) return error.ParseSeconds;
        const nth_minute = try parseIntForTime(b.?);
        if (nth_minute > 59) return error.ParseTimeAsSeconds;
        const nth_second = try parseIntForTime(second);
        if (nth_second > 59) return error.ParseTimeAsSeconds;
        return nth_hour * 60 * 60 + nth_minute * 60 + nth_second;
    } else {
        // 01:01
        //
        if (b) |second| {
            const nth_minute = a;
            if (nth_minute > 59) return error.ParseSeconds;
            const nth_second = try parseIntForTime(second);
            return nth_minute * 60 + nth_second;
        }
        // 01
        //
        else {
            const nth_second = a;
            return nth_second;
        }
    }
}

/// "01" -> 1
///
fn parseIntForTime(time_str: []const u8) !u32 {
    const valid_time_str = try getValidSliceForTime(time_str);
    return try fmt.parseInt(u32, valid_time_str, 10);
}

/// "01" -> "1"
///
fn getValidSliceForTime(time_str: []const u8) ![]const u8 {
    switch (time_str.len) {
        1 => return time_str,
        2 => {
            if (time_str[0] == '0') {
                return time_str[1..];
            } else {
                return time_str;
            }
        },
        else => return error.GetValidSliceForTime,
    }
}

fn printInfo(sound: Sound) void {
    const frame_rate = sound.engine.getSampleRate();
    const channels = sound.engine.getChannels();

    const nth_frame: u64 = sound.getNthFrame() catch 0;
    const total_frames: u64 = sound.getTotalFrames() catch 0;

    const nth_millis: u64 = sound.getNthMillis() catch 0;
    const total_millis: u64 = sound.getTotalMillis() catch 0;

    const data_format = sound.getDataFormat() catch mem.zeroes(SoundDataFormat);

    const volume = sound.getVolume();
    const muting = if (sound.isMuted()) "yes" else "no";
    const playing = if (sound.isPlaying()) "yes" else "no";
    const looping = if (sound.isLooping()) "yes" else "no";

    const pitch = sound.getPitch();
    const pan = sound.getPan();

    log.info(
        \\
        \\  TIME       : {} / {}
        \\  TIME(ms)   : {d} / {d}
        \\  FRAME      : {d} / {d}
        \\  FRAME_RATE : {d}
        \\  CHANNELS   : {d}
        \\  DATA_FORMAT: {any}
        \\  PAN        : {d}
        \\  PITCH      : {d}
        \\  VOLUME     : {d}
        \\  MUTING     : {s}
        \\  PLAYING    : {s}
        \\  LOOPING    : {s}
    , .{
        fmt.fmtDuration(nth_millis * time.ns_per_ms),
        fmt.fmtDuration(total_millis * time.ns_per_ms),
        nth_millis,
        total_millis,
        nth_frame,
        total_frames,
        frame_rate,
        channels,
        data_format,
        pan,
        pitch,
        volume,
        muting,
        playing,
        looping,
    });
}

fn readline(buf: []u8) ![]const u8 {
    return trimBlanks(try io.getStdIn().reader().readUntilDelimiter(buf, '\n'));
}

fn trimBlanks(buf: []const u8) []const u8 {
    return mem.trim(u8, buf, " \t\r\n");
}

pub const Engine = struct {
    allocator: Allocator,
    ma_engine: *ma.ma_engine,

    /// init
    ///
    /// ```
    /// var engine = try Engine.init(allocator);
    /// defer engine.deinit();
    /// ```
    ///
    pub fn init(allocator: Allocator) !Engine {
        const ma_engine = try allocator.create(ma.ma_engine);
        errdefer allocator.destroy(ma_engine);

        if (ma.ma_engine_init(null, ma_engine) != ma.MA_SUCCESS) {
            return error.MAEngineInit;
        }

        return .{
            .allocator = allocator,
            .ma_engine = ma_engine,
        };
    }

    /// deinit
    ///
    /// ```
    /// var engine = try Engine.init(allocator);
    /// defer engine.deinit();
    /// ```
    ///
    pub fn deinit(self: *Engine) void {
        log.debug("deinit engine", .{});
        ma.ma_engine_uninit(self.ma_engine);
        self.allocator.destroy(self.ma_engine);
        self.* = undefined;
    }

    /// get sample rate per channel (aka. frame rate)
    ///
    /// ```
    /// const sample_rate = engine.getSampleRate();
    /// ```
    ///
    pub fn getSampleRate(self: Engine) u32 {
        return ma.ma_engine_get_sample_rate(self.ma_engine);
    }

    /// get channels
    ///
    /// ```
    /// const channels = engine.getChannels();
    /// ```
    ///
    pub fn getChannels(self: Engine) u32 {
        return ma.ma_engine_get_channels(self.ma_engine);
    }
};

pub const SoundFlags = struct {
    ///
    streaming: bool = true,

    /// predecode before loading into memory (invalid when streaming is true)
    predecode: bool = false,

    /// enable pitch
    pitch: bool = true,

    /// convert to miniaudio sound flags value
    ///
    pub fn toMASoundFlags(self: SoundFlags) ma.ma_uint32 {
        var result: ma.ma_uint32 = 0;
        if (self.streaming) {
            result |= ma.MA_SOUND_FLAG_STREAM;
        }
        if (self.predecode) {
            result |= ma.MA_SOUND_FLAG_DECODE;
        }
        if (!self.pitch) {
            result |= ma.MA_SOUND_FLAG_NO_PITCH;
        }
        return result;
    }
};

pub const SampleFormat = enum(ma.ma_format) {
    unknown = ma.ma_format_unknown,
    u8 = ma.ma_format_u8,
    s16 = ma.ma_format_s16,
    s24 = ma.ma_format_s24,
    s32 = ma.ma_format_s32,
    f32 = ma.ma_format_f32,
    count = ma.ma_format_count,
};

pub const SoundDataFormat = struct {
    format: SampleFormat,
    channels: u32,
    sample_rate: u32, // sample rate per channel
};

pub const Sound = struct {
    engine: *Engine,
    ma_sound: *ma.ma_sound,
    volume_before_mute: f32 = 5.0,

    /// init
    ///
    /// ```
    /// var sound = try Sound.init(allocator, "1.mp3", .{});
    /// defer sound.deinit();
    /// ```
    ///
    pub fn init(engine: *Engine, file_path: [*c]const u8, flags: SoundFlags) !Sound {

        // allocate ma_sound
        //
        const ma_sound = try engine.allocator.create(ma.ma_sound);
        errdefer engine.allocator.destroy(ma_sound);

        // init ma_sound
        //
        if (ma.ma_sound_init_from_file(engine.ma_engine, file_path, flags.toMASoundFlags(), null, null, ma_sound) != ma.MA_SUCCESS) {
            return error.MASoundInitFile;
        }
        errdefer ma.ma_sound_uninit(ma_sound);

        return Sound{
            .ma_sound = ma_sound,
            .engine = engine,
        };
    }

    /// deinit
    ///
    /// ```
    /// var sound = try Sound.init(allocator, "1.mp3", .{});
    /// defer sound.deinit();
    /// ```
    ///
    pub fn deinit(self: *Sound) void {
        log.debug("deinit sound", .{});
        ma.ma_sound_uninit(self.ma_sound);
        self.engine.allocator.destroy(self.ma_sound);
        self.* = undefined;
    }

    /// start playing
    ///
    /// ```
    /// if(!sound.playing()) {
    ///     try sound.start();
    /// }
    /// ```
    ///
    pub fn start(self: Sound) !void {
        if (ma.ma_sound_start(self.ma_sound) != ma.MA_SUCCESS) {
            return error.MASoundStart;
        }
    }

    /// stop playing
    ///
    /// ```
    /// if(sound.playing()) {
    ///     try sound.stop();
    /// }
    /// ```
    ///
    pub fn stop(self: Sound) !void {
        if (ma.ma_sound_stop(self.ma_sound) != ma.MA_SUCCESS) {
            return error.MASoundStop;
        }
    }

    /// check if end of sound
    ///
    /// ```
    /// if(sound.isEnd()) {
    ///     ...
    /// }
    /// ```
    ///
    pub fn isEnd(self: Sound) bool {
        return ma.ma_sound_at_end(self.ma_sound) != 0;
    }

    /// check if is playing
    ///
    /// ```
    /// if(sound.isPlaying()) {
    ///     ...
    /// }
    /// ```
    ///
    pub fn isPlaying(self: Sound) bool {
        return ma.ma_sound_is_playing(self.ma_sound) != 0;
    }

    /// pause/resume
    ///
    /// ```
    /// if(sound.playing()) {
    ///     try sound.pauseOrResume(); // => pause
    /// } else {
    ///     try sound.pauseOrResume(); // => resume
    /// }
    /// ```
    ////
    pub fn pauseOrResume(self: Sound) !void {
        if (self.isPlaying()) {
            log.info("PAUSE", .{});
            try self.stop();
        } else {
            log.info("RESUME", .{});
            try self.start();
        }
    }

    /// get volume [0.0, 1.0]
    ///
    /// ```
    /// const volume = sound.getVolume();
    /// ```
    ///
    pub fn getVolume(self: Sound) f32 {
        return ma.ma_sound_get_volume(self.ma_sound);
    }

    /// set volume [0.0, 1.0]
    ///
    /// ```
    /// sound.setVolume(1.0);
    /// ```
    ///
    pub fn setVolume(self: Sound, volume: f32) void {
        const safe_volume = @max(0.0, @min(volume, 1.0));
        ma.ma_sound_set_volume(self.ma_sound, safe_volume);
        log.info("VOLUME: {d}", .{safe_volume});
    }

    /// increment volume [-1.0, 1.0]
    ///
    /// ```
    /// sound.incVolume(0.2);
    /// sound.incVolume(-0.2);
    /// ```
    ///
    pub fn incVolume(self: Sound, delta: f32) void {
        const volume = self.getVolume() + delta;
        self.setVolume(volume);
    }

    /// check if is muted
    ///
    /// ```
    /// if (sound.isMuted()) {
    ///     ...
    /// }
    /// ```
    ///
    pub fn isMuted(self: Sound) bool {
        return self.getVolume() == 0;
    }

    /// toggle `mute`
    ///
    /// ```
    /// if(sound.muting()) {
    ///     sound.mute(); // => mute disabled
    /// } else {
    ///     sound.mute(); // => mute enabled
    /// }
    /// ```
    ///
    pub fn mute(self: *Sound) void {
        const volume = self.getVolume();

        if (volume == 0) {
            // unmount
            //
            self.setVolume(self.volume_before_mute);
        } else {
            // mute
            //
            self.volume_before_mute = volume;
            self.setVolume(0.0);
        }
    }

    /// check if is looping
    ///
    /// ```
    /// if(sound.looping()) {
    ///     ...
    /// }
    /// ```
    ///
    pub fn isLooping(self: Sound) bool {
        return ma.ma_sound_is_looping(self.ma_sound) != 0;
    }

    /// toggle `loop`
    ///
    /// ```
    /// if(sound.looping()) {
    ///     sound.loop(); // => loop disabled
    /// } else{
    ///     soudn.loop(); // => loop enabled
    /// }
    /// ```
    ///
    pub fn loop(self: Sound) void {
        if (self.isLooping()) {
            log.info("UNLOOP", .{});
            ma.ma_sound_set_looping(self.ma_sound, 0);
        } else {
            log.info("LOOP", .{});
            ma.ma_sound_set_looping(self.ma_sound, 1);
        }
    }

    /// set loop point in second
    ///
    /// ```
    /// sound.setLoopPointInSecond(100, 200);
    /// ```
    ///
    pub fn setLoopPointInSecond(self: Sound, begin: u32, end: u32) !void {
        log.info("LOOP_POINT: {d}-{d}s", .{ begin, end });
        const sample_rate: u64 = @intCast(self.engine.getSampleRate());
        const begin_frame = @as(u64, @intCast(begin)) * sample_rate;
        const end_frame = @as(u64, @intCast(end)) * sample_rate;
        try self.setLoopPointInFrame(begin_frame, end_frame);
    }

    /// set loop point in frames
    ///
    /// ```
    /// try sound.setLoopPoint(100, 200);
    /// ```
    ///
    pub fn setLoopPointInFrame(self: Sound, begin: u64, end: u64) !void {
        log.info("LOOP_POINT_FRAME: {d}-{d}", .{ begin, end });
        const data_source = ma.ma_sound_get_data_source(self.ma_sound) orelse return error.MASoundGetDataSource;
        if (ma.ma_data_source_set_loop_point_in_pcm_frames(data_source, begin, end) != ma.MA_SUCCESS) {
            return error.MADataSouceSetLoopPointInPcmFrames;
        }
    }

    /// goto `nth second`
    ///
    /// ```
    /// try sound.gotoNthSecond(5);
    /// ```
    ///
    pub fn gotoNthSecond(self: Sound, nth: u32) !void {
        log.info("GOTO: {d}s", .{nth});
        const nth_frame: u64 = @as(u64, @intCast(nth)) * @as(u64, @intCast(self.engine.getSampleRate()));
        try self.gotoNthFrame(nth_frame);
    }

    /// goto `nth frame`
    ///
    /// ```
    /// try sound.gotoNthFrame(1000);
    /// ```
    ///
    pub fn gotoNthFrame(self: Sound, nth: u64) !void {
        log.info("GOTO_FRAME: {d}", .{nth});
        if (ma.ma_sound_seek_to_pcm_frame(self.ma_sound, nth) != ma.MA_SUCCESS) {
            return error.MASoundSeekToPcmFrame;
        }
    }

    /// go to next seconds if `offset` is positive
    /// go to prev seconds if `offset` is negative
    ///
    /// ```
    /// try sound.gotoNextNthSecond(-10);
    /// try sound.gotoNextNthSecond(10);
    /// ```
    ///
    pub fn gotoNextNthSecond(self: Sound, offset: i64) !void {
        log.info("GOTO_NEXT: {d}s", .{offset});
        try self.gotoNextNthFrame(offset * @as(i64, @intCast(self.engine.getSampleRate())));
    }

    /// go to next frames if `offset` is positive
    /// go to prev frames if `offset` is negative
    ///
    /// ```
    /// try sound.gotoNextNthFrame(-10);
    /// try sound.gotoNextNthFrame(10);
    /// ```
    ///
    pub fn gotoNextNthFrame(self: Sound, offset: i64) !void {
        const nth_frame = try self.getNthFrame();
        const nth_frame_to_go = if (offset >= 0)
            nth_frame +| @as(u64, @intCast(offset))
        else
            nth_frame -| @as(u64, @intCast(@abs(offset)));
        try self.gotoNthFrame(nth_frame_to_go);
    }

    /// get nth frame
    ///
    /// ```
    /// const nth_frame = try sound.getNthFrame();
    /// ```
    ///
    pub fn getNthFrame(self: Sound) !u64 {
        var result: u64 = undefined;
        if (ma.ma_sound_get_cursor_in_pcm_frames(self.ma_sound, &result) != ma.MA_SUCCESS) {
            return error.MASoundGetCursorInPcmFrames;
        }
        return result;
    }

    /// get nth milliseconds
    ///
    /// ```
    /// const nth_millis = try sound.getNthMillis();
    /// ```
    ///
    pub fn getNthMillis(self: Sound) !u32 {
        var result: f32 = undefined;
        if (ma.ma_sound_get_cursor_in_seconds(self.ma_sound, &result) != ma.MA_SUCCESS) {
            return error.MASoundGetCursorInSeconds;
        }
        return @intFromFloat(result * 1000);
    }

    /// get total frames
    ///
    /// ```
    /// const total_frames = try sound.getTotalFrames();
    /// ```
    ///
    pub fn getTotalFrames(self: Sound) !u64 {
        var result: u64 = undefined;
        if (ma.ma_sound_get_length_in_pcm_frames(self.ma_sound, &result) != ma.MA_SUCCESS) {
            return error.MASoundGetLengthInPcmFrames;
        }
        return result;
    }

    /// get total milliseconds
    ///
    /// ```
    /// const total_millis = try sound.getTotalMillis();
    /// ```
    ///
    pub fn getTotalMillis(self: Sound) !u32 {
        var result: f32 = undefined;
        if (ma.ma_sound_get_length_in_seconds(self.ma_sound, &result) != ma.MA_SUCCESS) {
            return error.MASoundGetLengthInSeconds;
        }
        return @intFromFloat(result * 1000);
    }

    /// get `SoundDataFormat`
    ///
    /// ```
    /// const data_format = try sound.getDataFormat();
    /// ```
    ///
    pub fn getDataFormat(self: Sound) !SoundDataFormat {
        var result: SoundDataFormat = undefined;
        if (ma.ma_sound_get_data_format(self.ma_sound, @ptrCast(&result.format), &result.channels, &result.sample_rate, null, 0) != ma.MA_SUCCESS) {
            return error.MASoundGetDataFormat;
        }
        return result;
    }

    /// get pitch [0.0, ?] (1.0 by default)
    ///
    /// ```
    /// const pitch = sound.getPitch();
    ///```
    ///
    pub fn getPitch(self: Sound) f32 {
        return ma.ma_sound_get_pitch(self.ma_sound);
    }

    /// set pitch [0.0, ?] (1.0 by default)
    ///
    /// ```
    /// sound.setPitch(1.0);
    /// ```
    ///
    pub fn setPitch(self: Sound, pitch: f32) void {
        log.info("PITCH: {d}", .{pitch});
        ma.ma_sound_set_pitch(self.ma_sound, pitch);
    }

    /// get pan [-1.0, 1.0] (0.0 by default)
    ///
    /// ```
    /// const pan = sound.getPan();
    /// ```
    ///
    pub fn getPan(self: Sound) f32 {
        return ma.ma_sound_get_pan(self.ma_sound);
    }

    /// set pan [-1.0, 1.0] (0.0 by default)
    ///
    /// ```
    /// sound.setPan(1.0);
    /// ```
    ///
    pub fn setPan(self: Sound, pan: f32) void {
        log.info("PAN: {d}", .{pan});
        ma.ma_sound_set_pan(self.ma_sound, pan);
    }
};

pub const DeviceDataFormat = struct {
    format: SampleFormat,
    channels: u32,
    sample_rate: u32,
    flags: u32,
};

pub const DeviceInfo = struct {
    id: ma.ma_device_id,
    name: []const u8,
    is_default: bool,
    native_data_formats: []DeviceDataFormat,

    // pub fn idStr(self: DeviceInfo, allocator: Allocator) ![]const u8 {
    //     // wasapi: [64]ma_wchar_win32,
    //     // dsound: [16]ma_uint8,
    //     // winmm: ma_uint32,
    //     // alsa: [256]u8,
    //     // pulse: [256]u8,
    //     // jack: c_int,
    //     // coreaudio: [256]u8,
    //     // sndio: [256]u8,
    //     // audio4: [256]u8,
    //     // oss: [64]u8,
    //     // aaudio: ma_int32,
    //     // opensl: ma_uint32,
    //     // webaudio: [32]u8,
    //     // custom: union_unnamed_58,
    //     // nullbackend: c_int,
    //     switch (self.id) {
    //         .wasapi => |v| fmt.allocPrint(allocator, "{d}", .{v}),
    //         .dsound => |v| fmt.allocPrint(allocator, "{s}", .{&v}),
    //         .winmm => |v| fmt.allocPrint(allocator, "{d}", .{v}),
    //         .alsa => |v| fmt.allocPrint(allocator, "{s}", .{&v}),
    //         .pulse => |v| fmt.allocPrint(allocator, "{s}", .{&v}),
    //         .jack => |v| fmt.allocPrint(allocator, "{d}", .{v}),
    //         .coreaudio => |v| fmt.allocPrint(allocator, "{s}", .{&v}),
    //         .sndio => |v| fmt.allocPrint(allocator, "{s}", .{&v}),
    //         .audio4 => |v| fmt.allocPrint(allocator, "{s}", .{&v}),
    //         .oss => |v| fmt.allocPrint(allocator, "{s}", .{&v}),
    //         .aaudio => |v| fmt.allocPrint(allocator, "{d}", .{v}),
    //         .opensl => |v| fmt.allocPrint(allocator, "{d}", .{v}),
    //         .webaudio => |v| fmt.allocPrint(allocator, "{s}", .{&v}),
    //         .custom => |v| fmt.allocPrint(allocator, "{any}", .{v}),
    //         .nullbackend => |v| fmt.allocPrint(allocator, "{d}", .{v}),
    //     }
    // }

    fn copyFrom(self: *DeviceInfo, arena_allocator: Allocator, dev: ma.ma_device_info) !void {
        const name = blk: {
            const eos_index = mem.indexOfSentinel(u8, 0, @ptrCast(&dev.name));
            if (eos_index <= 0) break :blk "";
            const _result = try arena_allocator.alloc(u8, eos_index);
            errdefer arena_allocator.free(_result);
            @memcpy(_result, dev.name[0..eos_index]);
            break :blk _result;
        };
        errdefer arena_allocator.free(name);

        const native_data_formats = blk: {
            log.debug("nativeFormatCount: {d}", .{dev.nativeDataFormatCount});
            var _result = try ArrayList(DeviceDataFormat).initCapacity(arena_allocator, dev.nativeDataFormatCount);
            errdefer _result.deinit();
            if (dev.nativeDataFormatCount > 0) {
                for (dev.nativeDataFormats[0..dev.nativeDataFormatCount]) |data_format| {
                    try _result.append(.{
                        .format = @enumFromInt(data_format.format),
                        .channels = data_format.channels,
                        .sample_rate = data_format.sampleRate,
                        .flags = data_format.flags,
                    });
                }
            }
            break :blk _result;
        };
        errdefer native_data_formats.deinit();
        self.* = .{
            .id = dev.id,
            .name = name,
            .is_default = (dev.isDefault == 1),
            .native_data_formats = native_data_formats.items,
        };
    }
};

pub const DeviceInfoList = struct {
    arena: *ArenaAllocator,

    /// playback device info list
    playbacks: ArrayList(*DeviceInfo),

    /// capture device info list
    captures: ArrayList(*DeviceInfo),

    pub fn init(allocator: Allocator, playbacks_cap: u32, captures_cap: u32) !DeviceInfoList {
        var result = DeviceInfoList{
            .arena = try allocator.create(ArenaAllocator),
            .playbacks = undefined,
            .captures = undefined,
        };
        errdefer allocator.destroy(result.arena);

        result.arena.* = ArenaAllocator.init(allocator);
        errdefer result.arena.deinit();

        result.playbacks = try ArrayList(*DeviceInfo).initCapacity(result.arena.allocator(), playbacks_cap);
        result.captures = try ArrayList(*DeviceInfo).initCapacity(result.arena.allocator(), captures_cap);

        return result;
    }

    pub fn deinit(self: *DeviceInfoList) void {
        const allocator = self.arena.child_allocator;
        self.arena.deinit();
        allocator.destroy(self.arena);
        self.* = undefined;
    }

    fn appendPlaybackDevice(self: *DeviceInfoList, dev: ma.ma_device_info) !void {
        const arena_allocator = self.arena.allocator();
        const device_info = try arena_allocator.create(DeviceInfo);
        try device_info.copyFrom(arena_allocator, dev);
        try self.playbacks.append(device_info);
    }

    fn appendCaptureDevice(self: *DeviceInfoList, dev: ma.ma_device_info) !void {
        const arena_allocator = self.arena.allocator();
        const device_info = try arena_allocator.create(DeviceInfo);
        try device_info.copyFrom(arena_allocator, dev);
        try self.captures.append(device_info);
    }
};

pub const Context = struct {
    allocator: Allocator,
    ma_context: *ma.ma_context,

    /// init Context
    ///
    /// ```
    /// var context = try Context.init(allocator);
    /// defer context.deinit();
    /// ```
    ///
    pub fn init(allocator: Allocator) !Context {
        const ma_context: *ma.ma_context = try allocator.create(ma.ma_context);
        errdefer allocator.destroy(ma_context);

        if (ma.ma_context_init(null, 0, null, ma_context) != ma.MA_SUCCESS) {
            return error.MAContextInit;
        }

        return .{
            .allocator = allocator,
            .ma_context = ma_context,
        };
    }

    /// deinit Context
    ///
    /// ```
    /// var context = try Context.init(allocator);
    /// defer context.deinit();
    /// ```
    ///
    pub fn deinit(self: *Context) void {
        if (ma.ma_context_uninit(self.ma_context) != ma.MA_SUCCESS) {
            @panic("Failed to call ma_context_uninit");
        }
        self.allocator.destroy(self.ma_context);
        self.* = undefined;
    }

    /// get device info list
    ///
    /// ```
    /// var device_info_list = try context.getDeviceInfoList();
    /// defer device_info_list.deinit();
    ///
    /// for(device_info_list.playbacks.items) |device_info| {
    ///     ...
    /// }
    ///
    /// for(device_info_list.captures.items) |device_info| {
    ///     ...
    /// }
    /// ```
    ///
    pub fn getDeviceInfoList(self: Context) !DeviceInfoList {
        // get devices
        //
        var playback_devices: ?[*]ma.ma_device_info = undefined;
        var playback_devices_count: u32 = undefined;
        var capture_devices: ?[*]ma.ma_device_info = undefined;
        var capture_devices_count: u32 = undefined;
        if (ma.ma_context_get_devices(self.ma_context, @ptrCast(&playback_devices), &playback_devices_count, @ptrCast(&capture_devices), &capture_devices_count) != ma.MA_SUCCESS) {
            return error.MAContextGetDevices;
        }

        // init result
        //
        var result = try DeviceInfoList.init(self.allocator, playback_devices_count, capture_devices_count);
        errdefer result.deinit();

        // append playback device info into result
        //
        if (playback_devices) |devs| {
            for (devs[0..playback_devices_count]) |dev| {
                try result.appendPlaybackDevice(dev);
            }
        }

        // append capture device info into result
        //
        if (capture_devices) |devs| {
            for (devs[0..capture_devices_count]) |dev| {
                try result.appendCaptureDevice(dev);
            }
        }

        return result;
    }
};

test "get devices" {
    std.testing.log_level = std.log.Level.info;
    var context = try Context.init(std.testing.allocator);
    defer context.deinit();
    var device_info_list = try context.getDeviceInfoList(10);
    defer device_info_list.deinit();

    for (device_info_list.playbacks.items) |dev| {
        log.info(
            \\
            \\ PLAYBACK
            \\     id                  : {any}
            \\     name                : {s}
            \\     is_default          : {any}
            \\     native_data_formats : {any}
        , .{ dev.id, dev.name, dev.is_default, dev.native_data_formats });
    }

    for (device_info_list.captures.items) |dev| {
        log.info(
            \\
            \\ CAPTURE
            \\     id                  : {any}
            \\     name                : {s}
            \\     is_default          : {any}
            \\     native_data_formats : {any}
        , .{ dev.id, dev.name, dev.is_default, dev.native_data_formats });
    }
}
