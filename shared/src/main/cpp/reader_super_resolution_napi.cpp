#include <napi/native_api.h>

#include <algorithm>
#include <chrono>
#include <cmath>
#include <condition_variable>
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <fstream>
#include <iterator>
#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <unordered_set>
#include <vector>

#include <sys/mman.h>

#if defined(__aarch64__)
#include <arm_neon.h>
#endif

#include <command.h>
#include <gpu.h>
#include <hilog/log.h>
#include <mat.h>
#include <net.h>
#include <pipeline.h>
#include <platform.h>

#include <mindspore/context.h>
#include <mindspore/model.h>
#include <mindspore/tensor.h>

#include "reader_super_resolution_shaders.h"

namespace {

constexpr const char *kModuleName = "nexte_super_resolution";
constexpr int kScale = 2;

struct MmapAllocation {
    void *base = nullptr;
    void *aligned = nullptr;
    size_t length = 0;
    size_t capacity = 0;
    bool inUse = false;
};

class MmapNcnnAllocator final : public ncnn::Allocator {
public:
    ~MmapNcnnAllocator() override
    {
        for (const MmapAllocation &allocation : allocations_) {
            munmap(allocation.base, allocation.length);
        }
    }

    void *fastMalloc(size_t size) override
    {
        std::lock_guard<std::mutex> lock(mutex_);
        size_t bestIndex = allocations_.size();
        size_t bestCapacity = SIZE_MAX;
        for (size_t index = 0; index < allocations_.size(); ++index) {
            const MmapAllocation &allocation = allocations_[index];
            if (!allocation.inUse && allocation.capacity >= size &&
                allocation.capacity < bestCapacity) {
                bestIndex = index;
                bestCapacity = allocation.capacity;
            }
        }
        if (bestIndex < allocations_.size()) {
            allocations_[bestIndex].inUse = true;
            return allocations_[bestIndex].aligned;
        }

        constexpr size_t kExtraBytes = NCNN_MALLOC_ALIGN - 1 + NCNN_MALLOC_OVERREAD;
        if (size > SIZE_MAX - kExtraBytes) {
            return nullptr;
        }
        const size_t length = size + kExtraBytes;
        void *base = mmap(
            nullptr,
            length,
            PROT_READ | PROT_WRITE,
            MAP_PRIVATE | MAP_ANONYMOUS,
            -1,
            0);
        if (base == MAP_FAILED) {
            return nullptr;
        }
        auto *aligned = ncnn::alignPtr(static_cast<unsigned char *>(base), NCNN_MALLOC_ALIGN);
        const size_t offset = static_cast<size_t>(
            aligned - static_cast<unsigned char *>(base));
        allocations_.push_back(MmapAllocation{
            base,
            aligned,
            length,
            length - offset - NCNN_MALLOC_OVERREAD,
            true,
        });
        return aligned;
    }

