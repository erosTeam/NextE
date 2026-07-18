import { ErrorEvent, MessageEvents, ThreadWorkerGlobalScope, worker } from '@kit.ArkTS'
import { mindSporeLite } from '@kit.MindSporeLiteKit'

const MODEL_INPUT_SIZE: number = 180
const MODEL_OUTPUT_SIZE: number = MODEL_INPUT_SIZE * 2
const INPUT_PLANE_ELEMENTS: number = MODEL_INPUT_SIZE * MODEL_INPUT_SIZE
const OUTPUT_PLANE_ELEMENTS: number = MODEL_OUTPUT_SIZE * MODEL_OUTPUT_SIZE

interface ReaderMindSporeWorkerRequest {
  kind: string
  requestId: number
  modelPath: string
  tensor: ArrayBuffer
}

interface ReaderMindSporeWorkerResponse {
  kind: string
  requestId: number
  tensor: ArrayBuffer
  modelLoadMs: number
  inferenceMs: number
  message: string
}

class ReaderMindSporeLoadedModel {
  model: mindSporeLite.Model
  input: mindSporeLite.MSTensor

  constructor(model: mindSporeLite.Model, input: mindSporeLite.MSTensor) {
    this.model = model
    this.input = input
  }
}

class ReaderMindSporeAccelerator {
  deviceID: bigint
  deviceName: string

  constructor(deviceID: bigint, deviceName: string) {
    this.deviceID = deviceID
    this.deviceName = deviceName
  }
}

let workerPort: ThreadWorkerGlobalScope | null = null
let cachedPath: string = ''
let cachedModel: ReaderMindSporeLoadedModel | null = null
let loadInFlight: Promise<ReaderMindSporeLoadedModel> | null = null

function response(
  kind: string,
  requestId: number,
  tensor: ArrayBuffer = new ArrayBuffer(0),
  modelLoadMs: number = 0,
  inferenceMs: number = 0,
  message: string = '',
): ReaderMindSporeWorkerResponse {
  return {
    kind: kind,
    requestId: requestId,
    tensor: tensor,
    modelLoadMs: modelLoadMs,
    inferenceMs: inferenceMs,
    message: message,
  }
}

function postResponse(
  message: ReaderMindSporeWorkerResponse,
  transfer: ArrayBuffer[] = [],
): void {
  if (workerPort === null) {
    throw new Error('NNRT worker port is unavailable')
  }
  if (transfer.length > 0) {
    workerPort.postMessage(message, transfer)
  } else {
    workerPort.postMessage(message)
  }
}

function acceleratorDevice(): ReaderMindSporeAccelerator | null {
  const devices: mindSporeLite.NNRTDeviceDescription[] =
    mindSporeLite.getAllNNRTDeviceDescriptions()
  let fallback: ReaderMindSporeAccelerator | null = null
  for (let index: number = 0; index < devices.length; index++) {
    const device: mindSporeLite.NNRTDeviceDescription = devices[index]
    if (device.deviceType() !== mindSporeLite.NNRTDeviceType.NNRTDEVICE_ACCELERATOR) {
      continue
    }
    const accelerator: ReaderMindSporeAccelerator = new ReaderMindSporeAccelerator(
      device.deviceID(),
      device.deviceName(),
    )
    if (fallback === null) {
      fallback = accelerator
    }
    if (accelerator.deviceName.startsWith('NPU_')) {
      return accelerator
    }
  }
  return fallback
}

