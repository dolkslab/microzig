const std = @import("std");
const microzig = @import("microzig/build-internals");

const Self = @This();

chips: struct {
    //lpc54616: *const microzig.Target,
    lpc54628: *const microzig.Target,
},

// boards: struct {
//     mbed: struct {
//         lpc1768: *const microzig.Target,
//     },
// },

pub fn init(dep: *std.Build.Dependency) Self {
    const b = dep.builder;
    const powerapi_paths = b.allocator.create([1]std.Build.LazyPath) catch @panic("out of memory");
    powerapi_paths[0] = b.path("src/clibs/libpower_hardabi.a");

    const chip_lpc54628: microzig.Target = .{
        .dep = dep,
        .preferred_binary_format = .elf,
        .chip = .{
            .name = "LPC54628",
            .cpu = .{
                .cpu_arch = .thumb,
                .cpu_model = .{ .explicit = &std.Target.arm.cpu.cortex_m4 },
                .cpu_features_add = std.Target.arm.featureSet(&.{.vfp4d16sp}),
                .os_tag = .freestanding,
                .abi = .eabihf,
            },
            // not Downloaded from http://ds.arm.com/media/resources/db/chip/nxp/lpc1768/LPC176x5x.svd
            .register_definition = .{ .svd = b.path("src/chips/LPC54628.svd") },
            .memory_regions = &.{
                .{ .offset = 0x00000000, .length = 512 * 1024, .kind = .flash },
                .{ .offset = 0x20000000, .length = 160 * 1024, .kind = .ram },
                .{ .offset = 0x04000000, .length = 32 * 1024, .kind = .ram }, // sramx
            },
        },
        .hal = .{
            .root_source_file = b.path("src/hal.zig"),
            .static_clibs = powerapi_paths,
        },
        .patch_elf = lpc_patch_elf,
    };

    return .{
        .chips = .{
            .lpc54628 = chip_lpc54628.derive(.{}),
        },
        // .boards = .{
        //     .mbed = .{
        //         .lpc1768 = chip_lpc176x5x.derive(.{
        //             .board = .{
        //                 .name = "mbed LPC1768",
        //                 .url = "https://os.mbed.com/platforms/mbed-LPC1768/",
        //                 .root_source_file = b.path("src/boards/mbed_LPC1768.zig"),
        //             },
        //         }),
        //     },
        // },
    };
}

pub fn build(b: *std.Build) void {
    const lpc_patch_elf_exe = b.addExecutable(.{
        .name = "lpc-patchelf",
        .root_source_file = b.path("../tools/patchelf.zig"),
        .target = b.host,
    });
    b.installArtifact(lpc_patch_elf_exe);
}

/// Patch an ELF file to add a checksum over the first 8 words so the
/// cpu will properly boot.
fn lpc_patch_elf(dep: *std.Build.Dependency, input: std.Build.LazyPath) std.Build.LazyPath {
    const patch_elf_exe = dep.artifact("lpc-patchelf");
    const run = dep.builder.addRunArtifact(patch_elf_exe);
    run.addFileArg(input);
    return run.addOutputFileArg("output.elf");
}
