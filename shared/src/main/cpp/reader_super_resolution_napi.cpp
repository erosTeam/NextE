#include <napi/native_api.h>

#include <algorithm>
#include <chrono>
#include <cmath>
#include <condition_variable>
#include <cstddef>
#include <cstdint>
#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <unordered_set>
#include <vector>

#include <command.h>
#include <gpu.h>
#include <hilog/log.h>
#include <mat.h>
#include <net.h>
#include <pipeline.h>
#include <platform.h>

#include "reader_super_resolution_shaders.h"

namespace {

constexpr const char *kModuleName = "nexte_super_resolution";
constexpr int kScale = 2;

enum class ModelKind : int {
    Waifu2x = 0,
    RealEsrgan = 1,
    Luminance = 2,
};

enum class BackendPreference : int {
    Automatic = 0,
    Vulkan = 1,
    Cpu = 2,
};

struct UpscaleTask {
    napi_async_work work = nullptr;
    napi_deferred deferred = nullptr;
    std::vector<uint8_t> input;
    std::vector<uint8_t> output;
    int width = 0;
    int height = 0;
    int stride = 0;
    int tileSize = 142;
    int prepadding = 7;
    int threads = 2;
    ModelKind modelKind = ModelKind::Waifu2x;
    BackendPreference backendPreference = BackendPreference::Automatic;
    std::string paramPath;
    std::string modelPath;
    std::string inputName;
    std::string outputName;
    std::string backend;
    std::string error;
    uint64_t requestId = 0;
    bool cancelled = false;
    int64_t modelLoadMs = 0;
    int64_t inferenceMs = 0;
};

std::once_flag gGpuInitFlag;
int gGpuInitResult = -1;
int gGpuCount = 0;
uint32_t gGpuHeapBudget = 0;
std::string gGpuName;
std::mutex gInferenceMutex;
std::mutex gRequestStateMutex;
std::unordered_set<uint64_t> gInactiveRequests;
std::mutex gInteractionMutex;
std::condition_variable gInteractionCondition;
bool gInteractionPaused = false;
std::unique_ptr<ncnn::Net> gCachedNet;
std::unique_ptr<ncnn::Pipeline> gCachedPreprocessPipeline;
std::unique_ptr<ncnn::Pipeline> gCachedPostprocessPipeline;
std::string gCachedNetKey;

using SteadyClock = std::chrono::steady_clock;

int64_t ElapsedMilliseconds(const SteadyClock::time_point &startedAt)
{
    return std::chrono::duration_cast<std::chrono::milliseconds>(SteadyClock::now() - startedAt).count();
}

void ResetCachedRuntime()
{
    gCachedPreprocessPipeline.reset();
    gCachedPostprocessPipeline.reset();
    gCachedNet.reset();
    gCachedNetKey.clear();
}

void InitializeGpuRuntime()
{
    std::call_once(gGpuInitFlag, []() {
        gGpuInitResult = ncnn::create_gpu_instance();
        if (gGpuInitResult == 0) {
            gGpuCount = ncnn::get_gpu_count();
            if (gGpuCount > 0) {
                const char *name = ncnn::get_gpu_info(0).device_name();
                if (name != nullptr) {
                    gGpuName = name;
                }
                const ncnn::VulkanDevice *device = ncnn::get_gpu_device(0);
                if (device != nullptr) {
                    gGpuHeapBudget = device->get_heap_budget();
                }
            }
        }
        OH_LOG_Print(
            LOG_APP,
            gGpuCount > 0 ? LOG_INFO : LOG_WARN,
            0x0,
            "NextESuperResolution",
            "ncnn Vulkan init result=%{public}d gpuCount=%{public}d gpu=%{public}s heapBudgetMiB=%{public}u",
            gGpuInitResult,
            gGpuCount,
            gGpuName.c_str(),
            gGpuHeapBudget);
    });
}

bool VulkanAvailable()
{
    InitializeGpuRuntime();
    return gGpuInitResult == 0 && gGpuCount > 0;
}

std::string GetString(napi_env env, napi_value value)
{
    size_t length = 0;
    if (napi_get_value_string_utf8(env, value, nullptr, 0, &length) != napi_ok) {
        return {};
    }
    std::string result(length + 1, '\0');
    size_t copied = 0;
    if (napi_get_value_string_utf8(env, value, result.data(), result.size(), &copied) != napi_ok) {
        return {};
    }
    result.resize(copied);
    return result;
}

bool GetBytes(napi_env env, napi_value value, std::vector<uint8_t> &bytes)
{
    bool typedArray = false;
    if (napi_is_typedarray(env, value, &typedArray) == napi_ok && typedArray) {
        napi_typedarray_type type = napi_uint8_array;
        size_t length = 0;
        void *data = nullptr;
        napi_value arrayBuffer = nullptr;
        size_t byteOffset = 0;
        if (napi_get_typedarray_info(
                env, value, &type, &length, &data, &arrayBuffer, &byteOffset) != napi_ok) {
            return false;
        }
        if (type != napi_uint8_array && type != napi_uint8_clamped_array) {
            return false;
        }
        const auto *begin = static_cast<const uint8_t *>(data);
        bytes.assign(begin, begin + length);
        return true;
    }

    bool arrayBuffer = false;
    if (napi_is_arraybuffer(env, value, &arrayBuffer) != napi_ok || !arrayBuffer) {
        return false;
    }
    void *data = nullptr;
    size_t length = 0;
    if (napi_get_arraybuffer_info(env, value, &data, &length) != napi_ok) {
        return false;
    }
    const auto *begin = static_cast<const uint8_t *>(data);
    bytes.assign(begin, begin + length);
    return true;
}

bool GetInt(napi_env env, napi_value value, int &result)
{
    int32_t number = 0;
    if (napi_get_value_int32(env, value, &number) != napi_ok) {
        return false;
    }
    result = number;
    return true;
}

bool GetInt64(napi_env env, napi_value value, int64_t &result)
{
    return napi_get_value_int64(env, value, &result) == napi_ok;
}

void SetRequestActiveState(uint64_t requestId, bool active)
{
    if (requestId == 0) {
        return;
    }
    {
        std::lock_guard<std::mutex> lock(gRequestStateMutex);
        if (active) {
            gInactiveRequests.erase(requestId);
        } else {
            gInactiveRequests.insert(requestId);
        }
    }
    if (!active) {
        gInteractionCondition.notify_all();
    }
}

bool EnsureRequestActive(UpscaleTask &task)
{
    if (task.requestId == 0) {
        return true;
    }
    std::lock_guard<std::mutex> lock(gRequestStateMutex);
    if (gInactiveRequests.find(task.requestId) == gInactiveRequests.end()) {
        return true;
    }
    task.cancelled = true;
    task.error = "super-resolution request superseded";
    return false;
}

void SetInteractionPausedState(bool paused)
{
    {
        std::lock_guard<std::mutex> lock(gInteractionMutex);
        gInteractionPaused = paused;
    }
    if (!paused) {
        gInteractionCondition.notify_all();
    }
    OH_LOG_Print(
        LOG_APP,
        LOG_INFO,
        0x0,
        "NextESuperResolution",
        "foreground interaction pause=%{public}d",
        paused ? 1 : 0);
}

bool WaitUntilInferenceAllowed(UpscaleTask &task)
{
    while (true) {
        {
            std::unique_lock<std::mutex> lock(gInteractionMutex);
            if (!gInteractionPaused) {
                break;
            }
            gInteractionCondition.wait_for(lock, std::chrono::milliseconds(16));
        }
        if (!EnsureRequestActive(task)) {
            return false;
        }
    }
    return EnsureRequestActive(task);
}

uint8_t ToByte(float value)
{
    const float scaled = value * 255.0f + 0.5f;
    return static_cast<uint8_t>(std::clamp(scaled, 0.0f, 255.0f));
}

bool ValidateTask(UpscaleTask &task)
{
    if (task.width <= 0 || task.height <= 0 || task.stride < task.width * 4) {
        task.error = "invalid RGBA dimensions or stride";
        return false;
    }
    const size_t requiredInput = static_cast<size_t>(task.stride) * task.height;
    if (task.input.size() < requiredInput) {
        task.error = "RGBA buffer is smaller than stride times height";
        return false;
    }
    if (task.tileSize < 32 || task.prepadding < 0 || task.threads < 1) {
        task.error = "invalid ncnn tile configuration";
        return false;
    }
    return true;
}

ncnn::Net *PrepareNet(UpscaleTask &task, bool useVulkan)
{
    const std::string key = task.paramPath + "|" + task.modelPath + "|" +
        (useVulkan ? "vulkan" : "cpu") + "|" + std::to_string(task.threads) + "|" +
        std::to_string(static_cast<int>(task.modelKind));
    if (gCachedNet != nullptr && gCachedNetKey == key) {
        task.modelLoadMs = 0;
        return gCachedNet.get();
    }

    const SteadyClock::time_point startedAt = SteadyClock::now();
    auto net = std::make_unique<ncnn::Net>();
    net->opt.num_threads = task.threads;
    net->opt.use_vulkan_compute = useVulkan;
    net->opt.use_fp16_packed = true;
    net->opt.use_fp16_storage = true;
    net->opt.use_fp16_arithmetic = true;
    net->opt.use_int8_storage = true;
    if (useVulkan) {
        net->set_vulkan_device(0);
    }
    if (net->load_param(task.paramPath.c_str()) != 0) {
        task.error = "failed to load ncnn param file";
        return nullptr;
    }
    if (net->load_model(task.modelPath.c_str()) != 0) {
        task.error = "failed to load ncnn model file";
        return nullptr;
    }

    std::unique_ptr<ncnn::Pipeline> preprocessPipeline;
    std::unique_ptr<ncnn::Pipeline> postprocessPipeline;
    if (useVulkan && task.modelKind != ModelKind::Luminance) {
        static std::vector<uint32_t> preprocessSpirv;
        static std::vector<uint32_t> postprocessSpirv;
        if (preprocessSpirv.empty() && ncnn::compile_spirv_module(
                kReaderSuperResolutionPreprocessShader,
                net->opt,
                preprocessSpirv) != 0) {
            task.error = "failed to compile super-resolution Vulkan preprocessing shader";
            return nullptr;
        }
        if (postprocessSpirv.empty() && ncnn::compile_spirv_module(
                kReaderSuperResolutionPostprocessShader,
                net->opt,
                postprocessSpirv) != 0) {
            task.error = "failed to compile super-resolution Vulkan postprocessing shader";
            return nullptr;
        }
        std::vector<ncnn::vk_specialization_type> specializations(2);
        specializations[0].i = 0;
        specializations[1].i = task.modelKind == ModelKind::RealEsrgan ? 1 : 0;
        preprocessPipeline = std::make_unique<ncnn::Pipeline>(net->vulkan_device());
        postprocessPipeline = std::make_unique<ncnn::Pipeline>(net->vulkan_device());
        const int localSize = task.modelKind == ModelKind::RealEsrgan ? 32 : 8;
        preprocessPipeline->set_optimal_local_size_xyz(localSize, localSize, 3);
        postprocessPipeline->set_optimal_local_size_xyz(localSize, localSize, 4);
        if (preprocessPipeline->create(
                preprocessSpirv.data(),
                preprocessSpirv.size() * sizeof(uint32_t),
                specializations) != 0 ||
            postprocessPipeline->create(
                postprocessSpirv.data(),
                postprocessSpirv.size() * sizeof(uint32_t),
                specializations) != 0) {
            task.error = "failed to create super-resolution Vulkan preprocessing pipeline";
            return nullptr;
        }
    }

    ResetCachedRuntime();
    gCachedNet = std::move(net);
    gCachedPreprocessPipeline = std::move(preprocessPipeline);
    gCachedPostprocessPipeline = std::move(postprocessPipeline);
    gCachedNetKey = key;
    task.modelLoadMs = ElapsedMilliseconds(startedAt);
    return gCachedNet.get();
}

ncnn::Mat NormalizedRgbaRoi(
    const UpscaleTask &task,
    int x,
    int y,
    int width,
    int height)
{
    ncnn::Mat rgba = ncnn::Mat::from_pixels_roi(
        task.input.data(),
        ncnn::Mat::PIXEL_RGBA,
        task.width,
        task.height,
        task.stride,
        x,
        y,
        width,
        height);
    if (rgba.empty()) {
        return {};
    }
    ncnn::Mat normalized(rgba.w, rgba.h, 3);
    for (int channel = 0; channel < 3; ++channel) {
        const float *source = rgba.channel(channel);
        float *destination = normalized.channel(channel);
        for (int index = 0; index < rgba.w * rgba.h; ++index) {
            *destination++ = *source++ * (1.0f / 255.0f);
        }
    }
    return normalized;
}

ncnn::Mat NormalizedLumaRoi(
    const UpscaleTask &task,
    int x,
    int y,
    int width,
    int height)
{
    ncnn::Mat luma(width, height, 1);
    if (luma.empty()) {
        return {};
    }
    for (int row = 0; row < height; ++row) {
        float *destination = luma.row(row);
        const uint8_t *source = task.input.data() +
            static_cast<size_t>(y + row) * task.stride + static_cast<size_t>(x) * 4;
        for (int column = 0; column < width; ++column) {
            const float red = source[0] * (1.0f / 255.0f);
            const float green = source[1] * (1.0f / 255.0f);
            const float blue = source[2] * (1.0f / 255.0f);
            destination[column] =
                (65.481f * red + 128.553f * green + 24.966f * blue + 16.0f) *
                (1.0f / 255.0f);
            source += 4;
        }
    }
    return luma;
}

struct RgbSample {
    float red;
    float green;
    float blue;
};

RgbSample BilinearSourceRgb(const UpscaleTask &task, float x, float y)
{
    const float clampedX = std::clamp(x, 0.0f, static_cast<float>(task.width - 1));
    const float clampedY = std::clamp(y, 0.0f, static_cast<float>(task.height - 1));
    const int x0 = static_cast<int>(std::floor(clampedX));
    const int y0 = static_cast<int>(std::floor(clampedY));
    const int x1 = std::min(x0 + 1, task.width - 1);
    const int y1 = std::min(y0 + 1, task.height - 1);
    const float tx = clampedX - x0;
    const float ty = clampedY - y0;
    const uint8_t *topLeft = task.input.data() +
        static_cast<size_t>(y0) * task.stride + static_cast<size_t>(x0) * 4;
    const uint8_t *topRight = task.input.data() +
        static_cast<size_t>(y0) * task.stride + static_cast<size_t>(x1) * 4;
    const uint8_t *bottomLeft = task.input.data() +
        static_cast<size_t>(y1) * task.stride + static_cast<size_t>(x0) * 4;
    const uint8_t *bottomRight = task.input.data() +
        static_cast<size_t>(y1) * task.stride + static_cast<size_t>(x1) * 4;
    const float topLeftWeight = (1.0f - tx) * (1.0f - ty);
    const float topRightWeight = tx * (1.0f - ty);
    const float bottomLeftWeight = (1.0f - tx) * ty;
    const float bottomRightWeight = tx * ty;
    constexpr float normalization = 1.0f / 255.0f;
    return {
        (topLeft[0] * topLeftWeight + topRight[0] * topRightWeight +
            bottomLeft[0] * bottomLeftWeight + bottomRight[0] * bottomRightWeight) * normalization,
        (topLeft[1] * topLeftWeight + topRight[1] * topRightWeight +
            bottomLeft[1] * bottomLeftWeight + bottomRight[1] * bottomRightWeight) * normalization,
        (topLeft[2] * topLeftWeight + topRight[2] * topRightWeight +
            bottomLeft[2] * bottomLeftWeight + bottomRight[2] * bottomRightWeight) * normalization,
    };
}

bool RunVulkan(UpscaleTask &task, ncnn::Net &net)
{
    if (gCachedPreprocessPipeline == nullptr || gCachedPostprocessPipeline == nullptr ||
        net.vulkan_device() == nullptr) {
        task.error = "super-resolution Vulkan pipelines are unavailable";
        return false;
    }

    const ncnn::VulkanDevice *device = net.vulkan_device();
    ncnn::VkAllocator *blobAllocator = device->acquire_blob_allocator();
    ncnn::VkAllocator *stagingAllocator = device->acquire_staging_allocator();
    ncnn::Option option = net.opt;
    option.blob_vkallocator = blobAllocator;
    option.workspace_vkallocator = blobAllocator;
    option.staging_vkallocator = stagingAllocator;

    const bool success = [&]() -> bool {
        const int outputWidth = task.width * kScale;
        const int outputHeight = task.height * kScale;
        task.output.assign(static_cast<size_t>(outputWidth) * outputHeight * 4, 255);

        ncnn::VkCompute command(device);
        ncnn::Mat sourceBytes(
            static_cast<int>(task.input.size()),
            task.input.data(),
            static_cast<size_t>(1u),
            1);
        ncnn::VkMat sourceGpu;
        command.record_clone(sourceBytes, sourceGpu, option);
        command.submit_and_wait();
        command.reset();

        ncnn::VkMat outputGpu;
        outputGpu.create(
            outputWidth,
            outputHeight,
            static_cast<size_t>(4u),
            1,
            blobAllocator);
        if (sourceGpu.empty() || outputGpu.empty()) {
            task.error = "failed to allocate super-resolution Vulkan image buffers";
            return false;
        }

        const int xTiles = (task.width + task.tileSize - 1) / task.tileSize;
        const int yTiles = (task.height + task.tileSize - 1) / task.tileSize;
        const size_t tileElementSize = option.use_fp16_storage ? 2u : 4u;
        for (int tileY = 0; tileY < yTiles; ++tileY) {
            const int inputY = tileY * task.tileSize;
            const int tileHeight = std::min(inputY + task.tileSize, task.height) - inputY;
            const int paddingBottom = task.modelKind == ModelKind::RealEsrgan
                ? task.prepadding + (tileHeight % 2)
                : task.prepadding + ((tileHeight + 1) / 2 * 2) - tileHeight;
            const int paddedHeight = tileHeight + task.prepadding + paddingBottom;

            for (int tileX = 0; tileX < xTiles; ++tileX) {
                if (!WaitUntilInferenceAllowed(task)) {
                    return false;
                }
                const int inputX = tileX * task.tileSize;
                const int tileWidth = std::min(inputX + task.tileSize, task.width) - inputX;
                const int paddingRight = task.modelKind == ModelKind::RealEsrgan
                    ? task.prepadding + (tileWidth % 2)
                    : task.prepadding + ((tileWidth + 1) / 2 * 2) - tileWidth;
                const int paddedWidth = tileWidth + task.prepadding + paddingRight;

                ncnn::VkMat inputTileGpu;
                inputTileGpu.create(
                    paddedWidth,
                    paddedHeight,
                    3,
                    tileElementSize,
                    1,
                    blobAllocator);
                if (inputTileGpu.empty()) {
                    task.error = "failed to allocate super-resolution Vulkan input tile";
                    return false;
                }
                std::vector<ncnn::VkMat> preprocessBindings(2);
                preprocessBindings[0] = sourceGpu;
                preprocessBindings[1] = inputTileGpu;
                std::vector<ncnn::vk_constant_type> preprocessConstants(11);
                preprocessConstants[0].i = task.width;
                preprocessConstants[1].i = task.height;
                preprocessConstants[2].i = task.stride;
                preprocessConstants[3].i = inputTileGpu.w;
                preprocessConstants[4].i = inputTileGpu.h;
                preprocessConstants[5].i = inputTileGpu.cstep;
                preprocessConstants[6].i = task.prepadding;
                preprocessConstants[7].i = task.prepadding;
                preprocessConstants[8].i = inputX;
                preprocessConstants[9].i = inputY;
                preprocessConstants[10].i = 4;
                ncnn::VkMat preprocessDispatcher;
                preprocessDispatcher.w = inputTileGpu.w;
                preprocessDispatcher.h = inputTileGpu.h;
                preprocessDispatcher.c = 3;
                command.record_pipeline(
                    gCachedPreprocessPipeline.get(),
                    preprocessBindings,
                    preprocessConstants,
                    preprocessDispatcher);

                ncnn::Extractor extractor = net.create_extractor();
                extractor.set_blob_vkallocator(blobAllocator);
                extractor.set_workspace_vkallocator(blobAllocator);
                extractor.set_staging_vkallocator(stagingAllocator);
                if (extractor.input(task.inputName.c_str(), inputTileGpu) != 0) {
                    task.error = "super-resolution model rejected the Vulkan input tile";
                    return false;
                }
                ncnn::VkMat outputTileGpu;
                if (extractor.extract(task.outputName.c_str(), outputTileGpu, command) != 0) {
                    task.error = "super-resolution model failed to infer the Vulkan output tile";
                    return false;
                }

                const int writeWidth = tileWidth * kScale;
                const int writeHeight = tileHeight * kScale;
                const int crop = task.modelKind == ModelKind::RealEsrgan
                    ? task.prepadding * kScale
                    : 0;
                if (outputTileGpu.w < crop + writeWidth ||
                    outputTileGpu.h < crop + writeHeight) {
                    task.error = "super-resolution Vulkan output tile has an unexpected shape";
                    return false;
                }
                std::vector<ncnn::VkMat> postprocessBindings(2);
                postprocessBindings[0] = outputTileGpu;
                postprocessBindings[1] = outputGpu;
                std::vector<ncnn::vk_constant_type> postprocessConstants(12);
                postprocessConstants[0].i = outputTileGpu.w;
                postprocessConstants[1].i = outputTileGpu.h;
                postprocessConstants[2].i = outputTileGpu.cstep;
                postprocessConstants[3].i = outputWidth;
                postprocessConstants[4].i = outputHeight;
                postprocessConstants[5].i = inputX * kScale;
                postprocessConstants[6].i = inputY * kScale;
                postprocessConstants[7].i = writeWidth;
                postprocessConstants[8].i = writeHeight;
                postprocessConstants[9].i = crop;
                postprocessConstants[10].i = crop;
                postprocessConstants[11].i = 4;
                ncnn::VkMat postprocessDispatcher;
                postprocessDispatcher.w = writeWidth;
                postprocessDispatcher.h = writeHeight;
                postprocessDispatcher.c = 4;
                command.record_pipeline(
                    gCachedPostprocessPipeline.get(),
                    postprocessBindings,
                    postprocessConstants,
                    postprocessDispatcher);
                command.submit_and_wait();
                command.reset();

                if (!EnsureRequestActive(task)) {
                    return false;
                }
                // One tile is the cancellation and GPU scheduling quantum. Leave a short gap so
                // RenderService can submit foreground composition work between inference tiles.
                std::this_thread::sleep_for(std::chrono::milliseconds(1));
            }
        }

        if (!WaitUntilInferenceAllowed(task)) {
            return false;
        }
        ncnn::Mat outputBytes(
            outputWidth,
            outputHeight,
            task.output.data(),
            static_cast<size_t>(4u),
            1);
        command.record_clone(outputGpu, outputBytes, option);
        command.submit_and_wait();
        return EnsureRequestActive(task);
    }();

    device->reclaim_blob_allocator(blobAllocator);
    device->reclaim_staging_allocator(stagingAllocator);
    return success;
}

bool RunWaifu2x(UpscaleTask &task, ncnn::Net &net)
{
    const int outputWidth = task.width * kScale;
    const int outputHeight = task.height * kScale;
    task.output.assign(static_cast<size_t>(outputWidth) * outputHeight * 4, 255);
    const int xTiles = (task.width + task.tileSize - 1) / task.tileSize;
    const int yTiles = (task.height + task.tileSize - 1) / task.tileSize;

    for (int tileY = 0; tileY < yTiles; ++tileY) {
        const int tileHeight =
            std::min((tileY + 1) * task.tileSize, task.height) - tileY * task.tileSize;
        int paddingBottom = task.prepadding;
        paddingBottom += ((tileHeight + 1) / 2 * 2) - tileHeight;
        const int inputY0 = std::max(tileY * task.tileSize - task.prepadding, 0);
        const int inputY1 =
            std::min((tileY + 1) * task.tileSize + paddingBottom, task.height);

        for (int tileX = 0; tileX < xTiles; ++tileX) {
            if (!WaitUntilInferenceAllowed(task)) {
                return false;
            }
            const int tileWidth =
                std::min((tileX + 1) * task.tileSize, task.width) - tileX * task.tileSize;
            int paddingRight = task.prepadding;
            paddingRight += ((tileWidth + 1) / 2 * 2) - tileWidth;
            const int inputX0 = std::max(tileX * task.tileSize - task.prepadding, 0);
            const int inputX1 =
                std::min((tileX + 1) * task.tileSize + paddingRight, task.width);

            ncnn::Mat normalized = NormalizedRgbaRoi(
                task, inputX0, inputY0, inputX1 - inputX0, inputY1 - inputY0);
            if (normalized.empty()) {
                task.error = "failed to create ncnn input tile";
                return false;
            }

            const int padTop = std::max(task.prepadding - tileY * task.tileSize, 0);
            const int padBottom = std::max(
                std::min((tileY + 1) * task.tileSize + paddingBottom - task.height, paddingBottom),
                0);
            const int padLeft = std::max(task.prepadding - tileX * task.tileSize, 0);
            const int padRight = std::max(
                std::min((tileX + 1) * task.tileSize + paddingRight - task.width, paddingRight),
                0);
            ncnn::Mat padded;
            ncnn::copy_make_border(
                normalized,
                padded,
                padTop,
                padBottom,
                padLeft,
                padRight,
                ncnn::BORDER_REPLICATE,
                0.0f,
                net.opt);

            ncnn::Extractor extractor = net.create_extractor();
            if (extractor.input(task.inputName.c_str(), padded) != 0) {
                task.error = "waifu2x rejected the input tile";
                return false;
            }
            ncnn::Mat outputTile;
            if (extractor.extract(task.outputName.c_str(), outputTile) != 0) {
                task.error = "waifu2x failed to infer the output tile";
                return false;
            }
            if (!WaitUntilInferenceAllowed(task)) {
                return false;
            }
            const int expectedWidth = tileWidth * kScale;
            const int expectedHeight = tileHeight * kScale;
            if (outputTile.w < expectedWidth || outputTile.h < expectedHeight || outputTile.c < 3) {
                task.error = "waifu2x returned an unexpected output shape";
                return false;
            }

            const int outputX0 = tileX * task.tileSize * kScale;
            const int outputY0 = tileY * task.tileSize * kScale;
            for (int y = 0; y < expectedHeight; ++y) {
                const float *red = outputTile.channel(0).row(y);
                const float *green = outputTile.channel(1).row(y);
                const float *blue = outputTile.channel(2).row(y);
                for (int x = 0; x < expectedWidth; ++x) {
                    const size_t offset =
                        (static_cast<size_t>(outputY0 + y) * outputWidth + outputX0 + x) * 4;
                    task.output[offset] = ToByte(red[x]);
                    task.output[offset + 1] = ToByte(green[x]);
                    task.output[offset + 2] = ToByte(blue[x]);
                }
            }
        }
    }
    return true;
}

bool RunRealEsrgan(UpscaleTask &task, ncnn::Net &net)
{
    const int outputWidth = task.width * kScale;
    const int outputHeight = task.height * kScale;
    task.output.assign(static_cast<size_t>(outputWidth) * outputHeight * 4, 255);
    const int xTiles = (task.width + task.tileSize - 1) / task.tileSize;
    const int yTiles = (task.height + task.tileSize - 1) / task.tileSize;

    for (int tileY = 0; tileY < yTiles; ++tileY) {
        const int outputInputY0 = tileY * task.tileSize;
        const int tileHeight = std::min(outputInputY0 + task.tileSize, task.height) - outputInputY0;
        const int paddingBottom = task.prepadding + (tileHeight % 2);
        const int inputY0 = std::max(outputInputY0 - task.prepadding, 0);
        const int inputY1 = std::min(outputInputY0 + tileHeight + paddingBottom, task.height);
        const int borderTop = std::max(task.prepadding - outputInputY0, 0);
        const int borderBottom =
            std::max(outputInputY0 + tileHeight + paddingBottom - task.height, 0);

        for (int tileX = 0; tileX < xTiles; ++tileX) {
            if (!WaitUntilInferenceAllowed(task)) {
                return false;
            }
            const int outputInputX0 = tileX * task.tileSize;
            const int tileWidth = std::min(outputInputX0 + task.tileSize, task.width) - outputInputX0;
            const int paddingRight = task.prepadding + (tileWidth % 2);
            const int inputX0 = std::max(outputInputX0 - task.prepadding, 0);
            const int inputX1 = std::min(outputInputX0 + tileWidth + paddingRight, task.width);
            const int borderLeft = std::max(task.prepadding - outputInputX0, 0);
            const int borderRight =
                std::max(outputInputX0 + tileWidth + paddingRight - task.width, 0);

            ncnn::Mat normalized = NormalizedRgbaRoi(
                task, inputX0, inputY0, inputX1 - inputX0, inputY1 - inputY0);
            if (normalized.empty()) {
                task.error = "failed to create Real-ESRGAN input tile";
                return false;
            }
            ncnn::Mat padded;
            ncnn::copy_make_border(
                normalized,
                padded,
                borderTop,
                borderBottom,
                borderLeft,
                borderRight,
                ncnn::BORDER_REPLICATE,
                0.0f,
                net.opt);
            if ((padded.w % 2) != 0 || (padded.h % 2) != 0) {
                task.error = "Real-ESRGAN input tile must have even dimensions";
                return false;
            }

            ncnn::Extractor extractor = net.create_extractor();
            if (extractor.input(task.inputName.c_str(), padded) != 0) {
                task.error = "Real-ESRGAN rejected the input tile";
                return false;
            }
            ncnn::Mat outputTile;
            if (extractor.extract(task.outputName.c_str(), outputTile) != 0) {
                task.error = "Real-ESRGAN failed to infer the output tile";
                return false;
            }
            if (!EnsureRequestActive(task)) {
                return false;
            }
            const int expectedWidth = tileWidth * kScale;
            const int expectedHeight = tileHeight * kScale;
            const int sourceX = task.prepadding * kScale;
            const int sourceY = task.prepadding * kScale;
            if (outputTile.w < sourceX + expectedWidth ||
                outputTile.h < sourceY + expectedHeight || outputTile.c < 3) {
                task.error = "Real-ESRGAN returned an unexpected output shape";
                return false;
            }

            const int outputX0 = outputInputX0 * kScale;
            const int outputY0 = outputInputY0 * kScale;
            for (int y = 0; y < expectedHeight; ++y) {
                const float *red = outputTile.channel(0).row(sourceY + y) + sourceX;
                const float *green = outputTile.channel(1).row(sourceY + y) + sourceX;
                const float *blue = outputTile.channel(2).row(sourceY + y) + sourceX;
                for (int x = 0; x < expectedWidth; ++x) {
                    const size_t offset =
                        (static_cast<size_t>(outputY0 + y) * outputWidth + outputX0 + x) * 4;
                    task.output[offset] = ToByte(red[x]);
                    task.output[offset + 1] = ToByte(green[x]);
                    task.output[offset + 2] = ToByte(blue[x]);
                }
            }
        }
    }
    return true;
}

bool RunLuminance(UpscaleTask &task, ncnn::Net &net)
{
    const int outputWidth = task.width * kScale;
    const int outputHeight = task.height * kScale;
    task.output.assign(static_cast<size_t>(outputWidth) * outputHeight * 4, 255);
    const int xTiles = (task.width + task.tileSize - 1) / task.tileSize;
    const int yTiles = (task.height + task.tileSize - 1) / task.tileSize;

    for (int tileY = 0; tileY < yTiles; ++tileY) {
        const int outputInputY0 = tileY * task.tileSize;
        const int tileHeight = std::min(outputInputY0 + task.tileSize, task.height) - outputInputY0;
        const int inputY0 = std::max(outputInputY0 - task.prepadding, 0);
        const int inputY1 = std::min(outputInputY0 + tileHeight + task.prepadding, task.height);
        const int borderTop = std::max(task.prepadding - outputInputY0, 0);
        const int borderBottom =
            std::max(outputInputY0 + tileHeight + task.prepadding - task.height, 0);

        for (int tileX = 0; tileX < xTiles; ++tileX) {
            if (!WaitUntilInferenceAllowed(task)) {
                return false;
            }
            const int outputInputX0 = tileX * task.tileSize;
            const int tileWidth = std::min(outputInputX0 + task.tileSize, task.width) - outputInputX0;
            const int inputX0 = std::max(outputInputX0 - task.prepadding, 0);
            const int inputX1 = std::min(outputInputX0 + tileWidth + task.prepadding, task.width);
            const int borderLeft = std::max(task.prepadding - outputInputX0, 0);
            const int borderRight =
                std::max(outputInputX0 + tileWidth + task.prepadding - task.width, 0);

            ncnn::Mat normalized = NormalizedLumaRoi(
                task, inputX0, inputY0, inputX1 - inputX0, inputY1 - inputY0);
            if (normalized.empty()) {
                task.error = "failed to create luminance input tile";
                return false;
            }
            ncnn::Mat padded;
            ncnn::copy_make_border(
                normalized,
                padded,
                borderTop,
                borderBottom,
                borderLeft,
                borderRight,
                ncnn::BORDER_REPLICATE,
                0.0f,
                net.opt);

            ncnn::Extractor extractor = net.create_extractor();
            if (extractor.input(task.inputName.c_str(), padded) != 0) {
                task.error = "luminance model rejected the input tile";
                return false;
            }
            ncnn::Mat outputTile;
            if (extractor.extract(task.outputName.c_str(), outputTile) != 0) {
                task.error = "luminance model failed to infer the output tile";
                return false;
            }
            if (!EnsureRequestActive(task)) {
                return false;
            }
            const int expectedWidth = tileWidth * kScale;
            const int expectedHeight = tileHeight * kScale;
            const int sourceX = task.prepadding * kScale;
            const int sourceY = task.prepadding * kScale;
            if (outputTile.w < sourceX + expectedWidth ||
                outputTile.h < sourceY + expectedHeight || outputTile.c < 1) {
                task.error = "luminance model returned an unexpected output shape";
                return false;
            }

            const int outputX0 = outputInputX0 * kScale;
            const int outputY0 = outputInputY0 * kScale;
            for (int y = 0; y < expectedHeight; ++y) {
                const float *enhancedLuma = outputTile.channel(0).row(sourceY + y) + sourceX;
                for (int x = 0; x < expectedWidth; ++x) {
                    const int globalX = outputX0 + x;
                    const int globalY = outputY0 + y;
                    const float sampleX = (globalX + 0.5f) * 0.5f - 0.5f;
                    const float sampleY = (globalY + 0.5f) * 0.5f - 0.5f;
                    const RgbSample source = BilinearSourceRgb(task, sampleX, sampleY);
                    const float sourceLuma =
                        (65.481f * source.red + 128.553f * source.green +
                            24.966f * source.blue + 16.0f) *
                        (1.0f / 255.0f);
                    const float lumaDelta = (enhancedLuma[x] - sourceLuma) * (255.0f / 219.0f);
                    const size_t offset =
                        (static_cast<size_t>(globalY) * outputWidth + globalX) * 4;
                    task.output[offset] = ToByte(source.red + lumaDelta);
                    task.output[offset + 1] = ToByte(source.green + lumaDelta);
                    task.output[offset + 2] = ToByte(source.blue + lumaDelta);
                }
            }
        }
    }
    return true;
}

bool RunWithBackend(UpscaleTask &task, bool useVulkan)
{
    ncnn::Net *net = PrepareNet(task, useVulkan);
    if (net == nullptr) {
        return false;
    }
    const SteadyClock::time_point inferenceStartedAt = SteadyClock::now();
    const bool success = task.modelKind == ModelKind::Luminance
        ? RunLuminance(task, *net)
        : (useVulkan
            ? RunVulkan(task, *net)
            : (task.modelKind == ModelKind::RealEsrgan
                ? RunRealEsrgan(task, *net)
                : RunWaifu2x(task, *net)));
    task.inferenceMs = ElapsedMilliseconds(inferenceStartedAt);
    if (!success) {
        if (!task.cancelled) {
            ResetCachedRuntime();
        }
        return false;
    }
    task.backend = useVulkan ? "vulkan" : "cpu";
    return true;
}

bool RunUpscale(UpscaleTask &task)
{
    if (!ValidateTask(task)) {
        return false;
    }
    if (!EnsureRequestActive(task)) {
        return false;
    }
    std::lock_guard<std::mutex> lock(gInferenceMutex);
    if (!EnsureRequestActive(task)) {
        return false;
    }
    const bool canUseVulkan = VulkanAvailable();
    if (task.backendPreference == BackendPreference::Vulkan && !canUseVulkan) {
        task.error = "Vulkan backend is unavailable";
        return false;
    }
    const bool tryVulkan = task.backendPreference != BackendPreference::Cpu && canUseVulkan;
    if (tryVulkan && RunWithBackend(task, true)) {
        return true;
    }
    if (task.cancelled) {
        return false;
    }
    if (task.backendPreference == BackendPreference::Vulkan) {
        return false;
    }
    if (tryVulkan) {
        OH_LOG_Print(
            LOG_APP,
            LOG_WARN,
            0x0,
            "NextESuperResolution",
            "Vulkan inference failed, falling back to CPU: %{public}s",
            task.error.c_str());
        task.error.clear();
        task.output.clear();
    }
    return RunWithBackend(task, false);
}

void WaitUntilPreparationAllowed()
{
    std::unique_lock<std::mutex> lock(gInteractionMutex);
    while (gInteractionPaused) {
        gInteractionCondition.wait_for(lock, std::chrono::milliseconds(16));
    }
}

bool PrepareWithBackend(UpscaleTask &task, bool useVulkan)
{
    ncnn::Net *net = PrepareNet(task, useVulkan);
    if (net == nullptr) {
        return false;
    }
    task.backend = useVulkan ? "vulkan" : "cpu";
    return true;
}

bool RunPrepare(UpscaleTask &task)
{
    if (task.threads < 1) {
        task.error = "invalid ncnn thread configuration";
        return false;
    }
    WaitUntilPreparationAllowed();
    std::lock_guard<std::mutex> lock(gInferenceMutex);
    const bool canUseVulkan = VulkanAvailable();
    if (task.backendPreference == BackendPreference::Vulkan && !canUseVulkan) {
        task.error = "Vulkan backend is unavailable";
        return false;
    }
    const bool tryVulkan = task.backendPreference != BackendPreference::Cpu && canUseVulkan;
    if (tryVulkan && PrepareWithBackend(task, true)) {
        return true;
    }
    if (task.backendPreference == BackendPreference::Vulkan) {
        return false;
    }
    task.error.clear();
    task.modelLoadMs = 0;
    return PrepareWithBackend(task, false);
}

void ExecuteUpscale(napi_env env, void *data)
{
    (void)env;
    auto *task = static_cast<UpscaleTask *>(data);
    RunUpscale(*task);
    // The N-API completion callback runs on the ArkTS thread. Release the multi-megabyte source
    // copy here so cancellation cannot turn buffer destruction into a foreground input stall.
    std::vector<uint8_t>().swap(task->input);
}

void ExecutePrepare(napi_env env, void *data)
{
    (void)env;
    auto *task = static_cast<UpscaleTask *>(data);
    RunPrepare(*task);
}

napi_value StringValue(napi_env env, const std::string &value)
{
    napi_value result = nullptr;
    napi_create_string_utf8(env, value.c_str(), value.size(), &result);
    return result;
}

napi_value Int64Value(napi_env env, int64_t value)
{
    napi_value result = nullptr;
    napi_create_int64(env, value, &result);
    return result;
}

void FinalizeOutputBuffer(napi_env env, void *data, void *hint)
{
    (void)env;
    (void)data;
    delete static_cast<std::vector<uint8_t> *>(hint);
}

void CompleteUpscale(napi_env env, napi_status status, void *data)
{
    auto *task = static_cast<UpscaleTask *>(data);
    if (status == napi_ok && task->error.empty()) {
        napi_value outputBuffer = nullptr;
        napi_value result = nullptr;
        auto *output = new std::vector<uint8_t>(std::move(task->output));
        if (napi_create_object(env, &result) == napi_ok &&
            napi_create_external_arraybuffer(
                env,
                output->data(),
                output->size(),
                FinalizeOutputBuffer,
                output,
                &outputBuffer) == napi_ok) {
            napi_set_named_property(env, result, "pixels", outputBuffer);
            napi_set_named_property(env, result, "backend", StringValue(env, task->backend));
            napi_set_named_property(env, result, "modelLoadMs", Int64Value(env, task->modelLoadMs));
            napi_set_named_property(env, result, "inferenceMs", Int64Value(env, task->inferenceMs));
            napi_resolve_deferred(env, task->deferred, result);
        } else {
            delete output;
            task->error = "failed to allocate JavaScript output";
        }
    }
    if (status != napi_ok || !task->error.empty()) {
        const std::string message = task->error.empty() ? "native super-resolution task failed" : task->error;
        napi_value text = nullptr;
        napi_value error = nullptr;
        napi_create_string_utf8(env, message.c_str(), message.size(), &text);
        napi_create_error(env, nullptr, text, &error);
        napi_reject_deferred(env, task->deferred, error);
    }
    napi_delete_async_work(env, task->work);
    SetRequestActiveState(task->requestId, true);
    delete task;
}

void CompletePrepare(napi_env env, napi_status status, void *data)
{
    auto *task = static_cast<UpscaleTask *>(data);
    if (status == napi_ok && task->error.empty()) {
        napi_value result = nullptr;
        if (napi_create_object(env, &result) == napi_ok) {
            napi_set_named_property(env, result, "backend", StringValue(env, task->backend));
            napi_set_named_property(env, result, "modelLoadMs", Int64Value(env, task->modelLoadMs));
            napi_resolve_deferred(env, task->deferred, result);
        } else {
            task->error = "failed to allocate JavaScript preparation result";
        }
    }
    if (status != napi_ok || !task->error.empty()) {
        const std::string message = task->error.empty()
            ? "native super-resolution preparation failed"
            : task->error;
        napi_value text = nullptr;
        napi_value error = nullptr;
        napi_create_string_utf8(env, message.c_str(), message.size(), &text);
        napi_create_error(env, nullptr, text, &error);
        napi_reject_deferred(env, task->deferred, error);
    }
    napi_delete_async_work(env, task->work);
    delete task;
}

napi_value SetRequestActive(napi_env env, napi_callback_info info)
{
    size_t argc = 2;
    napi_value argv[2] = {nullptr};
    int64_t requestId = 0;
    bool active = false;
    if (napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr) != napi_ok || argc < 2 ||
        !GetInt64(env, argv[0], requestId) || requestId <= 0 ||
        napi_get_value_bool(env, argv[1], &active) != napi_ok) {
        napi_throw_type_error(env, nullptr, "setRequestActive expects a positive request ID and boolean state");
        return nullptr;
    }
    SetRequestActiveState(static_cast<uint64_t>(requestId), active);
    napi_value result = nullptr;
    napi_get_undefined(env, &result);
    return result;
}

