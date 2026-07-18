#include <napi/native_api.h>

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <memory>
#include <mutex>
#include <string>
#include <vector>

#include <gpu.h>
#include <hilog/log.h>
#include <mat.h>
#include <net.h>
#include <platform.h>

namespace {

constexpr const char *kModuleName = "nexte_super_resolution";
constexpr int kScale = 2;

enum class ModelKind : int {
    Waifu2x = 0,
    RealEsrgan = 1,
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
};

std::once_flag gGpuInitFlag;
int gGpuInitResult = -1;
int gGpuCount = 0;
std::string gGpuName;
std::mutex gInferenceMutex;
std::unique_ptr<ncnn::Net> gCachedNet;
std::string gCachedNetKey;

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
            }
        }
        OH_LOG_Print(
            LOG_APP,
            gGpuCount > 0 ? LOG_INFO : LOG_WARN,
            0x0,
            "NextESuperResolution",
            "ncnn Vulkan init result=%{public}d gpuCount=%{public}d gpu=%{public}s",
            gGpuInitResult,
            gGpuCount,
            gGpuName.c_str());
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
        (useVulkan ? "vulkan" : "cpu") + "|" + std::to_string(task.threads);
    if (gCachedNet != nullptr && gCachedNetKey == key) {
        return gCachedNet.get();
    }

    auto net = std::make_unique<ncnn::Net>();
    net->opt.num_threads = task.threads;
    net->opt.use_vulkan_compute = useVulkan;
    net->opt.use_fp16_packed = true;
    net->opt.use_fp16_storage = true;
    net->opt.use_fp16_arithmetic = false;
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
    gCachedNet = std::move(net);
    gCachedNetKey = key;
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

bool RunWithBackend(UpscaleTask &task, bool useVulkan)
{
    ncnn::Net *net = PrepareNet(task, useVulkan);
    if (net == nullptr) {
        return false;
    }
    const bool success = task.modelKind == ModelKind::RealEsrgan
        ? RunRealEsrgan(task, *net)
        : RunWaifu2x(task, *net);
    if (!success) {
        gCachedNet.reset();
        gCachedNetKey.clear();
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
    std::lock_guard<std::mutex> lock(gInferenceMutex);
    const bool canUseVulkan = VulkanAvailable();
    if (task.backendPreference == BackendPreference::Vulkan && !canUseVulkan) {
        task.error = "Vulkan backend is unavailable";
        return false;
    }
    const bool tryVulkan = task.backendPreference != BackendPreference::Cpu && canUseVulkan;
    if (tryVulkan && RunWithBackend(task, true)) {
        return true;
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

void ExecuteUpscale(napi_env env, void *data)
{
    (void)env;
    auto *task = static_cast<UpscaleTask *>(data);
    RunUpscale(*task);
}

napi_value StringValue(napi_env env, const std::string &value)
{
    napi_value result = nullptr;
    napi_create_string_utf8(env, value.c_str(), value.size(), &result);
    return result;
}

void CompleteUpscale(napi_env env, napi_status status, void *data)
{
    auto *task = static_cast<UpscaleTask *>(data);
    if (status == napi_ok && task->error.empty()) {
        void *outputData = nullptr;
        napi_value outputBuffer = nullptr;
        napi_value result = nullptr;
        if (napi_create_arraybuffer(env, task->output.size(), &outputData, &outputBuffer) == napi_ok &&
            napi_create_object(env, &result) == napi_ok) {
            std::memcpy(outputData, task->output.data(), task->output.size());
            napi_set_named_property(env, result, "pixels", outputBuffer);
            napi_set_named_property(env, result, "backend", StringValue(env, task->backend));
            napi_resolve_deferred(env, task->deferred, result);
        } else {
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
    delete task;
}

napi_value UpscaleRgba(napi_env env, napi_callback_info info)
{
    size_t argc = 13;
    napi_value argv[13] = {nullptr};
    if (napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr) != napi_ok || argc < 13) {
        napi_throw_type_error(env, nullptr, "upscaleRgba expects 13 arguments");
        return nullptr;
    }

    auto *task = new UpscaleTask();
    int modelKind = 0;
    int backendPreference = 0;
    if (!GetBytes(env, argv[0], task->input) ||
        !GetInt(env, argv[1], task->width) ||
        !GetInt(env, argv[2], task->height) ||
        !GetInt(env, argv[3], task->stride) ||
        !GetInt(env, argv[6], modelKind) ||
        !GetInt(env, argv[7], backendPreference) ||
        !GetInt(env, argv[8], task->tileSize) ||
        !GetInt(env, argv[9], task->prepadding) ||
        !GetInt(env, argv[10], task->threads) ||
        modelKind < static_cast<int>(ModelKind::Waifu2x) ||
        modelKind > static_cast<int>(ModelKind::RealEsrgan) ||
        backendPreference < static_cast<int>(BackendPreference::Automatic) ||
        backendPreference > static_cast<int>(BackendPreference::Cpu)) {
        delete task;
        napi_throw_type_error(env, nullptr, "invalid super-resolution argument type");
        return nullptr;
    }
    task->modelKind = static_cast<ModelKind>(modelKind);
    task->backendPreference = static_cast<BackendPreference>(backendPreference);
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
        {"upscaleRgba", nullptr, UpscaleRgba, nullptr, nullptr, nullptr, napi_default, nullptr},
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
