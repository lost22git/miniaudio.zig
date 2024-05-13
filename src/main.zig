const std = @import("std");
const builtin = @import("builtin");
const log = std.log;

const Allocator = std.mem.Allocator;

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
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const allocator = gpa.allocator();

    // read file path from commandline args
    //
    var args = try std.process.argsWithAllocator(allocator);
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
    var sound = try Sound.init(&engine, sound_file_path, .{ .streaming = true, .predecode = false });
    defer sound.deinit();

    // sound start
    //
    try sound.start();

    // wait for instruction
    //
    while (true) {
        try std.io.getStdOut().writer().print("Press instruction: ", .{});
        var buffer: [100]u8 = undefined;
        const ins = try readline(&buffer);
        var ins_tks = std.mem.tokenizeAny(u8, ins, " \t");
        if (ins_tks.next()) |tk| {
            switch (tk[0]) {
                'q' => break,
                'p' => try sound.pauseOrResume(),
                'm' => sound.mute(),
                '0' => sound.incVolume(5.0),
                '9' => sound.incVolume(-5.0),
                'g' => {
                    const nth_second = ins_tks.next() orelse continue;
                    try sound.gotoNthSecond(try std.fmt.parseInt(u32, nth_second, 10));
                },
                // 'l' => // set loop spot,
                'L' => sound.loop(),
                'i' => printSoundInfo(sound),
                else => continue,
            }
        } else {
            continue;
        }
    }
}

fn printSoundInfo(sound: Sound) void {
    const frame_rate = sound.engine.getFrameRate();
    log.info("FRAME_RATE : {d}", .{frame_rate});

    const nth_frame: u64 = sound.getNthFrame() catch 0;
    const total_frames: u64 = sound.getTotalFrames() catch 0;
    log.info("FRAME      : {d}/{d}", .{ nth_frame, total_frames });

    const nth_millis: u64 = sound.getNthMillis() catch 0;
    const total_millis: u64 = sound.getTotalMillis() catch 0;
    log.info("TIME(ms)   : {d}/{d}", .{ nth_millis, total_millis });

    const volume = sound.getVolume();
    log.info("VOLUME     : {d}", .{volume});
}

fn readline(buf: []u8) ![]const u8 {
    return trimBlanks(try std.io.getStdIn().reader().readUntilDelimiter(buf, '\n'));
}

fn trimBlanks(buf: []const u8) []const u8 {
    return std.mem.trim(u8, buf, " \t\r\n");
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

    /// get frame rate
    ///
    /// ```
    /// const frame_rate = engine.getFrameRate();
    /// ```
    ///
    pub fn getFrameRate(self: Engine) u32 {
        return ma.ma_engine_get_sample_rate(self.ma_engine);
    }
};

pub const SoundFlags = struct {
    ///
    streaming: bool = true,

    /// 预先解码，解码完再开始播放
    predecode: bool = false,

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
        return result;
    }
};

pub const Sound = struct {
    engine: *Engine,
    ma_sound: *ma.ma_sound,
    volume: f32,
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

        // get volume
        //
        const volume = ma.ma_sound_get_volume(ma_sound);

        return Sound{
            .ma_sound = ma_sound,
            .engine = engine,
            .volume = volume,
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

    /// check if playing
    ///
    /// ```
    /// if(sound.playing()) {
    ///     ...
    /// }
    /// ```
    ///
    pub fn playing(self: Sound) bool {
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
        if (self.playing()) {
            log.info("PAUSE", .{});
            try self.stop();
        } else {
            log.info("RESUME", .{});
            try self.start();
        }
    }

    /// get volume
    ///
    /// ```
    /// const volume = sound.getVolume();
    /// ```
    ///
    pub fn getVolume(self: Sound) f32 {
        return ma.ma_sound_get_volume(self.ma_sound);
    }

    /// check `mute` if enabled
    ///
    /// ```
    /// if (sound.muting()) {
    ///     ...
    /// }
    /// ```
    ///
    pub fn muting(self: Sound) bool {
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

    /// set volume
    ///
    /// ```
    /// sound.setVolume(5.0);
    /// ```
    ///
    pub fn setVolume(self: *Sound, volume: f32) void {
        const safe_volume = @max(0.0, @min(volume, 50.0));
        ma.ma_sound_set_volume(self.ma_sound, safe_volume);
        log.info("VOLUME: {d}", .{safe_volume});
    }

    /// increment volume
    ///
    /// ```
    /// sound.incVolume(5.0);
    /// sound.incVolume(-5.0);
    /// ```
    ///
    pub fn incVolume(self: *Sound, delta: f32) void {
        const volume = self.getVolume() + delta;
        self.setVolume(volume);
    }

    /// check `looping` enabled
    ///
    /// ```
    /// if(sound.looping()) {
    ///     ...
    /// }
    /// ```
    ///
    pub fn looping(self: Sound) bool {
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
        if (self.looping()) {
            log.info("UNLOOP", .{});
            ma.ma_sound_set_looping(self.ma_sound, 0);
        } else {
            log.info("LOOP", .{});
            ma.ma_sound_set_looping(self.ma_sound, 1);
        }
    }

    /// goto `nth second` to play
    ///
    /// ```
    /// try sound.gotoNthSecond(5);
    /// ```
    ///
    pub fn gotoNthSecond(self: Sound, nth: u32) !void {
        log.info("GOTO: {d}s", .{nth});
        try self.stop();
        ma.ma_sound_set_start_time_in_milliseconds(self.ma_sound, nth * 1000);
        try self.start();
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
};