napi_value SetInteractionPaused(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value argv[1] = {nullptr};
    bool paused = false;
    if (napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr) != napi_ok || argc < 1 ||
        napi_get_value_bool(env, argv[0], &paused) != napi_ok) {
        napi_throw_type_error(env, nullptr, "setInteractionPaused expects a boolean state");
        return nullptr;
    }
    SetInteractionPausedState(paused);
    napi_value result = nullptr;
    napi_get_undefined(env, &result);
    return result;
}

napi_value UpscaleRgba(napi_env env, napi_callback_info info)
{
    size_t argc = 14;
    napi_value argv[14] = {nullptr};
    if (napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr) != napi_ok || argc < 14) {
        napi_throw_type_error(env, nullptr, "upscaleRgba expects 14 arguments");
        return nullptr;
    }

    auto *task = new UpscaleTask();
    int modelKind = 0;
    int backendPreference = 0;
    int64_t requestId = 0;
    if (!GetBytes(env, argv[0], task->input) ||
        !GetInt(env, argv[1], task->width) ||
        !GetInt(env, argv[2], task->height) ||
        !GetInt(env, argv[3], task->stride) ||
        !GetInt(env, argv[6], modelKind) ||
        !GetInt(env, argv[7], backendPreference) ||
        !GetInt(env, argv[8], task->tileSize) ||
        !GetInt(env, argv[9], task->prepadding) ||
        !GetInt(env, argv[10], task->threads) ||
        !GetInt64(env, argv[13], requestId) ||
        requestId <= 0 ||
        modelKind < static_cast<int>(ModelKind::Waifu2x) ||
        modelKind > static_cast<int>(ModelKind::Luminance) ||
        backendPreference < static_cast<int>(BackendPreference::Automatic) ||
        backendPreference > static_cast<int>(BackendPreference::Cpu)) {
        delete task;
        napi_throw_type_error(env, nullptr, "invalid super-resolution argument type");
        return nullptr;
    }
    task->modelKind = static_cast<ModelKind>(modelKind);
    task->backendPreference = static_cast<BackendPreference>(backendPreference);
    task->requestId = static_cast<uint64_t>(requestId);
    task->paramPath = GetString(env, argv[4]);
    task->modelPath = GetString(env, argv[5]);
    task->inputName = GetString(env, argv[11]);
    task->outputName = GetString(env, argv[12]);
    if (task->paramPath.empty() || task->modelPath.empty() ||
        task->inputName.empty() || task->outputName.empty()) {
        delete task;
        napi_throw_type_error(env, nullptr, "ncnn model paths and blob names are required");
        return nullptr;
    }

    napi_value promise = nullptr;
    napi_create_promise(env, &task->deferred, &promise);
    napi_value resourceName = nullptr;
    napi_create_string_utf8(env, "NextESuperResolution", NAPI_AUTO_LENGTH, &resourceName);
    if (napi_create_async_work(
            env,
            nullptr,
            resourceName,
            ExecuteUpscale,
            CompleteUpscale,
            task,
            &task->work) != napi_ok ||
        // Reader enhancement is long-running and must yield scheduling priority to foreground ArkUI.
        napi_queue_async_work_with_qos(env, task->work, napi_qos_background) != napi_ok) {
        delete task;
        napi_throw_error(env, nullptr, "failed to queue native super-resolution task");
        return nullptr;
    }
    return promise;
}