async function loadModelNow(modelPath: string): Promise<ReaderMindSporeLoadedModel> {
  const device: ReaderMindSporeAccelerator | null = acceleratorDevice()
  if (device === null) {
    throw new Error('NNRT accelerator is unavailable')
  }
  const context: mindSporeLite.Context = {
    target: ['nnrt'],
    nnrt: {
      deviceID: device.deviceID,
      performanceMode: mindSporeLite.PerformanceMode.PERFORMANCE_HIGH,
      priority: mindSporeLite.Priority.PRIORITY_LOW,
    },
  }
  const model: mindSporeLite.Model =
    await mindSporeLite.loadModelFromFile(modelPath, context)
  const inputs: mindSporeLite.MSTensor[] = model.getInputs()
  const input: mindSporeLite.MSTensor | undefined = inputs[0]
  if (input === undefined ||
    input.dtype !== mindSporeLite.DataType.NUMBER_TYPE_FLOAT32 ||
    input.format !== mindSporeLite.Format.NCHW ||
    input.elementNum !== INPUT_PLANE_ELEMENTS * 3 ||
    input.dataSize !== INPUT_PLANE_ELEMENTS * 3 * 4) {
    throw new Error('Real-ESRGAN NNRT model has an unexpected input contract')
  }
  return new ReaderMindSporeLoadedModel(model, input)
}

async function loadModel(modelPath: string): Promise<ReaderMindSporeLoadedModel> {
  if (cachedPath === modelPath && cachedModel !== null) {
    return cachedModel
  }
  if (cachedPath === modelPath && loadInFlight !== null) {
    return await loadInFlight
  }
  const task: Promise<ReaderMindSporeLoadedModel> = loadModelNow(modelPath)
  cachedPath = modelPath
  cachedModel = null
  loadInFlight = task
  try {
    const loaded: ReaderMindSporeLoadedModel = await task
    if (cachedPath === modelPath) {
      cachedModel = loaded
    }
    return loaded
  } finally {
    if (loadInFlight === task) {
      loadInFlight = null
    }
  }
}

async function handleMessage(request: ReaderMindSporeWorkerRequest): Promise<void> {
  try {
    const loadStartedAt: number = Date.now()
    const loaded: ReaderMindSporeLoadedModel = await loadModel(request.modelPath)
    const modelLoadMs: number = Date.now() - loadStartedAt
    if (request.kind === 'prepare') {
      postResponse(response('prepared', request.requestId, new ArrayBuffer(0), modelLoadMs))
      return
    }
    if (request.kind !== 'predict') {
      throw new Error('unsupported NNRT worker request')
    }
    if (request.tensor.byteLength !== INPUT_PLANE_ELEMENTS * 3 * 4) {
      throw new Error('Real-ESRGAN NNRT worker received an unexpected input buffer')
    }
    loaded.input.setData(request.tensor)
    const inferenceStartedAt: number = Date.now()
    const outputs: mindSporeLite.MSTensor[] = await loaded.model.predict([loaded.input])
    const inferenceMs: number = Date.now() - inferenceStartedAt
    const output: mindSporeLite.MSTensor | undefined = outputs[0]
    if (output === undefined ||
      output.dtype !== mindSporeLite.DataType.NUMBER_TYPE_FLOAT32 ||
      output.format !== mindSporeLite.Format.NCHW ||
      output.elementNum !== OUTPUT_PLANE_ELEMENTS * 3 ||
      output.dataSize !== OUTPUT_PLANE_ELEMENTS * 3 * 4) {
      throw new Error('Real-ESRGAN NNRT model returned an unexpected output contract')
    }
    const tensor: ArrayBuffer = output.getData()
    postResponse(
      response('predicted', request.requestId, tensor, modelLoadMs, inferenceMs),
      [tensor],
    )
  } catch (error) {
    postResponse(
      response('failure', request.requestId, new ArrayBuffer(0), 0, 0, (error as Error).message),
    )
  }
}

export function startReaderMindSporeSuperResolutionWorker(): void {
  workerPort = worker.workerPort
  workerPort.onmessage = (event: MessageEvents): void => {
    handleMessage(event.data as ReaderMindSporeWorkerRequest).catch((error: Error): void => {
      postResponse(response('failure', -1, new ArrayBuffer(0), 0, 0, error.message))
    })
  }
  workerPort.onerror = (_error: ErrorEvent): void => {}
}