    void fastFree(void *ptr) override
    {
        if (ptr == nullptr) {
            return;
        }
        std::lock_guard<std::mutex> lock(mutex_);
        for (MmapAllocation &allocation : allocations_) {
            if (allocation.aligned == ptr) {
                allocation.inUse = false;
                return;
            }
        }
    }

private:
    std::mutex mutex_;
    std::vector<MmapAllocation> allocations_;
};

enum class ModelKind : int {
    Waifu2x = 0,
    RealEsrgan = 1,
    Luminance = 2,
    RealCugan = 3,
    Waifu2xCunet = 4,
};

enum class BackendPreference : int {
    Automatic = 0,
    Vulkan = 1,
    Cpu = 2,
};

struct MindSporeContract {
    int inputSize = 0;
    int outputSize = 0;
    int inputChannels = 0;
    int outputChannels = 0;
    int tileSize = 0;
    int prepadding = 0;
    int outputCrop = 0;
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
    int effectStrengthPercent = 100;
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
    int tileCount = 0;
};

struct ComicRegionDetection {
    float points[8] = {0.0f};
    float score = 0.0f;
    int classId = 0;
};

struct ComicRegionDetectionTask {
    napi_async_work work = nullptr;
    napi_deferred deferred = nullptr;
    std::vector<uint8_t> input;
    std::vector<ComicRegionDetection> regions;
    int width = 0;
    int height = 0;
    int stride = 0;
    int threads = 2;
    float confidenceThreshold = 0.5f;
    std::string paramPath;
    std::string modelPath;
    std::string error;
    int64_t modelLoadMs = 0;
    int64_t inferenceMs = 0;
};

struct ComicTextRecognitionTask {
    napi_async_work work = nullptr;
    napi_deferred deferred = nullptr;
    std::vector<uint8_t> input;
    int width = 0;
    int height = 0;
    int stride = 0;
    int threads = 2;
    bool rotateCounterClockwise = false;
    std::string paramPath;
    std::string modelPath;
    std::string dictionaryPath;
    std::string text;
    std::string error;
    float score = 0.0f;
    int64_t modelLoadMs = 0;
    int64_t preprocessingMs = 0;
    int64_t inferenceMs = 0;
    int64_t decodingMs = 0;
};

struct ComicInpaintingTask {
    napi_async_work work = nullptr;
    napi_deferred deferred = nullptr;
    std::vector<uint8_t> input;
    std::vector<uint8_t> mask;
    std::vector<uint8_t> output;
    int width = 0;
    int height = 0;
    int stride = 0;
    int threads = 2;
    bool inputBgra = false;
    std::string paramPath;
    std::string modelPath;
    std::string error;
    int64_t modelLoadMs = 0;
    int64_t preprocessingMs = 0;
    int64_t inferenceMs = 0;
    int64_t postprocessingMs = 0;
    int inferenceWidth = 0;
    int inferenceHeight = 0;
};

struct ComicTextMaskTask {
    napi_async_work work = nullptr;
    napi_deferred deferred = nullptr;
    std::vector<uint8_t> input;
    std::vector<uint8_t> mask;
    std::vector<uint8_t> secondaryMask;
    int width = 0;
    int height = 0;
    int stride = 0;
    int threads = 2;
    float threshold = 0.3f;
    float secondaryThreshold = 0.0f;
    bool inputBgra = false;
    std::string paramPath;
    std::string modelPath;
    std::string error;
    int64_t modelLoadMs = 0;
    int64_t preprocessingMs = 0;
    int64_t inferenceMs = 0;
    int64_t postprocessingMs = 0;
    int64_t resultMarshallingMs = 0;
    int64_t maskedPixels = 0;
    int64_t secondaryMaskedPixels = 0;
};

std::once_flag gGpuInitFlag;
int gGpuInitResult = -1;
int gGpuCount = 0;
uint32_t gGpuHeapBudget = 0;
uint32_t gGpuApiVersion = 0;
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
std::mutex gMindSporeMutex;
OH_AI_ModelHandle gCachedMindSporeModel = nullptr;
std::string gCachedMindSporeModelPath;
std::string gCachedMindSporeDeviceName;
int gCachedMindSporeModelKind = -1;
std::unordered_set<std::string> gRejectedMindSporeModelDevices;
std::mutex gComicDetectorMutex;
std::unique_ptr<ncnn::Net> gCachedComicDetectorNet;
std::string gCachedComicDetectorKey;
std::mutex gComicRecognizerMutex;
std::unique_ptr<ncnn::Net> gCachedComicRecognizerNet;
std::string gCachedComicRecognizerKey;
std::vector<std::string> gCachedComicRecognizerDictionary;
std::mutex gComicInpainterMutex;
std::unique_ptr<ncnn::Net> gCachedComicInpainterNet;
std::string gCachedComicInpainterKey;
std::mutex gComicTextMaskMutex;
std::unique_ptr<ncnn::Net> gCachedComicTextMaskNet;
std::string gCachedComicTextMaskKey;

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
                const ncnn::GpuInfo &gpuInfo = ncnn::get_gpu_info(0);
                gGpuApiVersion = gpuInfo.api_version();
                const char *name = gpuInfo.device_name();
                if (name != nullptr) {
                    gGpuName = name;
                }
                const ncnn::VulkanDevice *device = ncnn::get_gpu_device(0);
                if (device != nullptr) {
                    gGpuHeapBudget = device->get_heap_budget();
                }
                OH_LOG_Print(
                    LOG_APP,
                    LOG_INFO,
                    0x0,
                    "NextESuperResolution",
                    "ncnn Vulkan properties api=%{public}u driver=%{public}u vendor=%{public}u "
                    "device=%{public}u score=%{public}u computeQueues=%{public}u "
                    "transferQueues=%{public}u unifiedQueue=%{public}d subgroup=%{public}u",
                    gpuInfo.api_version(),
                    gpuInfo.driver_version(),
                    gpuInfo.vendor_id(),
                    gpuInfo.device_id(),
                    gpuInfo.rough_score(),
                    gpuInfo.compute_queue_count(),
                    gpuInfo.transfer_queue_count(),
                    gpuInfo.unified_compute_transfer_queue() ? 1 : 0,
                    gpuInfo.subgroup_size());
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

bool GetFloat(napi_env env, napi_value value, float &result)
{
    double number = 0.0;
    if (napi_get_value_double(env, value, &number) != napi_ok || !std::isfinite(number)) {
        return false;
    }
    result = static_cast<float>(number);
    return true;
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

void ResetCachedMindSporeRuntime()
{
    if (gCachedMindSporeModel != nullptr) {
        OH_AI_ModelDestroy(&gCachedMindSporeModel);
    }
    gCachedMindSporeModelPath.clear();
    gCachedMindSporeDeviceName.clear();
    gCachedMindSporeModelKind = -1;
}

bool ResolveMindSporeContract(UpscaleTask &task, MindSporeContract &contract)
{
    if (task.modelKind == ModelKind::RealEsrgan) {
        contract = {180, 360, 3, 3, 160, 10, 20};
        return true;
    }
    if (task.modelKind == ModelKind::Waifu2x) {
        // upconv7 uses six valid 3x3 convolutions followed by a stride-2 deconvolution.
        // A 156px input therefore returns the 284px result for the centered 142px tile directly.
        contract = {156, 284, 3, 3, 142, 7, 0};
        return true;
    }
    if (task.modelKind == ModelKind::Luminance) {
        // ESPCN preserves the fixed input extent. Crop the 4px context on each side after 2x output.
        contract = {180, 360, 1, 1, 172, 4, 8};
        return true;
    }
    if (task.modelKind == ModelKind::RealCugan) {
        // Preserve the existing Reader 128 px tile plus 18 px context contract.
        contract = {164, 256, 3, 3, 128, 18, 0};
        return true;
    }
    if (task.modelKind == ModelKind::Waifu2xCunet) {
        // CUNet returns the centered 256 px result for the Reader's 128 px tile plus 18 px context.
        contract = {164, 256, 3, 3, 128, 18, 0};
        return true;
    }
    task.error = "MindSpore NNRT model kind is unsupported";
    return false;
}

std::string SelectMindSporeAccelerator()
{
    size_t count = 0;
    NNRTDeviceDesc *descriptions = OH_AI_GetAllNNRTDeviceDescs(&count);
    if (descriptions == nullptr || count == 0) {
        if (descriptions != nullptr) {
            OH_AI_DestroyAllNNRTDeviceDescs(&descriptions);
        }
        return "";
    }
    std::string fallback;
    std::string preferred;
    for (size_t index = 0; index < count; ++index) {
        NNRTDeviceDesc *description = OH_AI_GetElementOfNNRTDeviceDescs(descriptions, index);
        if (description == nullptr ||
            OH_AI_GetTypeFromNNRTDeviceDesc(description) != OH_AI_NNRTDEVICE_ACCELERATOR) {
            continue;
        }
        const char *name = OH_AI_GetNameFromNNRTDeviceDesc(description);
        if (name == nullptr) {
            continue;
        }
        if (fallback.empty()) {
            fallback = name;
        }
        if (std::string(name).rfind("NPU_", 0) == 0) {
            preferred = name;
            break;
        }
    }
    OH_AI_DestroyAllNNRTDeviceDescs(&descriptions);
    return preferred.empty() ? fallback : preferred;
}

bool ValidateMindSporeInput(
    UpscaleTask &task,
    OH_AI_TensorHandle input,
    const MindSporeContract &contract)
{
    const int64_t expectedElements =
        static_cast<int64_t>(contract.inputSize) * contract.inputSize * contract.inputChannels;
    const size_t expectedBytes = static_cast<size_t>(expectedElements) * sizeof(float);
    if (input == nullptr ||
        OH_AI_TensorGetDataType(input) != OH_AI_DATATYPE_NUMBERTYPE_FLOAT32 ||
        OH_AI_TensorGetFormat(input) != OH_AI_FORMAT_NCHW ||
        OH_AI_TensorGetElementNum(input) != expectedElements ||
        OH_AI_TensorGetDataSize(input) != expectedBytes) {
        task.error = "MindSpore NNRT model has an unexpected input contract";
        return false;
    }
    return true;
}

bool ValidateMindSporeCunetDevice(
    UpscaleTask &task,
    OH_AI_ModelHandle model,
    const OH_AI_TensorHandleArray &inputs,
    const MindSporeContract &contract,
    const std::string &rejectionKey)
{
    if (task.modelKind != ModelKind::Waifu2xCunet) {
        return true;
    }
    auto *inputData = static_cast<float *>(OH_AI_TensorGetMutableData(inputs.handle_list[0]));
    const int64_t inputElements = OH_AI_TensorGetElementNum(inputs.handle_list[0]);
    if (inputData == nullptr || inputElements <= 0) {
        task.error = "MindSpore NNRT CUNet self-test input is unavailable";
        return false;
    }
    for (int64_t index = 0; index < inputElements; ++index) {
        inputData[index] = static_cast<float>(index % 251) / 250.0f;
    }
    OH_AI_TensorHandleArray outputs = {0, nullptr};
    const SteadyClock::time_point startedAt = SteadyClock::now();
    const OH_AI_Status status = OH_AI_ModelPredict(model, inputs, &outputs, nullptr, nullptr);
    const int64_t elapsedMs = ElapsedMilliseconds(startedAt);
    const int64_t expectedElements =
        static_cast<int64_t>(contract.outputSize) * contract.outputSize * contract.outputChannels;
    if (status != OH_AI_STATUS_SUCCESS || outputs.handle_num < 1 || outputs.handle_list == nullptr ||
        outputs.handle_list[0] == nullptr ||
        OH_AI_TensorGetDataType(outputs.handle_list[0]) != OH_AI_DATATYPE_NUMBERTYPE_FLOAT32 ||
        OH_AI_TensorGetElementNum(outputs.handle_list[0]) != expectedElements) {
        gRejectedMindSporeModelDevices.insert(rejectionKey);
        task.error = "MindSpore NNRT CUNet self-test prediction failed";
        return false;
    }
    const auto *outputData = static_cast<const float *>(OH_AI_TensorGetData(outputs.handle_list[0]));
    if (outputData == nullptr) {
        gRejectedMindSporeModelDevices.insert(rejectionKey);
        task.error = "MindSpore NNRT CUNet self-test output is unavailable";
        return false;
    }
    float minimum = outputData[0];
    float maximum = outputData[0];
    for (int64_t index = 1; index < expectedElements; ++index) {
        minimum = std::min(minimum, outputData[index]);
        maximum = std::max(maximum, outputData[index]);
    }
    constexpr size_t probeIndices[] = {
        0, 127, 128, 255, 32768, 65535, 65536,
        65663, 98304, 131071, 131072, 163840, 196607,
    };
    constexpr float probeExpected[] = {
        0.762309f, 0.099176f, 0.123463f, 0.408622f, 0.772172f, 0.436751f,
        0.946322f, 0.259907f, 0.699357f, 0.372145f, 0.241364f, 0.842830f, 0.520484f,
    };
    float maximumProbeError = 0.0f;
    for (size_t index = 0; index < std::size(probeIndices); ++index) {
        maximumProbeError = std::max(
            maximumProbeError,
            std::abs(outputData[probeIndices[index]] - probeExpected[index]));
    }
    const bool valid = std::isfinite(minimum) && std::isfinite(maximum) &&
        minimum > -0.15f && maximum < 1.2f && maximumProbeError < 0.15f;
    OH_LOG_Print(
        LOG_APP,
        valid ? LOG_INFO : LOG_WARN,
        0x0,
        "NextESuperResolution",
        "MindSpore NNRT CUNet self-test valid=%{public}d range=%{public}.6f..%{public}.6f maxProbeError=%{public}.6f elapsedMs=%{public}lld",
        valid ? 1 : 0,
        minimum,
        maximum,
        maximumProbeError,
        static_cast<long long>(elapsedMs));
    if (!valid) {
        gRejectedMindSporeModelDevices.insert(rejectionKey);
        task.error = "MindSpore NNRT CUNet self-test rejected this accelerator";
    }
    return valid;
}

OH_AI_ModelHandle PrepareMindSporeModel(UpscaleTask &task)
{
    MindSporeContract contract;
    if (!ResolveMindSporeContract(task, contract)) {
        return nullptr;
    }
    if (gCachedMindSporeModel != nullptr && gCachedMindSporeModelPath == task.modelPath &&
        gCachedMindSporeModelKind == static_cast<int>(task.modelKind)) {
        task.modelLoadMs = 0;
        task.backend = "nnrt";
        return gCachedMindSporeModel;
    }
    const std::string deviceName = SelectMindSporeAccelerator();
    if (deviceName.empty()) {
        task.error = "NNRT accelerator is unavailable";
        return nullptr;
    }
    const std::string rejectionKey = task.modelPath + "|" + deviceName;
    if (gRejectedMindSporeModelDevices.find(rejectionKey) != gRejectedMindSporeModelDevices.end()) {
        task.error = "MindSpore NNRT model was rejected by the device self-test";
        return nullptr;
    }
    OH_AI_ContextHandle context = OH_AI_ContextCreate();
    OH_AI_DeviceInfoHandle device = OH_AI_CreateNNRTDeviceInfoByName(deviceName.c_str());
    OH_AI_ModelHandle model = OH_AI_ModelCreate();
    if (context == nullptr || device == nullptr || model == nullptr) {
        if (model != nullptr) {
            OH_AI_ModelDestroy(&model);
        }
        if (context != nullptr) {
            OH_AI_ContextDestroy(&context);
        } else if (device != nullptr) {
            OH_AI_DeviceInfoDestroy(&device);
        }
        task.error = "failed to create MindSpore NNRT runtime";
        return nullptr;
    }
    OH_AI_DeviceInfoSetPerformanceMode(device, OH_AI_PERFORMANCE_HIGH);
    OH_AI_DeviceInfoSetPriority(device, OH_AI_PRIORITY_LOW);
    OH_AI_ContextAddDeviceInfo(context, device);
    const SteadyClock::time_point startedAt = SteadyClock::now();
    const OH_AI_Status status = OH_AI_ModelBuildFromFile(
        model,
        task.modelPath.c_str(),
        OH_AI_MODELTYPE_MINDIR,
        context);
    task.modelLoadMs = ElapsedMilliseconds(startedAt);
    OH_AI_ContextDestroy(&context);
    if (status != OH_AI_STATUS_SUCCESS) {
        OH_AI_ModelDestroy(&model);
        task.error = "failed to build MindSpore NNRT model, status=" +
            std::to_string(static_cast<uint32_t>(status));
        return nullptr;
    }
    const OH_AI_TensorHandleArray inputs = OH_AI_ModelGetInputs(model);
    if (inputs.handle_num != 1 || inputs.handle_list == nullptr ||
        !ValidateMindSporeInput(task, inputs.handle_list[0], contract)) {
        OH_AI_ModelDestroy(&model);
        return nullptr;
    }
    if (!ValidateMindSporeCunetDevice(task, model, inputs, contract, rejectionKey)) {
        OH_AI_ModelDestroy(&model);
        return nullptr;
    }
    ResetCachedMindSporeRuntime();
    gCachedMindSporeModel = model;
    gCachedMindSporeModelPath = task.modelPath;
    gCachedMindSporeDeviceName = deviceName;
    gCachedMindSporeModelKind = static_cast<int>(task.modelKind);
    task.backend = "nnrt";
    OH_LOG_Print(
        LOG_APP,
        LOG_INFO,
        0x0,
        "NextESuperResolution",
        "MindSpore NNRT model loaded device=%{public}s elapsedMs=%{public}lld",
        deviceName.c_str(),
        static_cast<long long>(task.modelLoadMs));
    return gCachedMindSporeModel;
}

void PrepareMindSporeTile(
    const UpscaleTask &task,
    const MindSporeContract &contract,
    int inputX,
    int inputY,
    std::vector<float> &tile)
{
    const size_t planeElements =
        static_cast<size_t>(contract.inputSize) * contract.inputSize;
    constexpr float inverseByte = 1.0f / 255.0f;
    if (task.modelKind == ModelKind::Luminance) {
        tile.resize(planeElements);
        for (int localY = 0; localY < contract.inputSize; ++localY) {
            const int sourceY =
                std::clamp(inputY + localY - contract.prepadding, 0, task.height - 1);
            int localX = 0;
#if defined(__aarch64__)
            const int sourceStartX = inputX - contract.prepadding;
            const int contiguousStart = std::max(0, -sourceStartX);
            const int contiguousEnd = std::min(contract.inputSize, task.width - sourceStartX);
            for (; localX < contiguousStart; ++localX) {
                const int sourceX = std::clamp(sourceStartX + localX, 0, task.width - 1);
                const size_t sourceOffset =
                    static_cast<size_t>(sourceY) * task.stride + sourceX * 4;
                const float red = task.input[sourceOffset] * inverseByte;
                const float green = task.input[sourceOffset + 1] * inverseByte;
                const float blue = task.input[sourceOffset + 2] * inverseByte;
                tile[static_cast<size_t>(localY) * contract.inputSize + localX] =
                    (65.481f * red + 128.553f * green + 24.966f * blue + 16.0f) *
                    inverseByte;
            }
            const float32x4_t byteScale = vdupq_n_f32(inverseByte);
            const float32x4_t redWeight = vdupq_n_f32(65.481f);
            const float32x4_t greenWeight = vdupq_n_f32(128.553f);
            const float32x4_t blueWeight = vdupq_n_f32(24.966f);
            const float32x4_t bias = vdupq_n_f32(16.0f);
            for (; localX + 8 <= contiguousEnd; localX += 8) {
                const int sourceX = sourceStartX + localX;
                const size_t sourceOffset =
                    static_cast<size_t>(sourceY) * task.stride + sourceX * 4;
                const uint8x8x4_t rgba = vld4_u8(task.input.data() + sourceOffset);
                const uint16x8_t red16 = vmovl_u8(rgba.val[0]);
                const uint16x8_t green16 = vmovl_u8(rgba.val[1]);
                const uint16x8_t blue16 = vmovl_u8(rgba.val[2]);
                auto convertLuma = [&](uint32x4_t red32, uint32x4_t green32, uint32x4_t blue32) {
                    const float32x4_t red =
                        vmulq_f32(vcvtq_f32_u32(red32), byteScale);
                    const float32x4_t green =
                        vmulq_f32(vcvtq_f32_u32(green32), byteScale);
                    const float32x4_t blue =
                        vmulq_f32(vcvtq_f32_u32(blue32), byteScale);
                    float32x4_t luma = vmlaq_f32(bias, red, redWeight);
                    luma = vmlaq_f32(luma, green, greenWeight);
                    luma = vmlaq_f32(luma, blue, blueWeight);
                    return vmulq_f32(luma, byteScale);
                };
                const size_t tileOffset =
                    static_cast<size_t>(localY) * contract.inputSize + localX;
                vst1q_f32(
                    tile.data() + tileOffset,
                    convertLuma(
                        vmovl_u16(vget_low_u16(red16)),
                        vmovl_u16(vget_low_u16(green16)),
                        vmovl_u16(vget_low_u16(blue16))));
                vst1q_f32(
                    tile.data() + tileOffset + 4,
                    convertLuma(
                        vmovl_u16(vget_high_u16(red16)),
                        vmovl_u16(vget_high_u16(green16)),
                        vmovl_u16(vget_high_u16(blue16))));
            }
#endif
            for (; localX < contract.inputSize; ++localX) {
                const int sourceX =
                    std::clamp(inputX + localX - contract.prepadding, 0, task.width - 1);
                const size_t sourceOffset =
                    static_cast<size_t>(sourceY) * task.stride + sourceX * 4;
                const float red = task.input[sourceOffset] * inverseByte;
                const float green = task.input[sourceOffset + 1] * inverseByte;
                const float blue = task.input[sourceOffset + 2] * inverseByte;
                tile[static_cast<size_t>(localY) * contract.inputSize + localX] =
                    (65.481f * red + 128.553f * green + 24.966f * blue + 16.0f) *
                    inverseByte;
            }
        }
        return;
    }
    tile.resize(planeElements * 3);
    for (int localY = 0; localY < contract.inputSize; ++localY) {
        const int sourceY =
            std::clamp(inputY + localY - contract.prepadding, 0, task.height - 1);
        int localX = 0;
#if defined(__aarch64__)
        const int sourceStartX = inputX - contract.prepadding;
        const int contiguousStart = std::max(0, -sourceStartX);
        const int contiguousEnd = std::min(contract.inputSize, task.width - sourceStartX);
        for (; localX < contiguousStart; ++localX) {
            const int sourceX = std::clamp(sourceStartX + localX, 0, task.width - 1);
            const size_t sourceOffset = static_cast<size_t>(sourceY) * task.stride + sourceX * 4;
            const size_t tileOffset = static_cast<size_t>(localY) * contract.inputSize + localX;
            tile[tileOffset] = task.input[sourceOffset] * inverseByte;
            tile[planeElements + tileOffset] = task.input[sourceOffset + 1] * inverseByte;
            tile[planeElements * 2 + tileOffset] = task.input[sourceOffset + 2] * inverseByte;
        }
        const float32x4_t scale = vdupq_n_f32(inverseByte);
        for (; localX + 8 <= contiguousEnd; localX += 8) {
            const int sourceX = sourceStartX + localX;
            const size_t sourceOffset = static_cast<size_t>(sourceY) * task.stride + sourceX * 4;
            const size_t tileOffset = static_cast<size_t>(localY) * contract.inputSize + localX;
            const uint8x8x4_t rgba = vld4_u8(task.input.data() + sourceOffset);
            const uint16x8_t red16 = vmovl_u8(rgba.val[0]);
            const uint16x8_t green16 = vmovl_u8(rgba.val[1]);
            const uint16x8_t blue16 = vmovl_u8(rgba.val[2]);
            vst1q_f32(
                tile.data() + tileOffset,
                vmulq_f32(vcvtq_f32_u32(vmovl_u16(vget_low_u16(red16))), scale));
            vst1q_f32(
                tile.data() + tileOffset + 4,
                vmulq_f32(vcvtq_f32_u32(vmovl_u16(vget_high_u16(red16))), scale));
            vst1q_f32(
                tile.data() + planeElements + tileOffset,
                vmulq_f32(vcvtq_f32_u32(vmovl_u16(vget_low_u16(green16))), scale));
            vst1q_f32(
                tile.data() + planeElements + tileOffset + 4,
                vmulq_f32(vcvtq_f32_u32(vmovl_u16(vget_high_u16(green16))), scale));
            vst1q_f32(
                tile.data() + planeElements * 2 + tileOffset,
                vmulq_f32(vcvtq_f32_u32(vmovl_u16(vget_low_u16(blue16))), scale));
            vst1q_f32(
                tile.data() + planeElements * 2 + tileOffset + 4,
                vmulq_f32(vcvtq_f32_u32(vmovl_u16(vget_high_u16(blue16))), scale));
        }
#endif
        for (; localX < contract.inputSize; ++localX) {
            const int sourceX =
                std::clamp(inputX + localX - contract.prepadding, 0, task.width - 1);
            const size_t sourceOffset = static_cast<size_t>(sourceY) * task.stride + sourceX * 4;
            const size_t tileOffset = static_cast<size_t>(localY) * contract.inputSize + localX;
            tile[tileOffset] = task.input[sourceOffset] * inverseByte;
            tile[planeElements + tileOffset] = task.input[sourceOffset + 1] * inverseByte;
            tile[planeElements * 2 + tileOffset] = task.input[sourceOffset + 2] * inverseByte;
        }
    }
}

void PrepareBilinearRgbaOutput(UpscaleTask &task)
{
    const int outputWidth = task.width * kScale;
    const int outputHeight = task.height * kScale;
    task.output.resize(static_cast<size_t>(outputWidth) * outputHeight * 4);
    ncnn::resize_bilinear_c4(
        task.input.data(),
        task.width,
        task.height,
        task.stride,
        task.output.data(),
        outputWidth,
        outputHeight,
        outputWidth * 4);
}

struct BilinearAxisSample {
    int first = 0;
    int second = 0;
    int secondWeight = 0;
};

std::vector<BilinearAxisSample> ResolveBilinearAxisSamples(int sourceExtent)
{
    const int outputExtent = sourceExtent * kScale;
    std::vector<BilinearAxisSample> samples(static_cast<size_t>(outputExtent));
    for (int output = 1; output < outputExtent; ++output) {
        const int quarterPosition = output * 2 - 1;
        BilinearAxisSample &sample = samples[static_cast<size_t>(output)];
        sample.first = std::min(quarterPosition / 4, sourceExtent - 1);
        sample.second = std::min(sample.first + 1, sourceExtent - 1);
        sample.secondWeight = quarterPosition % 4;
    }
    return samples;
}

bool ApplyEffectStrength(UpscaleTask &task)
{
    if (task.effectStrengthPercent >= 100) {
        return true;
    }
    const int outputWidth = task.width * kScale;
    const int outputHeight = task.height * kScale;
    const size_t expectedBytes = static_cast<size_t>(outputWidth) * outputHeight * 4;
    if (task.output.size() != expectedBytes) {
        task.error = "super-resolution output is unavailable for effect-strength mixing";
        return false;
    }
    const int sourceStrength = 100 - task.effectStrengthPercent;
    const std::vector<BilinearAxisSample> xSamples = ResolveBilinearAxisSamples(task.width);
    const std::vector<BilinearAxisSample> ySamples = ResolveBilinearAxisSamples(task.height);
    for (int outputY = 0; outputY < outputHeight; ++outputY) {
        if (!EnsureRequestActive(task)) {
            return false;
        }
        const BilinearAxisSample &ySample = ySamples[static_cast<size_t>(outputY)];
        const int topWeight = 4 - ySample.secondWeight;
        const uint8_t *topRow = task.input.data() + static_cast<size_t>(ySample.first) * task.stride;
        const uint8_t *bottomRow =
            task.input.data() + static_cast<size_t>(ySample.second) * task.stride;
        uint8_t *outputRow =
            task.output.data() + static_cast<size_t>(outputY) * outputWidth * 4;
        for (int outputX = 0; outputX < outputWidth; ++outputX) {
            const BilinearAxisSample &xSample = xSamples[static_cast<size_t>(outputX)];
            const int leftWeight = 4 - xSample.secondWeight;
            const size_t leftOffset = static_cast<size_t>(xSample.first) * 4;
            const size_t rightOffset = static_cast<size_t>(xSample.second) * 4;
            const size_t outputOffset = static_cast<size_t>(outputX) * 4;
            for (size_t channel = 0; channel < 3; ++channel) {
                const int top =
                    topRow[leftOffset + channel] * leftWeight +
                    topRow[rightOffset + channel] * xSample.secondWeight;
                const int bottom =
                    bottomRow[leftOffset + channel] * leftWeight +
                    bottomRow[rightOffset + channel] * xSample.secondWeight;
                const int baseline =
                    (top * topWeight + bottom * ySample.secondWeight + 8) / 16;
                outputRow[outputOffset + channel] = static_cast<uint8_t>(
                    (outputRow[outputOffset + channel] * task.effectStrengthPercent +
                        baseline * sourceStrength + 50) /
                    100);
            }
        }
    }
    return true;
}

void WriteMindSporeTile(
    UpscaleTask &task,
    const MindSporeContract &contract,
    const float *tensor,
    int inputX,
    int inputY,
    int tileWidth,
    int tileHeight)
{
    const size_t planeElements =
        static_cast<size_t>(contract.outputSize) * contract.outputSize;
    const int outputWidth = task.width * kScale;
    const int writeWidth = tileWidth * kScale;
    const int writeHeight = tileHeight * kScale;
    const int outputX = inputX * kScale;
    const int outputY = inputY * kScale;
    if (task.modelKind == ModelKind::Luminance) {
        constexpr float inverseByte = 1.0f / 255.0f;
        for (int y = 0; y < writeHeight; ++y) {
            const size_t tensorRow =
                static_cast<size_t>(contract.outputCrop + y) * contract.outputSize +
                contract.outputCrop;
            const int globalY = outputY + y;
            int x = 0;
#if defined(__aarch64__)
            const float32x4_t byteScale = vdupq_n_f32(inverseByte);
            const float32x4_t redWeight = vdupq_n_f32(65.481f);
            const float32x4_t greenWeight = vdupq_n_f32(128.553f);
            const float32x4_t blueWeight = vdupq_n_f32(24.966f);
            const float32x4_t lumaBias = vdupq_n_f32(16.0f);
            const float32x4_t lumaDeltaScale = vdupq_n_f32(255.0f / 219.0f);
            const float32x4_t outputScale = vdupq_n_f32(255.0f);
            const float32x4_t rounding = vdupq_n_f32(0.5f);
            const float32x4_t minimum = vdupq_n_f32(0.0f);
            const float32x4_t maximum = vdupq_n_f32(255.0f);
            for (; x + 8 <= writeWidth; x += 8) {
                const int globalX = outputX + x;
                const size_t targetOffset =
                    (static_cast<size_t>(globalY) * outputWidth + globalX) * 4;
                uint8x8x4_t rgba = vld4_u8(task.output.data() + targetOffset);
                const uint16x8_t red16 = vmovl_u8(rgba.val[0]);
                const uint16x8_t green16 = vmovl_u8(rgba.val[1]);
                const uint16x8_t blue16 = vmovl_u8(rgba.val[2]);
                auto computeDelta = [&](
                    uint32x4_t red32,
                    uint32x4_t green32,
                    uint32x4_t blue32,
                    const float *enhancedLuma) {
                    const float32x4_t red =
                        vmulq_f32(vcvtq_f32_u32(red32), byteScale);
                    const float32x4_t green =
                        vmulq_f32(vcvtq_f32_u32(green32), byteScale);
                    const float32x4_t blue =
                        vmulq_f32(vcvtq_f32_u32(blue32), byteScale);
                    float32x4_t luma = vmlaq_f32(lumaBias, red, redWeight);
                    luma = vmlaq_f32(luma, green, greenWeight);
                    luma = vmulq_f32(vmlaq_f32(luma, blue, blueWeight), byteScale);
                    return vmulq_f32(vsubq_f32(vld1q_f32(enhancedLuma), luma), lumaDeltaScale);
                };
                const float32x4_t lowDelta = computeDelta(
                    vmovl_u16(vget_low_u16(red16)),
                    vmovl_u16(vget_low_u16(green16)),
                    vmovl_u16(vget_low_u16(blue16)),
                    tensor + tensorRow + x);
                const float32x4_t highDelta = computeDelta(
                    vmovl_u16(vget_high_u16(red16)),
                    vmovl_u16(vget_high_u16(green16)),
                    vmovl_u16(vget_high_u16(blue16)),
                    tensor + tensorRow + x + 4);
                auto convertChannel = [&](uint16x8_t channel) {
                    float32x4_t low = vaddq_f32(
                        vmulq_f32(
                            vaddq_f32(
                                vmulq_f32(
                                    vcvtq_f32_u32(vmovl_u16(vget_low_u16(channel))),
                                    byteScale),
                                lowDelta),
                            outputScale),
                        rounding);
                    float32x4_t high = vaddq_f32(
                        vmulq_f32(
                            vaddq_f32(
                                vmulq_f32(
                                    vcvtq_f32_u32(vmovl_u16(vget_high_u16(channel))),
                                    byteScale),
                                highDelta),
                            outputScale),
                        rounding);
                    low = vmaxq_f32(minimum, vminq_f32(maximum, low));
                    high = vmaxq_f32(minimum, vminq_f32(maximum, high));
                    return vmovn_u16(vcombine_u16(
                        vmovn_u32(vcvtq_u32_f32(low)),
                        vmovn_u32(vcvtq_u32_f32(high))));
                };
                rgba.val[0] = convertChannel(red16);
                rgba.val[1] = convertChannel(green16);
                rgba.val[2] = convertChannel(blue16);
                vst4_u8(task.output.data() + targetOffset, rgba);
            }
#endif
            for (; x < writeWidth; ++x) {
                const int globalX = outputX + x;
                const size_t targetOffset =
                    (static_cast<size_t>(globalY) * outputWidth + globalX) * 4;
                const float red = task.output[targetOffset] * inverseByte;
                const float green = task.output[targetOffset + 1] * inverseByte;
                const float blue = task.output[targetOffset + 2] * inverseByte;
                const float sourceLuma =
                    (65.481f * red + 128.553f * green + 24.966f * blue + 16.0f) *
                    (1.0f / 255.0f);
                const float lumaDelta =
                    (tensor[tensorRow + x] - sourceLuma) * (255.0f / 219.0f);
                task.output[targetOffset] = ToByte(red + lumaDelta);
                task.output[targetOffset + 1] = ToByte(green + lumaDelta);
                task.output[targetOffset + 2] = ToByte(blue + lumaDelta);
            }
        }
        return;
    }
    for (int y = 0; y < writeHeight; ++y) {
        const size_t tensorRow =
            static_cast<size_t>(contract.outputCrop + y) * contract.outputSize +
            contract.outputCrop;
        const size_t targetRow =
            (static_cast<size_t>(outputY + y) * outputWidth + outputX) * 4;
        int x = 0;
#if defined(__aarch64__)
        const float32x4_t scale = vdupq_n_f32(255.0f);
        const float32x4_t rounding = vdupq_n_f32(0.5f);
        const float32x4_t minimum = vdupq_n_f32(0.0f);
        const float32x4_t maximum = vdupq_n_f32(255.0f);
        const uint8x8_t alpha = vdup_n_u8(255);
        for (; x + 8 <= writeWidth; x += 8) {
            const size_t tensorOffset = tensorRow + x;
            const size_t targetOffset = targetRow + x * 4;
            auto convertChannel = [&](const float *channel) -> uint8x8_t {
                float32x4_t low = vaddq_f32(vmulq_f32(vld1q_f32(channel), scale), rounding);
                float32x4_t high = vaddq_f32(vmulq_f32(vld1q_f32(channel + 4), scale), rounding);
                low = vmaxq_f32(minimum, vminq_f32(maximum, low));
                high = vmaxq_f32(minimum, vminq_f32(maximum, high));
                return vmovn_u16(vcombine_u16(
                    vmovn_u32(vcvtq_u32_f32(low)),
                    vmovn_u32(vcvtq_u32_f32(high))));
            };
            uint8x8x4_t rgba;
            rgba.val[0] = convertChannel(tensor + tensorOffset);
            rgba.val[1] = convertChannel(tensor + planeElements + tensorOffset);
            rgba.val[2] = convertChannel(tensor + planeElements * 2 + tensorOffset);
            rgba.val[3] = alpha;
            vst4_u8(task.output.data() + targetOffset, rgba);
        }
#endif
        for (; x < writeWidth; ++x) {
            const size_t tensorOffset = tensorRow + x;
            const size_t targetOffset = targetRow + x * 4;
            task.output[targetOffset] = ToByte(tensor[tensorOffset]);
            task.output[targetOffset + 1] = ToByte(tensor[planeElements + tensorOffset]);
            task.output[targetOffset + 2] = ToByte(tensor[planeElements * 2 + tensorOffset]);
            task.output[targetOffset + 3] = 255;
        }
    }
}

bool ValidateTask(UpscaleTask &task);

bool RunMindSporeUpscale(UpscaleTask &task)
{
    if (!ValidateTask(task)) {
        return false;
    }
    std::lock_guard<std::mutex> lock(gMindSporeMutex);
    MindSporeContract contract;
    if (!ResolveMindSporeContract(task, contract)) {
        return false;
    }
    OH_AI_ModelHandle model = PrepareMindSporeModel(task);
    if (model == nullptr) {
        return false;
    }
    const OH_AI_TensorHandleArray inputs = OH_AI_ModelGetInputs(model);
    if (inputs.handle_num != 1 || inputs.handle_list == nullptr ||
        !ValidateMindSporeInput(task, inputs.handle_list[0], contract)) {
        return false;
    }
    const size_t outputBytes = static_cast<size_t>(task.width) * kScale * task.height * kScale * 4;
    if (task.modelKind == ModelKind::Luminance) {
        PrepareBilinearRgbaOutput(task);
    } else {
        task.output.assign(outputBytes, 255);
    }
    std::vector<float> tile;
    for (int inputY = 0; inputY < task.height; inputY += contract.tileSize) {
        const int tileHeight = std::min(contract.tileSize, task.height - inputY);
        for (int inputX = 0; inputX < task.width; inputX += contract.tileSize) {
            if (!WaitUntilInferenceAllowed(task)) {
                return false;
            }
            const int tileWidth = std::min(contract.tileSize, task.width - inputX);
            PrepareMindSporeTile(task, contract, inputX, inputY, tile);
            void *inputData = OH_AI_TensorGetMutableData(inputs.handle_list[0]);
            if (inputData == nullptr) {
                task.error = "MindSpore NNRT input buffer is unavailable";
                return false;
            }
            std::memcpy(inputData, tile.data(), tile.size() * sizeof(float));
            OH_AI_TensorHandleArray outputs = {0, nullptr};
            const SteadyClock::time_point predictionStartedAt = SteadyClock::now();
            const OH_AI_Status status = OH_AI_ModelPredict(model, inputs, &outputs, nullptr, nullptr);
            task.inferenceMs += ElapsedMilliseconds(predictionStartedAt);
            if (status != OH_AI_STATUS_SUCCESS || outputs.handle_num < 1 || outputs.handle_list == nullptr) {
                task.error = "MindSpore NNRT prediction failed, status=" +
                    std::to_string(static_cast<uint32_t>(status));
                return false;
            }
            OH_AI_TensorHandle output = outputs.handle_list[0];
            const int64_t expectedElements =
                static_cast<int64_t>(contract.outputSize) * contract.outputSize *
                contract.outputChannels;
            const size_t expectedBytes = static_cast<size_t>(expectedElements) * sizeof(float);
            if (output == nullptr ||
                OH_AI_TensorGetDataType(output) != OH_AI_DATATYPE_NUMBERTYPE_FLOAT32 ||
                OH_AI_TensorGetFormat(output) != OH_AI_FORMAT_NCHW ||
                OH_AI_TensorGetElementNum(output) != expectedElements ||
                OH_AI_TensorGetDataSize(output) != expectedBytes) {
                task.error = "MindSpore NNRT model returned an unexpected output contract";
                return false;
            }
            const auto *outputData = static_cast<const float *>(OH_AI_TensorGetData(output));
            if (outputData == nullptr) {
                task.error = "MindSpore NNRT output buffer is unavailable";
                return false;
            }
            WriteMindSporeTile(
                task,
                contract,
                outputData,
                inputX,
                inputY,
                tileWidth,
                tileHeight);
            task.tileCount += 1;
        }
    }
    task.backend = "nnrt";
    return true;
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
    if (task.effectStrengthPercent < 0 || task.effectStrengthPercent > 100) {
        task.error = "invalid super-resolution effect strength";
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
    PrepareBilinearRgbaOutput(task);
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
                    const size_t offset =
                        (static_cast<size_t>(globalY) * outputWidth + globalX) * 4;
                    constexpr float inverseByte = 1.0f / 255.0f;
                    const float red = task.output[offset] * inverseByte;
                    const float green = task.output[offset + 1] * inverseByte;
                    const float blue = task.output[offset + 2] * inverseByte;
                    const float sourceLuma =
                        (65.481f * red + 128.553f * green + 24.966f * blue + 16.0f) *
                        (1.0f / 255.0f);
                    const float lumaDelta = (enhancedLuma[x] - sourceLuma) * (255.0f / 219.0f);
                    task.output[offset] = ToByte(red + lumaDelta);
                    task.output[offset + 1] = ToByte(green + lumaDelta);
                    task.output[offset + 2] = ToByte(blue + lumaDelta);
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

bool RunMindSporePrepare(UpscaleTask &task)
{
    WaitUntilPreparationAllowed();
    std::lock_guard<std::mutex> lock(gMindSporeMutex);
    return PrepareMindSporeModel(task) != nullptr;
}

constexpr int kComicDetectorInputSize = 640;
constexpr int kComicDetectorClassCount = 5;
constexpr size_t kComicDetectorMaxRegions = 512;

void ResetCachedComicDetector()
{
    gCachedComicDetectorNet.reset();
    gCachedComicDetectorKey.clear();
}

bool ValidateComicDetectorTask(ComicRegionDetectionTask &task)
{
    if (task.width <= 0 || task.height <= 0 || task.width > 32768 || task.height > 32768 ||
        task.stride < task.width * 4 || task.threads < 1 || task.threads > 8 ||
        task.paramPath.empty() || task.modelPath.empty() ||
        task.confidenceThreshold <= 0.0f || task.confidenceThreshold >= 1.0f) {
        task.error = "invalid comic region detector configuration";
        return false;
    }
    const size_t required = static_cast<size_t>(task.stride) * static_cast<size_t>(task.height);
    if (required == 0 || task.input.size() < required) {
        task.error = "comic region detector RGBA input is truncated";
        return false;
    }
    return true;
}

ncnn::Net *PrepareComicDetector(ComicRegionDetectionTask &task)
{
    const std::string key = task.paramPath + "\n" + task.modelPath + "\n" +
        std::to_string(task.threads);
    if (gCachedComicDetectorNet != nullptr && gCachedComicDetectorKey == key) {
        return gCachedComicDetectorNet.get();
    }
    ResetCachedComicDetector();
    auto net = std::make_unique<ncnn::Net>();
    net->opt.use_vulkan_compute = false;
    // This converted OBB model is numerically unstable with ncnn's default fp16 storage on ARM.
    // Keep the first distributable profile on the parity-tested fp32 path.
    net->opt.use_fp16_storage = false;
    net->opt.use_fp16_packed = false;
    net->opt.use_fp16_arithmetic = false;
    net->opt.use_packing_layout = false;
    net->opt.num_threads = task.threads;
    const SteadyClock::time_point startedAt = SteadyClock::now();
    if (net->load_param(task.paramPath.c_str()) != 0 ||
        net->load_model(task.modelPath.c_str()) != 0) {
        task.error = "failed to load comic region detector model";
        return nullptr;
    }
    task.modelLoadMs = ElapsedMilliseconds(startedAt);
    gCachedComicDetectorKey = key;
    gCachedComicDetectorNet = std::move(net);
    return gCachedComicDetectorNet.get();
}

float ComicRegionAxisIou(const ComicRegionDetection &left, const ComicRegionDetection &right)
{
    float leftMinX = left.points[0];
    float leftMaxX = left.points[0];
    float leftMinY = left.points[1];
    float leftMaxY = left.points[1];
    float rightMinX = right.points[0];
    float rightMaxX = right.points[0];
    float rightMinY = right.points[1];
    float rightMaxY = right.points[1];
    for (int point = 1; point < 4; ++point) {
        leftMinX = std::min(leftMinX, left.points[point * 2]);
        leftMaxX = std::max(leftMaxX, left.points[point * 2]);
        leftMinY = std::min(leftMinY, left.points[point * 2 + 1]);
        leftMaxY = std::max(leftMaxY, left.points[point * 2 + 1]);
        rightMinX = std::min(rightMinX, right.points[point * 2]);
        rightMaxX = std::max(rightMaxX, right.points[point * 2]);
        rightMinY = std::min(rightMinY, right.points[point * 2 + 1]);
        rightMaxY = std::max(rightMaxY, right.points[point * 2 + 1]);
    }
    const float intersectionWidth = std::max(
        0.0f,
        std::min(leftMaxX, rightMaxX) - std::max(leftMinX, rightMinX));
    const float intersectionHeight = std::max(
        0.0f,
        std::min(leftMaxY, rightMaxY) - std::max(leftMinY, rightMinY));
    const float intersection = intersectionWidth * intersectionHeight;
    const float leftArea = std::max(0.0f, leftMaxX - leftMinX) *
        std::max(0.0f, leftMaxY - leftMinY);
    const float rightArea = std::max(0.0f, rightMaxX - rightMinX) *
        std::max(0.0f, rightMaxY - rightMinY);
    const float unionArea = leftArea + rightArea - intersection;
    return unionArea > 0.0f ? intersection / unionArea : 0.0f;
}

void DeduplicateComicRegions(std::vector<ComicRegionDetection> &regions)
{
    std::sort(
        regions.begin(),
        regions.end(),
        [](const ComicRegionDetection &left, const ComicRegionDetection &right) {
            return left.score > right.score;
        });
    std::vector<ComicRegionDetection> accepted;
    accepted.reserve(std::min(regions.size(), kComicDetectorMaxRegions));
    for (const ComicRegionDetection &candidate : regions) {
        float candidateCenterX = 0.0f;
        float candidateCenterY = 0.0f;
        for (int point = 0; point < 4; ++point) {
            candidateCenterX += candidate.points[point * 2] * 0.25f;
            candidateCenterY += candidate.points[point * 2 + 1] * 0.25f;
        }
        bool duplicate = false;
        for (const ComicRegionDetection &existing : accepted) {
            float existingCenterX = 0.0f;
            float existingCenterY = 0.0f;
            for (int point = 0; point < 4; ++point) {
                existingCenterX += existing.points[point * 2] * 0.25f;
                existingCenterY += existing.points[point * 2 + 1] * 0.25f;
            }
            const float distance = std::hypot(
                candidateCenterX - existingCenterX,
                candidateCenterY - existingCenterY);
            if ((candidate.classId == existing.classId && distance < 10.0f) ||
                ComicRegionAxisIou(candidate, existing) > 0.3f) {
                duplicate = true;
                break;
            }
        }
        if (!duplicate) {
            accepted.push_back(candidate);
            if (accepted.size() >= kComicDetectorMaxRegions) {
                break;
            }
        }
    }
    regions.swap(accepted);
}

bool RunComicRegionDetection(ComicRegionDetectionTask &task)
{
    if (!ValidateComicDetectorTask(task)) {
        return false;
    }
    std::lock_guard<std::mutex> lock(gComicDetectorMutex);
    ncnn::Net *net = PrepareComicDetector(task);
    if (net == nullptr) {
        return false;
    }
    const float gain = std::min(
        static_cast<float>(kComicDetectorInputSize) / static_cast<float>(task.height),
        static_cast<float>(kComicDetectorInputSize) / static_cast<float>(task.width));
    const int resizedWidth = std::max(1, static_cast<int>(std::round(task.width * gain)));
    const int resizedHeight = std::max(1, static_cast<int>(std::round(task.height * gain)));
    const int left = (kComicDetectorInputSize - resizedWidth) / 2;
    const int right = kComicDetectorInputSize - resizedWidth - left;
    const int top = (kComicDetectorInputSize - resizedHeight) / 2;
    const int bottom = kComicDetectorInputSize - resizedHeight - top;
    ncnn::Mat resized = ncnn::Mat::from_pixels_resize(
        task.input.data(),
        ncnn::Mat::PIXEL_RGBA2RGB,
        task.width,
        task.height,
        task.stride,
        resizedWidth,
        resizedHeight);
    if (resized.empty()) {
        task.error = "failed to resize comic detector input";
        return false;
    }
    ncnn::Mat input;
    ncnn::copy_make_border(
        resized,
        input,
        top,
        bottom,
        left,
        right,
        ncnn::BORDER_CONSTANT,
        114.0f,
        net->opt);
    if (input.empty() || input.w != kComicDetectorInputSize ||
        input.h != kComicDetectorInputSize || input.c != 3) {
        task.error = "comic detector letterbox preprocessing failed";
        return false;
    }
    const float normalize[3] = {1.0f / 255.0f, 1.0f / 255.0f, 1.0f / 255.0f};
    input.substract_mean_normalize(nullptr, normalize);
    const SteadyClock::time_point startedAt = SteadyClock::now();
    MmapNcnnAllocator blobAllocator;
    MmapNcnnAllocator workspaceAllocator;
    ncnn::Extractor extractor = net->create_extractor();
    extractor.set_light_mode(true);
    extractor.set_blob_allocator(&blobAllocator);
    extractor.set_workspace_allocator(&workspaceAllocator);
    if (extractor.input("in0", input) != 0) {
        task.error = "comic detector rejected the input tensor";
        return false;
    }
    ncnn::Mat output;
    if (extractor.extract("out0", output) != 0) {
        task.error = "comic detector failed to infer output";
        return false;
    }
    task.inferenceMs = ElapsedMilliseconds(startedAt);
    if (output.dims != 2 || output.w != 8400 || output.h != 11 || output.elempack != 1) {
        task.error = "comic detector returned an unexpected output shape";
        ResetCachedComicDetector();
        return false;
    }
    const float inverseGain = 1.0f / gain;
    const float *centerXs = output.row(0);
    const float *centerYs = output.row(1);
    const float *widths = output.row(2);
    const float *heights = output.row(3);
    const float *angles = output.row(10);
    task.regions.clear();
    for (int candidate = 0; candidate < output.w; ++candidate) {
        int classId = 0;
        float score = output.row(4)[candidate];
        for (int classIndex = 1; classIndex < kComicDetectorClassCount; ++classIndex) {
            const float classScore = output.row(4 + classIndex)[candidate];
            if (classScore > score) {
                score = classScore;
                classId = classIndex;
            }
        }
        if (score <= task.confidenceThreshold) {
            continue;
        }
        const float centerX = std::clamp(
            (centerXs[candidate] - static_cast<float>(left)) * inverseGain,
            0.0f,
            static_cast<float>(task.width));
        const float centerY = std::clamp(
            (centerYs[candidate] - static_cast<float>(top)) * inverseGain,
            0.0f,
            static_cast<float>(task.height));
        const float width = widths[candidate] * inverseGain;
        const float height = heights[candidate] * inverseGain;
        const float cosine = std::cos(angles[candidate]);
        const float sine = std::sin(angles[candidate]);
        const float vector1X = width * 0.5f * cosine;
        const float vector1Y = width * 0.5f * sine;
        const float vector2X = -height * 0.5f * sine;
        const float vector2Y = height * 0.5f * cosine;
        ComicRegionDetection region;
        region.classId = classId;
        region.score = score;
        const float corners[8] = {
            centerX + vector1X + vector2X, centerY + vector1Y + vector2Y,
            centerX + vector1X - vector2X, centerY + vector1Y - vector2Y,
            centerX - vector1X - vector2X, centerY - vector1Y - vector2Y,
            centerX - vector1X + vector2X, centerY - vector1Y + vector2Y,
        };
        for (int coordinate = 0; coordinate < 8; coordinate += 2) {
            region.points[coordinate] = std::clamp(
                corners[coordinate], 0.0f, static_cast<float>(task.width));
            region.points[coordinate + 1] = std::clamp(
                corners[coordinate + 1], 0.0f, static_cast<float>(task.height));
        }
        task.regions.push_back(region);
    }
    DeduplicateComicRegions(task.regions);
    return true;
}

void ExecuteComicRegionDetection(napi_env env, void *data)
{
    (void)env;
    auto *task = static_cast<ComicRegionDetectionTask *>(data);
    RunComicRegionDetection(*task);
    std::vector<uint8_t>().swap(task->input);
}

constexpr int kComicRecognizerInputHeight = 48;
constexpr int kComicRecognizerInputWidth = 320;
constexpr int kComicRecognizerTimeSteps = 40;
constexpr int kComicRecognizerCharacters = 18385;

void ResetCachedComicRecognizer()
{
    gCachedComicRecognizerNet.reset();
    gCachedComicRecognizerKey.clear();
    gCachedComicRecognizerDictionary.clear();
}

bool ValidateComicRecognizerTask(ComicTextRecognitionTask &task)
{
    if (task.width <= 0 || task.height <= 0 || task.width > 4096 || task.height > 4096 ||
        task.stride < task.width * 4 || task.threads < 1 || task.threads > 8 ||
        task.paramPath.empty() || task.modelPath.empty() || task.dictionaryPath.empty()) {
        task.error = "invalid comic text recognizer configuration";
        return false;
    }
    const size_t required = static_cast<size_t>(task.stride) * static_cast<size_t>(task.height);
    if (required == 0 || task.input.size() < required) {
        task.error = "comic text recognizer RGBA input is truncated";
        return false;
    }
    return true;
}

bool LoadComicRecognizerDictionary(const std::string &path, std::vector<std::string> &output)
{
    std::ifstream stream(path);
    if (!stream.is_open()) {
        return false;
    }
    output.clear();
    output.reserve(kComicRecognizerCharacters);
    output.push_back("");
    std::string line;
    while (std::getline(stream, line)) {
        if (!line.empty() && line.back() == '\r') {
            line.pop_back();
        }
        output.push_back(line);
    }
    output.push_back(" ");
    return output.size() == kComicRecognizerCharacters;
}

ncnn::Net *PrepareComicRecognizer(ComicTextRecognitionTask &task)
{
    const std::string key = task.paramPath + "\n" + task.modelPath + "\n" +
        task.dictionaryPath + "\n" + std::to_string(task.threads);
    if (gCachedComicRecognizerNet != nullptr && gCachedComicRecognizerKey == key &&
        gCachedComicRecognizerDictionary.size() == kComicRecognizerCharacters) {
        return gCachedComicRecognizerNet.get();
    }
    ResetCachedComicRecognizer();
    std::vector<std::string> dictionary;
    if (!LoadComicRecognizerDictionary(task.dictionaryPath, dictionary)) {
        task.error = "failed to load comic text recognizer dictionary";
        return nullptr;
    }
    auto net = std::make_unique<ncnn::Net>();
    net->opt.use_vulkan_compute = false;
    net->opt.use_fp16_storage = false;
    net->opt.use_fp16_packed = false;
    net->opt.use_fp16_arithmetic = false;
    net->opt.use_packing_layout = false;
    net->opt.num_threads = task.threads;
    const SteadyClock::time_point startedAt = SteadyClock::now();
    if (net->load_param(task.paramPath.c_str()) != 0 ||
        net->load_model(task.modelPath.c_str()) != 0) {
        task.error = "failed to load comic text recognizer model";
        return nullptr;
    }
    task.modelLoadMs = ElapsedMilliseconds(startedAt);
    gCachedComicRecognizerKey = key;
    gCachedComicRecognizerDictionary = std::move(dictionary);
    gCachedComicRecognizerNet = std::move(net);
    return gCachedComicRecognizerNet.get();
}

void RotateComicRecognizerInputCounterClockwise(
    const ComicTextRecognitionTask &task,
    std::vector<uint8_t> &output)
{
    output.resize(static_cast<size_t>(task.width) * static_cast<size_t>(task.height) * 4);
    const int outputWidth = task.height;
    for (int y = 0; y < task.height; ++y) {
        for (int x = 0; x < task.width; ++x) {
            const size_t source = static_cast<size_t>(y) * static_cast<size_t>(task.stride) +
                static_cast<size_t>(x) * 4;
            const int outputX = y;
            const int outputY = task.width - 1 - x;
            const size_t destination =
                (static_cast<size_t>(outputY) * static_cast<size_t>(outputWidth) +
                    static_cast<size_t>(outputX)) * 4;
            std::memcpy(output.data() + destination, task.input.data() + source, 4);
        }
    }
}

bool RunComicTextRecognition(ComicTextRecognitionTask &task)
{
    if (!ValidateComicRecognizerTask(task)) {
        return false;
    }
    std::lock_guard<std::mutex> lock(gComicRecognizerMutex);
    ncnn::Net *net = PrepareComicRecognizer(task);
    if (net == nullptr) {
        return false;
    }
    const SteadyClock::time_point preprocessingStartedAt = SteadyClock::now();
    std::vector<uint8_t> rotated;
    const uint8_t *source = task.input.data();
    int sourceWidth = task.width;
    int sourceHeight = task.height;
    int sourceStride = task.stride;
    if (task.rotateCounterClockwise) {
        RotateComicRecognizerInputCounterClockwise(task, rotated);
        source = rotated.data();
        sourceWidth = task.height;
        sourceHeight = task.width;
        sourceStride = sourceWidth * 4;
    }
    const int resizedWidth = std::clamp(
        static_cast<int>(std::ceil(
            static_cast<float>(kComicRecognizerInputHeight) *
            static_cast<float>(sourceWidth) / static_cast<float>(sourceHeight))),
        1,
        kComicRecognizerInputWidth);
    ncnn::Mat resized = ncnn::Mat::from_pixels_resize(
        source,
        ncnn::Mat::PIXEL_RGBA2BGR,
        sourceWidth,
        sourceHeight,
        sourceStride,
        resizedWidth,
        kComicRecognizerInputHeight);
    if (resized.empty()) {
        task.error = "failed to resize comic text recognizer input";
        return false;
    }
    const float mean[3] = {127.5f, 127.5f, 127.5f};
    const float normalize[3] = {1.0f / 127.5f, 1.0f / 127.5f, 1.0f / 127.5f};
    resized.substract_mean_normalize(mean, normalize);
    ncnn::Mat input;
    ncnn::copy_make_border(
        resized,
        input,
        0,
        0,
        0,
        kComicRecognizerInputWidth - resizedWidth,
        ncnn::BORDER_CONSTANT,
        0.0f,
        net->opt);
    if (input.empty() || input.w != kComicRecognizerInputWidth ||
        input.h != kComicRecognizerInputHeight || input.c != 3) {
        task.error = "comic text recognizer preprocessing failed";
        return false;
    }
    task.preprocessingMs = ElapsedMilliseconds(preprocessingStartedAt);
    const SteadyClock::time_point inferenceStartedAt = SteadyClock::now();
    ncnn::Extractor extractor = net->create_extractor();
    if (extractor.input("in0", input) != 0) {
        task.error = "comic text recognizer rejected the input tensor";
        return false;
    }
    ncnn::Mat output;
    if (extractor.extract("out0", output) != 0) {
        task.error = "comic text recognizer failed to infer output";
        return false;
    }
    task.inferenceMs = ElapsedMilliseconds(inferenceStartedAt);
    if (output.dims != 2 || output.w != kComicRecognizerCharacters ||
        output.h != kComicRecognizerTimeSteps || output.elempack != 1) {
        task.error = "comic text recognizer returned an unexpected output shape";
        ResetCachedComicRecognizer();
        return false;
    }
    const SteadyClock::time_point decodingStartedAt = SteadyClock::now();
    int previous = -1;
    float confidence = 0.0f;
    int selected = 0;
    task.text.clear();
    for (int step = 0; step < output.h; ++step) {
        const float *values = output.row(step);
        int best = 0;
        float bestScore = values[0];
        for (int character = 1; character < output.w; ++character) {
            if (values[character] > bestScore) {
                best = character;
                bestScore = values[character];
            }
        }
        if (best != previous && best != 0) {
            task.text += gCachedComicRecognizerDictionary[best];
            confidence += bestScore;
            ++selected;
        }
        previous = best;
    }
    task.score = selected > 0 ? confidence / static_cast<float>(selected) : 0.0f;
    task.decodingMs = ElapsedMilliseconds(decodingStartedAt);
    return true;
}

void ExecuteComicTextRecognition(napi_env env, void *data)
{
    (void)env;
    auto *task = static_cast<ComicTextRecognitionTask *>(data);
    RunComicTextRecognition(*task);
    std::vector<uint8_t>().swap(task->input);
}

constexpr int kComicTextMaskInputSize = 1024;

void ResetCachedComicTextMask()
{
    gCachedComicTextMaskNet.reset();
    gCachedComicTextMaskKey.clear();
}

bool ValidateComicTextMaskTask(ComicTextMaskTask &task)
{
    if (task.width <= 1 || task.height <= 1 || task.width > 2048 || task.height > 2048 ||
        task.stride < task.width * 4 || task.threads < 1 || task.threads > 8 ||
        task.paramPath.empty() || task.modelPath.empty() ||
        task.threshold <= 0.0f || task.threshold >= 1.0f ||
        task.secondaryThreshold < 0.0f || task.secondaryThreshold >= 1.0f ||
        (task.secondaryThreshold > 0.0f && task.secondaryThreshold <= task.threshold)) {
        task.error = "invalid comic text mask configuration";
        return false;
    }
    const size_t required = static_cast<size_t>(task.stride) * static_cast<size_t>(task.height);
    if (required == 0 || task.input.size() < required) {
        task.error = "comic text mask input is truncated";
        return false;
    }
    return true;
}

ncnn::Net *PrepareComicTextMask(ComicTextMaskTask &task)
{
    const std::string key = task.paramPath + "\n" + task.modelPath + "\n" +
        std::to_string(task.threads);
    if (gCachedComicTextMaskNet != nullptr && gCachedComicTextMaskKey == key) {
        return gCachedComicTextMaskNet.get();
    }
    ResetCachedComicTextMask();
    auto net = std::make_unique<ncnn::Net>();
    net->opt.use_vulkan_compute = false;
    net->opt.use_fp16_storage = true;
    net->opt.use_fp16_packed = true;
    net->opt.use_fp16_arithmetic = true;
    net->opt.use_packing_layout = true;
    net->opt.num_threads = task.threads;
    const SteadyClock::time_point startedAt = SteadyClock::now();
    if (net->load_param(task.paramPath.c_str()) != 0 ||
        net->load_model(task.modelPath.c_str()) != 0) {
        task.error = "failed to load comic text mask model";
        return nullptr;
    }
    task.modelLoadMs = ElapsedMilliseconds(startedAt);
    gCachedComicTextMaskKey = key;
    gCachedComicTextMaskNet = std::move(net);
    return gCachedComicTextMaskNet.get();
}

bool RunComicTextMask(ComicTextMaskTask &task)
{
    if (!ValidateComicTextMaskTask(task)) {
        return false;
    }
    std::lock_guard<std::mutex> lock(gComicTextMaskMutex);
    ncnn::Net *net = PrepareComicTextMask(task);
    if (net == nullptr) {
        return false;
    }
    const SteadyClock::time_point preprocessingStartedAt = SteadyClock::now();
    // Match comic-text-detector's CPU ONNX preprocessing: preserve aspect ratio, place the
    // resized RGB image at the top-left of a 1024 square, and zero-pad only right/bottom.
    const float gain = std::min(
        static_cast<float>(kComicTextMaskInputSize) / static_cast<float>(task.width),
        static_cast<float>(kComicTextMaskInputSize) / static_cast<float>(task.height));
    const int resizedWidth = std::max(1, static_cast<int>(std::round(task.width * gain)));
    const int resizedHeight = std::max(1, static_cast<int>(std::round(task.height * gain)));
    const int right = kComicTextMaskInputSize - resizedWidth;
    const int bottom = kComicTextMaskInputSize - resizedHeight;
    const int pixelConversion = task.inputBgra ?
        ncnn::Mat::PIXEL_BGRA2RGB : ncnn::Mat::PIXEL_RGBA2RGB;
    ncnn::Mat resized = ncnn::Mat::from_pixels_resize(
        task.input.data(),
        pixelConversion,
        task.width,
        task.height,
        task.stride,
        resizedWidth,
        resizedHeight);
    if (resized.empty()) {
        task.error = "failed to resize comic text mask input";
        return false;
    }
    ncnn::Mat input;
    ncnn::copy_make_border(
        resized,
        input,
        0,
        bottom,
        0,
        right,
        ncnn::BORDER_CONSTANT,
        0.0f,
        net->opt);
    if (input.empty() || input.w != kComicTextMaskInputSize ||
        input.h != kComicTextMaskInputSize || input.c != 3) {
        task.error = "comic text mask preprocessing failed";
        return false;
    }
    const float normalize[3] = {1.0f / 255.0f, 1.0f / 255.0f, 1.0f / 255.0f};
    input.substract_mean_normalize(nullptr, normalize);
    task.preprocessingMs = ElapsedMilliseconds(preprocessingStartedAt);
    const SteadyClock::time_point startedAt = SteadyClock::now();
    MmapNcnnAllocator blobAllocator;
    MmapNcnnAllocator workspaceAllocator;
    ncnn::Extractor extractor = net->create_extractor();
    extractor.set_light_mode(true);
    extractor.set_blob_allocator(&blobAllocator);
    extractor.set_workspace_allocator(&workspaceAllocator);
    if (extractor.input("in0", input) != 0) {
        task.error = "comic text mask model rejected the input tensor";
        return false;
    }
    ncnn::Mat output;
    if (extractor.extract("out0", output) != 0) {
        task.error = "comic text mask model failed to infer output";
        return false;
    }
    task.inferenceMs = ElapsedMilliseconds(startedAt);
    if (output.dims != 3 || output.w != kComicTextMaskInputSize ||
        output.h != kComicTextMaskInputSize || output.c != 1 || output.elempack != 1) {
        task.error = "comic text mask model returned an unexpected output shape";
        ResetCachedComicTextMask();
        return false;
    }
    const SteadyClock::time_point postprocessingStartedAt = SteadyClock::now();
    ncnn::Mat cropped;
    ncnn::copy_cut_border(output, cropped, 0, bottom, 0, right, net->opt);
    ncnn::Mat restored;
    ncnn::resize_bilinear(cropped, restored, task.width, task.height, net->opt);
    if (restored.empty() || restored.w != task.width || restored.h != task.height ||
        restored.c != 1 || restored.elempack != 1) {
        task.error = "comic text mask postprocessing failed";
        return false;
    }
    task.mask.assign(
        static_cast<size_t>(task.width) * static_cast<size_t>(task.height),
        0);
    if (task.secondaryThreshold > 0.0f) {
        task.secondaryMask.assign(
            static_cast<size_t>(task.width) * static_cast<size_t>(task.height),
            0);
    }
    for (int y = 0; y < task.height; ++y) {
        const float *row = restored.row(y);
        for (int x = 0; x < task.width; ++x) {
            const size_t index = static_cast<size_t>(y) * static_cast<size_t>(task.width) +
                static_cast<size_t>(x);
            if (row[x] >= task.threshold) {
                task.mask[index] = 1;
                ++task.maskedPixels;
            }
            if (task.secondaryThreshold > 0.0f && row[x] >= task.secondaryThreshold) {
                task.secondaryMask[index] = 1;
                ++task.secondaryMaskedPixels;
            }
        }
    }
    task.postprocessingMs = ElapsedMilliseconds(postprocessingStartedAt);
    return true;
}

void ExecuteComicTextMask(napi_env env, void *data)
{
    (void)env;
    auto *task = static_cast<ComicTextMaskTask *>(data);
    RunComicTextMask(*task);
    std::vector<uint8_t>().swap(task->input);
}

constexpr int kComicInpainterInputAlignment = 8;
constexpr int kComicInpainterMaxInferenceEdge = 256;

void ResetCachedComicInpainter()
{
    gCachedComicInpainterNet.reset();
    gCachedComicInpainterKey.clear();
}

bool ValidateComicInpainterTask(ComicInpaintingTask &task)
{
    if (task.width <= 1 || task.height <= 1 || task.width > 1024 || task.height > 1024 ||
        task.stride < task.width * 4 || task.threads < 1 || task.threads > 8 ||
        task.paramPath.empty() || task.modelPath.empty()) {
        task.error = "invalid comic inpainter configuration";
        return false;
    }
    const size_t requiredPixels =
        static_cast<size_t>(task.stride) * static_cast<size_t>(task.height);
    const size_t requiredMask =
        static_cast<size_t>(task.width) * static_cast<size_t>(task.height);
    if (requiredPixels == 0 || task.input.size() < requiredPixels ||
        requiredMask == 0 || task.mask.size() < requiredMask) {
        task.error = "comic inpainter input is truncated";
        return false;
    }
    return true;
}

ncnn::Net *PrepareComicInpainter(ComicInpaintingTask &task)
{
    const std::string key = task.paramPath + "\n" + task.modelPath + "\n" +
        std::to_string(task.threads);
    if (gCachedComicInpainterNet != nullptr && gCachedComicInpainterKey == key) {
        return gCachedComicInpainterNet.get();
    }
    ResetCachedComicInpainter();
    auto net = std::make_unique<ncnn::Net>();
    net->opt.use_vulkan_compute = false;
    net->opt.use_fp16_storage = false;
    net->opt.use_fp16_packed = false;
    net->opt.use_fp16_arithmetic = false;
    net->opt.use_packing_layout = false;
    net->opt.num_threads = task.threads;
    const SteadyClock::time_point startedAt = SteadyClock::now();
    if (net->load_param(task.paramPath.c_str()) != 0 ||
        net->load_model(task.modelPath.c_str()) != 0) {
        task.error = "failed to load comic inpainter model";
        return nullptr;
    }
    task.modelLoadMs = ElapsedMilliseconds(startedAt);
    gCachedComicInpainterKey = key;
    gCachedComicInpainterNet = std::move(net);
    return gCachedComicInpainterNet.get();
}

bool RunComicInpainting(ComicInpaintingTask &task)
{
    if (!ValidateComicInpainterTask(task)) {
        return false;
    }
    size_t maskedPixels = 0;
    for (size_t index = 0;
        index < static_cast<size_t>(task.width) * static_cast<size_t>(task.height);
        ++index) {
        if (task.mask[index] != 0) {
            ++maskedPixels;
        }
    }
    task.output = task.input;
    if (maskedPixels == 0) {
        return true;
    }

    std::lock_guard<std::mutex> lock(gComicInpainterMutex);
    ncnn::Net *net = PrepareComicInpainter(task);
    if (net == nullptr) {
        return false;
    }
    const SteadyClock::time_point preprocessingStartedAt = SteadyClock::now();
    int inferenceWidth = task.width;
    int inferenceHeight = task.height;
    const int sourceMaxEdge = std::max(task.width, task.height);
    if (sourceMaxEdge > kComicInpainterMaxInferenceEdge) {
        const float scale = static_cast<float>(kComicInpainterMaxInferenceEdge) /
            static_cast<float>(sourceMaxEdge);
        inferenceWidth = std::max(2, static_cast<int>(std::round(task.width * scale)));
        inferenceHeight = std::max(2, static_cast<int>(std::round(task.height * scale)));
    }
    const int paddedWidth =
        ((inferenceWidth + kComicInpainterInputAlignment - 1) /
            kComicInpainterInputAlignment) * kComicInpainterInputAlignment;
    const int paddedHeight =
        ((inferenceHeight + kComicInpainterInputAlignment - 1) /
            kComicInpainterInputAlignment) * kComicInpainterInputAlignment;
    const int left = (paddedWidth - inferenceWidth) / 2;
    const int right = paddedWidth - inferenceWidth - left;
    const int top = (paddedHeight - inferenceHeight) / 2;
    const int bottom = paddedHeight - inferenceHeight - top;
    task.inferenceWidth = paddedWidth;
    task.inferenceHeight = paddedHeight;

    // manga-image-translator feeds its AOT checkpoint OpenCV BGR data in [-1, 1].
    const int pixelConversion = task.inputBgra ?
        ncnn::Mat::PIXEL_BGRA2BGR : ncnn::Mat::PIXEL_RGBA2BGR;
    ncnn::Mat sourceImage = ncnn::Mat::from_pixels(
        task.input.data(),
        pixelConversion,
        task.width,
        task.height,
        task.stride);
    ncnn::Mat sourceMask(task.width, task.height, 1);
    if (sourceImage.empty() || sourceMask.empty()) {
        task.error = "failed to allocate comic inpainter input";
        return false;
    }
    for (int y = 0; y < task.height; ++y) {
        float *row = sourceMask.row(y);
        for (int x = 0; x < task.width; ++x) {
            row[x] = task.mask[static_cast<size_t>(y) * static_cast<size_t>(task.width) +
                static_cast<size_t>(x)] == 0 ? 0.0f : 1.0f;
        }
    }
    ncnn::Mat resizedImage;
    ncnn::Mat resizedMask;
    if (inferenceWidth != task.width || inferenceHeight != task.height) {
        ncnn::resize_bilinear(
            sourceImage,
            resizedImage,
            inferenceWidth,
            inferenceHeight,
            net->opt);
        ncnn::resize_nearest(
            sourceMask,
            resizedMask,
            inferenceWidth,
            inferenceHeight,
            net->opt);
    } else {
        resizedImage = sourceImage;
        resizedMask = sourceMask;
    }
    if (resizedImage.empty() || resizedMask.empty() ||
        resizedImage.w != inferenceWidth || resizedImage.h != inferenceHeight ||
        resizedImage.c != 3 || resizedMask.w != inferenceWidth ||
        resizedMask.h != inferenceHeight || resizedMask.c != 1) {
        task.error = "failed to resize comic inpainter input";
        return false;
    }
    ncnn::Mat imageInput;
    ncnn::Mat maskInput;
    ncnn::copy_make_border(
        resizedImage,
        imageInput,
        top,
        bottom,
        left,
        right,
        ncnn::BORDER_REFLECT,
        0.0f,
        net->opt);
    ncnn::copy_make_border(
        resizedMask,
        maskInput,
        top,
        bottom,
        left,
        right,
        ncnn::BORDER_CONSTANT,
        0.0f,
        net->opt);
    if (imageInput.empty() || maskInput.empty() ||
        imageInput.w != paddedWidth ||
        imageInput.h != paddedHeight || imageInput.c != 3 ||
        maskInput.w != paddedWidth ||
        maskInput.h != paddedHeight || maskInput.c != 1) {
        task.error = "comic inpainter preprocessing failed: image=" +
            std::to_string(imageInput.dims) + "d/" +
            std::to_string(imageInput.w) + "x" + std::to_string(imageInput.h) + "x" +
            std::to_string(imageInput.c) + ", mask=" +
            std::to_string(maskInput.dims) + "d/" +
            std::to_string(maskInput.w) + "x" + std::to_string(maskInput.h) + "x" +
            std::to_string(maskInput.c);
        return false;
    }
    const float mean[3] = {127.5f, 127.5f, 127.5f};
    const float normalize[3] = {1.0f / 127.5f, 1.0f / 127.5f, 1.0f / 127.5f};
    imageInput.substract_mean_normalize(mean, normalize);
    for (int channel = 0; channel < imageInput.c; ++channel) {
        ncnn::Mat channelValues = imageInput.channel(channel);
        for (int y = 0; y < imageInput.h; ++y) {
            float *imageRow = channelValues.row(y);
            const float *maskRow = maskInput.row(y);
            for (int x = 0; x < imageInput.w; ++x) {
                if (maskRow[x] >= 0.5f) {
                    imageRow[x] = 0.0f;
                }
            }
        }
    }
    task.preprocessingMs = ElapsedMilliseconds(preprocessingStartedAt);

    const SteadyClock::time_point startedAt = SteadyClock::now();
    MmapNcnnAllocator blobAllocator;
    MmapNcnnAllocator workspaceAllocator;
    ncnn::Extractor extractor = net->create_extractor();
    extractor.set_light_mode(true);
    extractor.set_blob_allocator(&blobAllocator);
    extractor.set_workspace_allocator(&workspaceAllocator);
    if (extractor.input("in0", imageInput) != 0 ||
        extractor.input("in1", maskInput) != 0) {
        task.error = "comic inpainter rejected the input tensors";
        return false;
    }
    ncnn::Mat modelOutput;
    if (extractor.extract("out0", modelOutput) != 0) {
        task.error = "comic inpainter failed to infer output";
        return false;
    }
    task.inferenceMs = ElapsedMilliseconds(startedAt);
    if (modelOutput.dims != 3 || modelOutput.w != paddedWidth ||
        modelOutput.h != paddedHeight || modelOutput.c != 3 ||
        modelOutput.elempack != 1) {
        task.error = "comic inpainter returned an unexpected output shape";
        ResetCachedComicInpainter();
        return false;
    }
    const SteadyClock::time_point postprocessingStartedAt = SteadyClock::now();
    ncnn::Mat cropped;
    ncnn::copy_cut_border(modelOutput, cropped, top, bottom, left, right, net->opt);
    if (cropped.empty() || cropped.w != inferenceWidth || cropped.h != inferenceHeight ||
        cropped.c != 3 || cropped.elempack != 1) {
        task.error = "comic inpainter postprocessing failed";
        return false;
    }
    ncnn::Mat restored;
    if (inferenceWidth != task.width || inferenceHeight != task.height) {
        ncnn::resize_bilinear(cropped, restored, task.width, task.height, net->opt);
    } else {
        restored = cropped;
    }
    if (restored.empty() || restored.w != task.width || restored.h != task.height ||
        restored.c != 3 || restored.elempack != 1) {
        task.error = "comic inpainter output resize failed";
        return false;
    }
    for (int y = 0; y < task.height; ++y) {
        const float *blue = restored.channel(0).row(y);
        const float *green = restored.channel(1).row(y);
        const float *red = restored.channel(2).row(y);
        for (int x = 0; x < task.width; ++x) {
            const size_t maskIndex =
                static_cast<size_t>(y) * static_cast<size_t>(task.width) +
                static_cast<size_t>(x);
            if (task.mask[maskIndex] == 0) {
                continue;
            }
            const size_t pixelOffset =
                static_cast<size_t>(y) * static_cast<size_t>(task.stride) +
                static_cast<size_t>(x) * 4;
            const uint8_t redByte = static_cast<uint8_t>(std::clamp(
                std::round((red[x] + 1.0f) * 127.5f), 0.0f, 255.0f));
            const uint8_t greenByte = static_cast<uint8_t>(std::clamp(
                std::round((green[x] + 1.0f) * 127.5f), 0.0f, 255.0f));
            const uint8_t blueByte = static_cast<uint8_t>(std::clamp(
                std::round((blue[x] + 1.0f) * 127.5f), 0.0f, 255.0f));
            task.output[pixelOffset] = task.inputBgra ? blueByte : redByte;
            task.output[pixelOffset + 1] = greenByte;
            task.output[pixelOffset + 2] = task.inputBgra ? redByte : blueByte;
        }
    }
    task.postprocessingMs = ElapsedMilliseconds(postprocessingStartedAt);
    return true;
}

void ExecuteComicInpainting(napi_env env, void *data)
{
    (void)env;
    auto *task = static_cast<ComicInpaintingTask *>(data);
    RunComicInpainting(*task);
    std::vector<uint8_t>().swap(task->input);
    std::vector<uint8_t>().swap(task->mask);
}

void ExecuteUpscale(napi_env env, void *data)
{
    (void)env;
    auto *task = static_cast<UpscaleTask *>(data);
    if (RunUpscale(*task)) {
        ApplyEffectStrength(*task);
    }
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

void ExecuteMindSporeUpscale(napi_env env, void *data)
{
    (void)env;
    auto *task = static_cast<UpscaleTask *>(data);
    if (RunMindSporeUpscale(*task)) {
        ApplyEffectStrength(*task);
    }
    std::vector<uint8_t>().swap(task->input);
}

void ExecuteMindSporePrepare(napi_env env, void *data)
{
    (void)env;
    auto *task = static_cast<UpscaleTask *>(data);
    RunMindSporePrepare(*task);
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

napi_value IntValue(napi_env env, int value)
{
    napi_value result = nullptr;
    napi_create_int32(env, value, &result);
    return result;
}

napi_value DoubleValue(napi_env env, double value)
{
    napi_value result = nullptr;
    napi_create_double(env, value, &result);
    return result;
}

const char *ComicRegionClassLabel(int classId)
{
    constexpr const char *labels[kComicDetectorClassCount] = {
        "balloon",
        "qipao",
        "shuqing",
        "changfangtiao",
        "hengxie",
    };
    return classId >= 0 && classId < kComicDetectorClassCount ? labels[classId] : "unknown";
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
            napi_set_named_property(env, result, "tileCount", Int64Value(env, task->tileCount));
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

void CompleteComicRegionDetection(napi_env env, napi_status status, void *data)
{
    auto *task = static_cast<ComicRegionDetectionTask *>(data);
    if (status == napi_ok && task->error.empty()) {
        napi_value result = nullptr;
        napi_value regions = nullptr;
        if (napi_create_object(env, &result) == napi_ok &&
            napi_create_array_with_length(env, task->regions.size(), &regions) == napi_ok) {
            for (size_t index = 0; index < task->regions.size(); ++index) {
                const ComicRegionDetection &region = task->regions[index];
                napi_value item = nullptr;
                napi_value points = nullptr;
                napi_create_object(env, &item);
                napi_create_array_with_length(env, 8, &points);
                for (uint32_t coordinate = 0; coordinate < 8; ++coordinate) {
                    napi_set_element(
                        env,
                        points,
                        coordinate,
                        DoubleValue(env, region.points[coordinate]));
                }
                napi_set_named_property(env, item, "points", points);
                napi_set_named_property(env, item, "score", DoubleValue(env, region.score));
                napi_set_named_property(env, item, "classId", IntValue(env, region.classId));
                napi_set_named_property(
                    env,
                    item,
                    "label",
                    StringValue(env, ComicRegionClassLabel(region.classId)));
                napi_set_element(env, regions, index, item);
            }
            napi_set_named_property(env, result, "regions", regions);
            napi_set_named_property(env, result, "backend", StringValue(env, "ncnn-fp32-cpu"));
            napi_set_named_property(env, result, "modelLoadMs", Int64Value(env, task->modelLoadMs));
            napi_set_named_property(env, result, "inferenceMs", Int64Value(env, task->inferenceMs));
            napi_resolve_deferred(env, task->deferred, result);
        } else {
            task->error = "failed to allocate comic detector result";
        }
    }
    if (status != napi_ok || !task->error.empty()) {
        const std::string message = task->error.empty()
            ? "native comic region detection failed"
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

void CompleteComicTextRecognition(napi_env env, napi_status status, void *data)
{
    auto *task = static_cast<ComicTextRecognitionTask *>(data);
    if (status == napi_ok && task->error.empty()) {
        napi_value result = nullptr;
        if (napi_create_object(env, &result) == napi_ok) {
            napi_set_named_property(env, result, "text", StringValue(env, task->text));
            napi_set_named_property(env, result, "score", DoubleValue(env, task->score));
            napi_set_named_property(env, result, "backend", StringValue(env, "ncnn-fp32-cpu"));
            napi_set_named_property(env, result, "modelLoadMs", Int64Value(env, task->modelLoadMs));
            napi_set_named_property(
                env,
                result,
                "preprocessingMs",
                Int64Value(env, task->preprocessingMs));
            napi_set_named_property(env, result, "inferenceMs", Int64Value(env, task->inferenceMs));
            napi_set_named_property(env, result, "decodingMs", Int64Value(env, task->decodingMs));
            napi_resolve_deferred(env, task->deferred, result);
        } else {
            task->error = "failed to allocate comic text recognizer result";
        }
    }
    if (status != napi_ok || !task->error.empty()) {
        const std::string message = task->error.empty()
            ? "native comic text recognition failed"
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

void CompleteComicTextMask(napi_env env, napi_status status, void *data)
{
    auto *task = static_cast<ComicTextMaskTask *>(data);
    if (status == napi_ok && task->error.empty()) {
        const SteadyClock::time_point marshallingStartedAt = SteadyClock::now();
        napi_value result = nullptr;
        napi_value outputBuffer = nullptr;
        void *outputData = nullptr;
        // HarmonyOS does not export napi_adjust_external_memory. Keep these full-page masks
        // VM-owned so consecutive pages contribute to GC pressure instead of accumulating
        // unreported external buffers until an unrelated collection.
        const bool primaryCreated = napi_create_object(env, &result) == napi_ok &&
            napi_create_arraybuffer(
                env,
                task->mask.size(),
                &outputData,
                &outputBuffer) == napi_ok;
        if (primaryCreated) {
            std::memcpy(outputData, task->mask.data(), task->mask.size());
            napi_set_named_property(env, result, "mask", outputBuffer);
            if (!task->secondaryMask.empty()) {
                napi_value secondaryBuffer = nullptr;
                void *secondaryData = nullptr;
                if (napi_create_arraybuffer(
                        env,
                        task->secondaryMask.size(),
                        &secondaryData,
                        &secondaryBuffer) == napi_ok) {
                    std::memcpy(
                        secondaryData,
                        task->secondaryMask.data(),
                        task->secondaryMask.size());
                    napi_set_named_property(env, result, "secondaryMask", secondaryBuffer);
                } else {
                    task->error = "failed to allocate secondary comic text mask result";
                }
            }
        } else {
            task->error = "failed to allocate comic text mask result";
        }
        task->resultMarshallingMs = ElapsedMilliseconds(marshallingStartedAt);
        if (task->error.empty()) {
            napi_set_named_property(env, result, "backend", StringValue(env, "ncnn-fp16-cpu"));
            napi_set_named_property(env, result, "modelLoadMs", Int64Value(env, task->modelLoadMs));
            napi_set_named_property(
                env,
                result,
                "preprocessingMs",
                Int64Value(env, task->preprocessingMs));
            napi_set_named_property(env, result, "inferenceMs", Int64Value(env, task->inferenceMs));
            napi_set_named_property(
                env,
                result,
                "postprocessingMs",
                Int64Value(env, task->postprocessingMs));
            napi_set_named_property(
                env,
                result,
                "resultMarshallingMs",
                Int64Value(env, task->resultMarshallingMs));
            napi_set_named_property(env, result, "maskedPixels", Int64Value(env, task->maskedPixels));
            napi_set_named_property(
                env,
                result,
                "secondaryMaskedPixels",
                Int64Value(env, task->secondaryMaskedPixels));
            napi_resolve_deferred(env, task->deferred, result);
        }
    }
    if (status != napi_ok || !task->error.empty()) {
        const std::string message = task->error.empty()
            ? "native comic text mask inference failed"
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

void CompleteComicInpainting(napi_env env, napi_status status, void *data)
{
    auto *task = static_cast<ComicInpaintingTask *>(data);
    if (status == napi_ok && task->error.empty()) {
        napi_value result = nullptr;
        napi_value outputBuffer = nullptr;
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
            napi_set_named_property(env, result, "backend", StringValue(env, "ncnn-fp32-cpu"));
            napi_set_named_property(env, result, "modelLoadMs", Int64Value(env, task->modelLoadMs));
            napi_set_named_property(
                env,
                result,
                "preprocessingMs",
                Int64Value(env, task->preprocessingMs));
            napi_set_named_property(env, result, "inferenceMs", Int64Value(env, task->inferenceMs));
            napi_set_named_property(
                env,
                result,
                "postprocessingMs",
                Int64Value(env, task->postprocessingMs));
            napi_set_named_property(env, result, "inferenceWidth", IntValue(env, task->inferenceWidth));
            napi_set_named_property(env, result, "inferenceHeight", IntValue(env, task->inferenceHeight));
            napi_resolve_deferred(env, task->deferred, result);
        } else {
            delete output;
            task->error = "failed to allocate comic inpainter result";
        }
    }
    if (status != napi_ok || !task->error.empty()) {
        const std::string message = task->error.empty()
            ? "native comic inpainting failed"
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
    size_t argc = 15;
    napi_value argv[15] = {nullptr};
    if (napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr) != napi_ok || argc < 15) {
        napi_throw_type_error(env, nullptr, "upscaleRgba expects 15 arguments");
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
        !GetInt(env, argv[14], task->effectStrengthPercent) ||
        requestId <= 0 ||
        modelKind < static_cast<int>(ModelKind::Waifu2x) ||
        modelKind > static_cast<int>(ModelKind::Waifu2xCunet) ||
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

napi_value DetectComicRegions(napi_env env, napi_callback_info info)
{
    size_t argc = 8;
    napi_value argv[8] = {nullptr};
    if (napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr) != napi_ok || argc < 8) {
        napi_throw_type_error(env, nullptr, "detectComicRegions expects 8 arguments");
        return nullptr;
    }
    auto *task = new ComicRegionDetectionTask();
    if (!GetBytes(env, argv[0], task->input) ||
        !GetInt(env, argv[1], task->width) ||
        !GetInt(env, argv[2], task->height) ||
        !GetInt(env, argv[3], task->stride) ||
        !GetFloat(env, argv[6], task->confidenceThreshold) ||
        !GetInt(env, argv[7], task->threads)) {
        delete task;
        napi_throw_type_error(env, nullptr, "invalid comic region detector argument type");
        return nullptr;
    }
    task->paramPath = GetString(env, argv[4]);
    task->modelPath = GetString(env, argv[5]);
    if (task->paramPath.empty() || task->modelPath.empty()) {
        delete task;
        napi_throw_type_error(env, nullptr, "comic detector model paths are required");
        return nullptr;
    }
    napi_value promise = nullptr;
    napi_create_promise(env, &task->deferred, &promise);
    napi_value resourceName = nullptr;
    napi_create_string_utf8(env, "NextEComicRegionDetector", NAPI_AUTO_LENGTH, &resourceName);
    if (napi_create_async_work(
            env,
            nullptr,
            resourceName,
            ExecuteComicRegionDetection,
            CompleteComicRegionDetection,
            task,
            &task->work) != napi_ok) {
        delete task;
        napi_throw_error(env, nullptr, "failed to create comic region detector task");
        return nullptr;
    }
    if (napi_queue_async_work_with_qos(env, task->work, napi_qos_user_initiated) != napi_ok) {
        napi_delete_async_work(env, task->work);
        delete task;
        napi_throw_error(env, nullptr, "failed to queue comic region detector task");
        return nullptr;
    }
    return promise;
}

napi_value RecognizeComicText(napi_env env, napi_callback_info info)
{
    size_t argc = 9;
    napi_value argv[9] = {nullptr};
    if (napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr) != napi_ok || argc < 9) {
        napi_throw_type_error(env, nullptr, "recognizeComicText expects 9 arguments");
        return nullptr;
    }
    auto *task = new ComicTextRecognitionTask();
    if (!GetBytes(env, argv[0], task->input) ||
        !GetInt(env, argv[1], task->width) ||
        !GetInt(env, argv[2], task->height) ||
        !GetInt(env, argv[3], task->stride) ||
        napi_get_value_bool(env, argv[7], &task->rotateCounterClockwise) != napi_ok ||
        !GetInt(env, argv[8], task->threads)) {
        delete task;
        napi_throw_type_error(env, nullptr, "invalid comic text recognizer argument type");
        return nullptr;
    }
    task->paramPath = GetString(env, argv[4]);
    task->modelPath = GetString(env, argv[5]);
    task->dictionaryPath = GetString(env, argv[6]);
    if (task->paramPath.empty() || task->modelPath.empty() || task->dictionaryPath.empty()) {
        delete task;
        napi_throw_type_error(env, nullptr, "comic text recognizer model paths are required");
        return nullptr;
    }
    napi_value promise = nullptr;
    napi_create_promise(env, &task->deferred, &promise);
    napi_value resourceName = nullptr;
    napi_create_string_utf8(env, "NextEComicTextRecognizer", NAPI_AUTO_LENGTH, &resourceName);
    if (napi_create_async_work(
            env,
            nullptr,
            resourceName,
            ExecuteComicTextRecognition,
            CompleteComicTextRecognition,
            task,
            &task->work) != napi_ok) {
        delete task;
        napi_throw_error(env, nullptr, "failed to create comic text recognizer task");
        return nullptr;
    }
    // Supplemental PP-OCR is bounded to a few short recognitions and directly gates the
    // user-requested current-page result. Background QoS can starve these small tasks for
    // seconds behind unrelated native work even though inference itself takes milliseconds.
    if (napi_queue_async_work_with_qos(env, task->work, napi_qos_user_initiated) != napi_ok) {
        napi_delete_async_work(env, task->work);
        delete task;
        napi_throw_error(env, nullptr, "failed to queue comic text recognizer task");
        return nullptr;
    }
    return promise;
}

napi_value InpaintComicRegion(napi_env env, napi_callback_info info)
{
    size_t argc = 9;
    napi_value argv[9] = {nullptr};
    if (napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr) != napi_ok || argc < 9) {
        napi_throw_type_error(env, nullptr, "inpaintComicRegion expects 9 arguments");
        return nullptr;
    }
    auto *task = new ComicInpaintingTask();
    if (!GetBytes(env, argv[0], task->input) ||
        !GetBytes(env, argv[1], task->mask) ||
        !GetInt(env, argv[2], task->width) ||
        !GetInt(env, argv[3], task->height) ||
        !GetInt(env, argv[4], task->stride) ||
        !GetInt(env, argv[7], task->threads) ||
        napi_get_value_bool(env, argv[8], &task->inputBgra) != napi_ok) {
        delete task;
        napi_throw_type_error(env, nullptr, "invalid comic inpainter argument type");
        return nullptr;
    }
    task->paramPath = GetString(env, argv[5]);
    task->modelPath = GetString(env, argv[6]);
    if (task->paramPath.empty() || task->modelPath.empty()) {
        delete task;
        napi_throw_type_error(env, nullptr, "comic inpainter model paths are required");
        return nullptr;
    }
    napi_value promise = nullptr;
    napi_create_promise(env, &task->deferred, &promise);
    napi_value resourceName = nullptr;
    napi_create_string_utf8(env, "NextEComicInpainter", NAPI_AUTO_LENGTH, &resourceName);
    if (napi_create_async_work(
            env,
            nullptr,
            resourceName,
            ExecuteComicInpainting,
            CompleteComicInpainting,
            task,
            &task->work) != napi_ok) {
        delete task;
        napi_throw_error(env, nullptr, "failed to create comic inpainter task");
        return nullptr;
    }
    if (napi_queue_async_work_with_qos(env, task->work, napi_qos_utility) != napi_ok) {
        napi_delete_async_work(env, task->work);
        delete task;
        napi_throw_error(env, nullptr, "failed to queue comic inpainter task");
        return nullptr;
    }
    return promise;
}

napi_value InferComicTextMask(napi_env env, napi_callback_info info)
{
    size_t argc = 10;
    napi_value argv[10] = {nullptr};
    if (napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr) != napi_ok || argc < 10) {
        napi_throw_type_error(env, nullptr, "inferComicTextMask expects 10 arguments");
        return nullptr;
    }
    auto *task = new ComicTextMaskTask();
    if (!GetBytes(env, argv[0], task->input) ||
        !GetInt(env, argv[1], task->width) ||
        !GetInt(env, argv[2], task->height) ||
        !GetInt(env, argv[3], task->stride) ||
        !GetFloat(env, argv[6], task->threshold) ||
        !GetInt(env, argv[7], task->threads) ||
        napi_get_value_bool(env, argv[8], &task->inputBgra) != napi_ok ||
        !GetFloat(env, argv[9], task->secondaryThreshold)) {
        delete task;
        napi_throw_type_error(env, nullptr, "invalid comic text mask argument type");
        return nullptr;
    }
    task->paramPath = GetString(env, argv[4]);
    task->modelPath = GetString(env, argv[5]);
    if (task->paramPath.empty() || task->modelPath.empty()) {
        delete task;
        napi_throw_type_error(env, nullptr, "comic text mask model paths are required");
        return nullptr;
    }
    napi_value promise = nullptr;
    napi_create_promise(env, &task->deferred, &promise);
    napi_value resourceName = nullptr;
    napi_create_string_utf8(env, "NextEComicTextMask", NAPI_AUTO_LENGTH, &resourceName);
    if (napi_create_async_work(
            env,
            nullptr,
            resourceName,
            ExecuteComicTextMask,
            CompleteComicTextMask,
            task,
            &task->work) != napi_ok) {
        delete task;
        napi_throw_error(env, nullptr, "failed to create comic text mask task");
        return nullptr;
    }
    // CTD proposal/treatment is serialized and directly blocks the requested page result.
    // Keep the heavier inference unchanged, but avoid utility-queue starvation on the current page.
    if (napi_queue_async_work_with_qos(env, task->work, napi_qos_user_initiated) != napi_ok) {
        napi_delete_async_work(env, task->work);
        delete task;
        napi_throw_error(env, nullptr, "failed to queue comic text mask task");
        return nullptr;
    }
    return promise;
}

napi_value UpscaleMindSporeRgba(napi_env env, napi_callback_info info)
{
    size_t argc = 8;
    napi_value argv[8] = {nullptr};
    if (napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr) != napi_ok || argc < 8) {
        napi_throw_type_error(env, nullptr, "upscaleMindSporeRgba expects 8 arguments");
        return nullptr;
    }

    auto *task = new UpscaleTask();
    int modelKind = 0;
    int64_t requestId = 0;
    if (!GetBytes(env, argv[0], task->input) ||
        !GetInt(env, argv[1], task->width) ||
        !GetInt(env, argv[2], task->height) ||
        !GetInt(env, argv[3], task->stride) ||
        !GetInt(env, argv[5], modelKind) ||
        !GetInt64(env, argv[6], requestId) || requestId <= 0 ||
        !GetInt(env, argv[7], task->effectStrengthPercent) ||
        modelKind < static_cast<int>(ModelKind::Waifu2x) ||
        modelKind > static_cast<int>(ModelKind::Waifu2xCunet)) {
        delete task;
        napi_throw_type_error(env, nullptr, "invalid MindSpore NNRT upscale argument type");
        return nullptr;
    }
    task->modelPath = GetString(env, argv[4]);
    task->modelKind = static_cast<ModelKind>(modelKind);
    task->requestId = static_cast<uint64_t>(requestId);
    if (task->modelPath.empty()) {
        delete task;
        napi_throw_type_error(env, nullptr, "MindSpore NNRT model path is required");
        return nullptr;
    }

    napi_value promise = nullptr;
    napi_create_promise(env, &task->deferred, &promise);
    napi_value resourceName = nullptr;
    napi_create_string_utf8(env, "NextEMindSporeNnrt", NAPI_AUTO_LENGTH, &resourceName);
    if (napi_create_async_work(
            env,
            nullptr,
            resourceName,
            ExecuteMindSporeUpscale,
            CompleteUpscale,
            task,
            &task->work) != napi_ok) {
        delete task;
        napi_throw_error(env, nullptr, "failed to create MindSpore NNRT upscale task");
        return nullptr;
    }
    if (napi_queue_async_work_with_qos(env, task->work, napi_qos_background) != napi_ok) {
        napi_delete_async_work(env, task->work);
        delete task;
        napi_throw_error(env, nullptr, "failed to queue MindSpore NNRT upscale task");
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
        modelKind > static_cast<int>(ModelKind::Waifu2xCunet) ||
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

napi_value PrepareMindSporeModelNapi(napi_env env, napi_callback_info info)
{
    size_t argc = 2;
    napi_value argv[2] = {nullptr};
    if (napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr) != napi_ok || argc < 2) {
        napi_throw_type_error(env, nullptr, "prepareMindSporeModel expects a model path and kind");
        return nullptr;
    }
    auto *task = new UpscaleTask();
    int modelKind = 0;
    task->modelPath = GetString(env, argv[0]);
    if (!GetInt(env, argv[1], modelKind) ||
        modelKind < static_cast<int>(ModelKind::Waifu2x) ||
        modelKind > static_cast<int>(ModelKind::Waifu2xCunet) ||
        task->modelPath.empty()) {
        delete task;
        napi_throw_type_error(env, nullptr, "MindSpore NNRT model path and kind are required");
        return nullptr;
    }
    task->modelKind = static_cast<ModelKind>(modelKind);

    napi_value promise = nullptr;
    napi_create_promise(env, &task->deferred, &promise);
    napi_value resourceName = nullptr;
    napi_create_string_utf8(env, "NextEMindSporeNnrtPrepare", NAPI_AUTO_LENGTH, &resourceName);
    if (napi_create_async_work(
            env,
            nullptr,
            resourceName,
            ExecuteMindSporePrepare,
            CompletePrepare,
            task,
            &task->work) != napi_ok) {
        delete task;
        napi_throw_error(env, nullptr, "failed to create MindSpore NNRT preparation task");
        return nullptr;
    }
    if (napi_queue_async_work_with_qos(env, task->work, napi_qos_background) != napi_ok) {
        napi_delete_async_work(env, task->work);
        delete task;
        napi_throw_error(env, nullptr, "failed to queue MindSpore NNRT preparation task");
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
    napi_value vulkanApiVersion = nullptr;
    napi_create_object(env, &result);
    napi_get_boolean(env, VulkanAvailable(), &vulkanAvailable);
    napi_create_int32(env, gGpuCount, &gpuCount);
    napi_create_uint32(env, gGpuApiVersion, &vulkanApiVersion);
    napi_set_named_property(env, result, "vulkanAvailable", vulkanAvailable);
    napi_set_named_property(env, result, "gpuCount", gpuCount);
    napi_set_named_property(env, result, "vulkanApiVersion", vulkanApiVersion);
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
        {"prepareMindSporeModel", nullptr, PrepareMindSporeModelNapi, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"upscaleMindSporeRgba", nullptr, UpscaleMindSporeRgba, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"detectComicRegions", nullptr, DetectComicRegions, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"recognizeComicText", nullptr, RecognizeComicText, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"inferComicTextMask", nullptr, InferComicTextMask, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"inpaintComicRegion", nullptr, InpaintComicRegion, nullptr, nullptr, nullptr, napi_default, nullptr},
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