napi_value PrepareModel(napi_env env, napi_callback_info info)
{
    size_t argc = 9;
    napi_value argv[9] = {nullptr};
    if (napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr) != napi_ok || argc < 9) {
        napi_throw_type_error(env, nullptr, "prepareModel expects 9 arguments");
        return nullptr;
    }

    auto *task = new UpscaleTask();
    int modelKind = 0;
    int backendPreference = 0;
    if (!GetInt(env, argv[2], modelKind) ||
        !GetInt(env, argv[3], backendPreference) ||
        !GetInt(env, argv[4], task->tileSize) ||
        !GetInt(env, argv[5], task->prepadding) ||
        !GetInt(env, argv[6], task->threads) ||
        modelKind < static_cast<int>(ModelKind::Waifu2x) ||
        modelKind > static_cast<int>(ModelKind::Luminance) ||
        backendPreference < static_cast<int>(BackendPreference::Automatic) ||
        backendPreference > static_cast<int>(BackendPreference::Cpu)) {
        delete task;
        napi_throw_type_error(env, nullptr, "invalid super-resolution preparation argument type");
        return nullptr;
    }
    task->modelKind = static_cast<ModelKind>(modelKind);
    task->backendPreference = static_cast<BackendPreference>(backendPreference);
    task->paramPath = GetString(env, argv[0]);
    task->modelPath = GetString(env, argv[1]);
    task->inputName = GetString(env, argv[7]);
    task->outputName = GetString(env, argv[8]);
    if (task->paramPath.empty() || task->modelPath.empty() || task->tileSize < 32 || task->prepadding < 0 ||
        task->threads < 1 ||
        task->inputName.empty() || task->outputName.empty()) {
        delete task;
        napi_throw_type_error(env, nullptr, "ncnn preparation configuration is required");
        return nullptr;
    }

    napi_value promise = nullptr;
    napi_create_promise(env, &task->deferred, &promise);
    napi_value resourceName = nullptr;
    napi_create_string_utf8(env, "NextESuperResolutionPrepare", NAPI_AUTO_LENGTH, &resourceName);
    if (napi_create_async_work(
            env,
            nullptr,
            resourceName,
            ExecutePrepare,
            CompletePrepare,
            task,
            &task->work) != napi_ok) {
        delete task;
        napi_throw_error(env, nullptr, "failed to create native super-resolution preparation task");
        return nullptr;
    }
    if (napi_queue_async_work_with_qos(env, task->work, napi_qos_background) != napi_ok) {
        napi_delete_async_work(env, task->work);
        delete task;
        napi_throw_error(env, nullptr, "failed to queue native super-resolution preparation task");
        return nullptr;
    }
    return promise;
}

