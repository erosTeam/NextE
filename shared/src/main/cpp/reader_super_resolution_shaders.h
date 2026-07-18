#pragma once

// Vulkan preprocessing and postprocessing adapted from waifu2x-ncnn-vulkan and
// Real-ESRGAN-ncnn-vulkan. Both upstream projects are distributed under the MIT License.
//
// Copyright (c) 2019 nihui
// Copyright (c) 2021 Xintao Wang
//
// Permission is hereby granted, free of charge, to any person obtaining a copy of this software and
// associated documentation files (the "Software"), to deal in the Software without restriction,
// including without limitation the rights to use, copy, modify, merge, publish, distribute,
// sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all copies or
// substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT
// NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
// NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM,
// DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT
// OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

static const char kReaderSuperResolutionPreprocessShader[] = R"glsl(
#version 450

#if NCNN_fp16_storage
#extension GL_EXT_shader_16bit_storage: require
#define sfp float16_t
#else
#define sfp float
#endif

#if NCNN_int8_storage
#extension GL_EXT_shader_8bit_storage: require
#endif

layout (constant_id = 0) const int bgr = 0;
layout (constant_id = 1) const int reflect_padding = 0;

layout (binding = 0) readonly buffer source_blob { uint8_t source_blob_data[]; };
layout (binding = 1) writeonly buffer input_blob { sfp input_blob_data[]; };

layout (push_constant) uniform parameter
{
    int source_width;
    int source_height;
    int source_stride;
    int input_width;
    int input_height;
    int input_cstep;
    int pad_top;
    int pad_left;
    int crop_x;
    int crop_y;
    int source_channels;
} p;

void main()
{
    int gx = int(gl_GlobalInvocationID.x);
    int gy = int(gl_GlobalInvocationID.y);
    int gz = int(gl_GlobalInvocationID.z);

    if (gx >= p.input_width || gy >= p.input_height || gz >= 3)
        return;

    int x = gx + p.crop_x - p.pad_left;
    int y = gy + p.crop_y - p.pad_top;
    if (reflect_padding == 1)
    {
        x = abs(x);
        y = abs(y);
        x = (p.source_width - 1) - abs(x - (p.source_width - 1));
        y = (p.source_height - 1) - abs(y - (p.source_height - 1));
    }
    else
    {
        x = clamp(x, 0, p.source_width - 1);
        y = clamp(y, 0, p.source_height - 1);
    }

    int channel = bgr == 1 ? 2 - gz : gz;
    int source_offset = y * p.source_stride + x * p.source_channels + channel;
    float value = float(uint(source_blob_data[source_offset])) * (1.f / 255.f);
    input_blob_data[gz * p.input_cstep + gy * p.input_width + gx] = sfp(value);
}
)glsl";

static const char kReaderSuperResolutionPostprocessShader[] = R"glsl(
#version 450

#if NCNN_fp16_storage
#extension GL_EXT_shader_16bit_storage: require
#define sfp float16_t
#else
#define sfp float
#endif

#if NCNN_int8_storage
#extension GL_EXT_shader_8bit_storage: require
#endif

layout (constant_id = 0) const int bgr = 0;
layout (constant_id = 1) const int reflect_padding = 0;

layout (binding = 0) readonly buffer output_tile_blob { sfp output_tile_blob_data[]; };
layout (binding = 1) writeonly buffer output_blob { uint8_t output_blob_data[]; };

layout (push_constant) uniform parameter
{
    int tile_width;
    int tile_height;
    int tile_cstep;
    int output_width;
    int output_height;
    int offset_x;
    int offset_y;
    int write_width;
    int write_height;
    int crop_x;
    int crop_y;
    int output_channels;
} p;

void main()
{
    int gx = int(gl_GlobalInvocationID.x);
    int gy = int(gl_GlobalInvocationID.y);
    int gz = int(gl_GlobalInvocationID.z);

    if (gx >= p.write_width || gy >= p.write_height || gz >= p.output_channels)
        return;

    float value = 255.f;
    if (gz < 3)
    {
        int channel = bgr == 1 ? 2 - gz : gz;
        int tile_offset = channel * p.tile_cstep +
            (gy + p.crop_y) * p.tile_width + gx + p.crop_x;
        value = float(output_tile_blob_data[tile_offset]) * 255.f + 0.5f;
    }

    int output_offset = ((gy + p.offset_y) * p.output_width + gx + p.offset_x) *
        p.output_channels + gz;
    output_blob_data[output_offset] = uint8_t(clamp(uint(floor(value)), 0, 255));
}
)glsl";