napi_value GetCapabilities(napi_env env, napi_callback_info info)
{
    (void)info;
    InitializeGpuRuntime();
    napi_value result = nullptr;
    napi_value vulkanAvailable = nullptr;
    napi_value gpuCount = nullptr;
    napi_create_object(env, &result);
    napi_get_boolean(env, VulkanAvailable(), &vulkanAvailable);
    napi_create_int32(env, gGpuCount, &gpuCount);
    napi_set_named_property(env, result, "vulkanAvailable", vulkanAvailable);
    napi_set_named_property(env, result, "gpuCount", gpuCount);
    napi_set_named_property(env, result, "gpuName", StringValue(env, gGpuName));
    napi_set_named_property(env, result, "ncnnVersion", StringValue(env, NCNN_VERSION_STRING));
    return result;
}

} // namespace

EXTERN_C_START
static napi_value Init(napi_env env, napi_value exports)
{
    napi_property_descriptor descriptors[] = {
        {"prepareModel", nullptr, PrepareModel, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"upscaleRgba", nullptr, UpscaleRgba, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"setRequestActive", nullptr, SetRequestActive, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"setInteractionPaused", nullptr, SetInteractionPaused, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"getCapabilities", nullptr, GetCapabilities, nullptr, nullptr, nullptr, napi_default, nullptr},
    };
    napi_define_properties(env, exports, sizeof(descriptors) / sizeof(descriptors[0]), descriptors);
    return exports;
}
EXTERN_C_END

static napi_module superResolutionModule = {
    .nm_version = 1,
    .nm_flags = 0,
    .nm_filename = nullptr,
    .nm_register_func = Init,
    .nm_modname = kModuleName,
    .nm_priv = nullptr,
    .reserved = {0},
};

extern "C" __attribute__((constructor)) void RegisterNextESuperResolutionModule(void)
{
    OH_LOG_Print(LOG_APP, LOG_INFO, 0x0, "NextESuperResolution", "native ncnn runtime loaded");
    napi_module_register(&superResolutionModule);
}
