import { image } from '@kit.ImageKit'
import common from '@ohos.app.ability.common'
import { NodeContent } from '@ohos.arkui.node'
import nativeNode from 'libimageknifepro.so'
import {
  CacheStrategy,
  DownSamplingStrategy,
  EventImage,
  HeaderOptions,
  ImageKnife,
  ImageInfo,
  ImageKnifeOptionV2,
  Priority,
} from '@ohos/imageknifepro'
import { DiagnosticLogger } from '../diagnostics/DiagnosticLogger'
import { ImageKnifeProRuntime } from './ImageKnifeProRuntime'
import {
  EH_IMAGE_DOWNSAMPLING_AT_LEAST,
  EH_IMAGE_DOWNSAMPLING_AT_MOST,
  EH_IMAGE_DOWNSAMPLING_CENTER_INSIDE_MEMORY,
  EH_IMAGE_DOWNSAMPLING_CENTER_INSIDE_QUALITY,
  EH_IMAGE_DOWNSAMPLING_DESIRED_SIZE_ASPECT_FILL,
  EH_IMAGE_DOWNSAMPLING_DESIRED_SIZE_ASPECT_FIT,
  EH_IMAGE_DOWNSAMPLING_DESIRED_SIZE_FILL,
  EH_IMAGE_DOWNSAMPLING_FIT_CENTER_MEMORY,
  EH_IMAGE_DOWNSAMPLING_FIT_CENTER_QUALITY,
  EH_IMAGE_DOWNSAMPLING_NONE,
  EH_IMAGE_PRIORITY_HIGH,
  EH_IMAGE_PRIORITY_LOW,
} from './ImagePipelineTypes'

@ComponentV2
export struct ImageKnifeProImageAdapter {
  @Param src: string = '';
  @Param objectFit: ImageFit = ImageFit.Cover;
  @Param radius: number = 0;
  @Param widthValue: Length = '100%';
  @Param heightValue: Length = '100%';
  @Param enableCache: boolean = true;
  @Param memoryOnly: boolean = false;
  @Param fileCacheName: string = '';
  @Param signature: string = '';
  @Param priority: number = EH_IMAGE_PRIORITY_LOW;
  @Param downSampling: number = 1;
  @Param desiredWidth: number = 0;
  @Param desiredHeight: number = 0;
  @Param maxRetries: number = 0;
  @Param retryDelayMs: number = 0;
  @Param settleTimeoutMs: number = 0;
  @Param connectTimeoutMs: number = 0;
  @Param readTimeoutMs: number = 0;
  @Param reloadToken: number = 0;
  @Event onComplete: () => void = () => {};
  @Event onImageInfo: (width: number, height: number) => void = (_width: number, _height: number) => {};
  @Event onError: () => void = () => {};
  @Event onProgress: (progress: number) => void = (_progress: number) => {};
  @Local option: ImageKnifeOptionV2 = new ImageKnifeOptionV2();
  @Local completionNotified: boolean = false;
  private requestEpoch: number = 0;
  private requestId: string = '';
  private retriesUsed: number = 0;
  private settleTimerId: number = 0;
  private retryTimerId: number = 0;
  // The vendor V2 component clears its native root when an ancestor is recycled, but its
  // monitor-based rebind is suppressed by V2 resetStateVarsOnReuse. Keeping the native root
  // here makes option construction and native update one lifecycle transaction.
  private nativeComponentId: string = '';
  private nativeRootAttached: boolean = false;
  private nativeRootSlot: NodeContent = new NodeContent();

  aboutToAppear(): void {
    this.nativeComponentId = this.getUniqueId().toString()
    this.applyOption()
    nativeNode.createNativeRoot(
      this.nativeRootSlot,
      this.nativeComponentId,
      this.option,
      undefined,
      this.defaultContext(),
      {
        syncLoad: false,
        draggable: false,
      },
    )
    this.nativeRootAttached = true
  }

  aboutToReuse(): void {
    this.applyOption()
  }

  aboutToDisappear(): void {
    this.invalidateRequest()
    if (this.nativeRootAttached) {
      nativeNode.destroyNativeRoot(this.nativeComponentId)
      this.nativeRootAttached = false
    }
  }

  aboutToRecycle(): void {
    // Native clear cancels its request, but it cannot invalidate this adapter's JS timers or
    // listener closures. Do that first so an old settle/retry callback cannot reload a cover
    // while this component is parked in WaterFlow's reuse pool.
    this.invalidateRequest()
    nativeNode.clearNativeRoot(this.nativeComponentId)
  }

  @Monitor(
    'src',
    'objectFit',
    'radius',
    'enableCache',
    'memoryOnly',
    'fileCacheName',
    'signature',
    'priority',
    'downSampling',
    'desiredWidth',
    'desiredHeight',
    'maxRetries',
    'retryDelayMs',
    'settleTimeoutMs',
    'connectTimeoutMs',
    'readTimeoutMs',
    'reloadToken',
  )
  onOptionInputChanged(): void {
    this.applyOption()
  }

  private applyOption(): void {
    this.clearTimers()
    this.requestEpoch += 1
    const epoch: number = this.requestEpoch
    this.requestId = ''
    this.retriesUsed = 0
    this.completionNotified = false
    const option: ImageKnifeOptionV2 = new ImageKnifeOptionV2()
    option.loadSrc = this.src
    option.objectFit = this.objectFit
    option.writeCacheStrategy = this.memoryOnly
      ? CacheStrategy.MEMORY
      : (this.enableCache ? CacheStrategy.DEFAULT : CacheStrategy.NONE)
    option.headerOption = this.headers()
    option.priority = this.imageKnifePriority()
    if (this.connectTimeoutMs > 0 && this.readTimeoutMs > 0) {
      option.httpOption = {
        connectTimeout: this.connectTimeoutMs,
        readTimeout: this.readTimeoutMs,
      }
    }
    if (this.fileCacheName.length > 0) {
      option.fileCacheName = this.fileCacheName
    }
    if (this.signature.length > 0) {
      option.signature = this.signature
    }
    option.downSampling = this.imageKnifeDownSampling()
    if (this.desiredWidth > 0 && this.desiredHeight > 0) {
      const desiredSize: image.Size = {
        width: this.desiredWidth,
        height: this.desiredHeight,
      }
      option.desiredSize = desiredSize
    }
    option.progressListener = (progress: number) => {
      if (this.isCurrent(epoch)) {
        this.onProgress(progress)
      }
    }
    option.onLoadListener = {
      onLoadStart: (imageInfo: ImageInfo) => {
        if (!this.isCurrent(epoch)) {
          return
        }
        this.requestId = imageInfo.requestId
        this.armSettleTimeout(epoch)
      },
      onLoadSuccess: (imageInfo: ImageInfo) => {
        if (!this.isCurrent(epoch)) {
          return
        }
        if (imageInfo.imageWidth > 0 && imageInfo.imageHeight > 0) {
          this.onImageInfo(imageInfo.imageWidth, imageInfo.imageHeight)
        }
        this.markComplete(epoch)
      },
      onLoadFailed: (_err: string, imageInfo: ImageInfo) => {
        this.retryOrFail('load_failed', imageInfo.requestId, epoch)
      },
    }
    option.onComplete = (_event: EventImage | undefined) => {
      this.markComplete(epoch)
    }
    if (this.radius > 0) {
      option.border = { radius: this.radius }
    }
    this.option = option
    this.updateNativeRoot()
  }

  private invalidateRequest(): void {
    this.clearTimers()
    this.requestEpoch += 1
    this.requestId = ''
    this.retriesUsed = 0
    this.completionNotified = true
  }

  private markComplete(epoch: number): void {
    if (!this.isCurrent(epoch) || this.completionNotified) {
      return
    }
    this.completionNotified = true
    this.clearTimers()
    this.onComplete()
  }

  private retryOrFail(reason: string, callbackRequestId: string, epoch: number): void {
    if (!this.isCurrent(epoch) || this.completionNotified || this.retryTimerId > 0) {
      return
    }
    this.clearSettleTimer()
    if (callbackRequestId.length > 0) {
      this.requestId = callbackRequestId
    }
    const allowedRetries: number = Math.max(0, this.maxRetries)
    if (this.retriesUsed >= allowedRetries || this.requestId.length === 0) {
      this.markFailed(reason, epoch)
      return
    }
    this.retriesUsed += 1
    DiagnosticLogger.warn(
      'image',
      'thumbnail_retry',
      `reason=${reason} attempt=${this.retriesUsed}/${allowedRetries} urlHash=${DiagnosticLogger.ownerHash(this.src)}`,
    )
    const requestId: string = this.requestId
    const delayMs: number = Math.max(0, this.retryDelayMs)
    this.retryTimerId = setTimeout((): void => {
      this.retryTimerId = 0
      if (!this.isCurrent(epoch) || this.completionNotified) {
        return
      }
      try {
        ImageKnife.getInstance().reload(requestId)
        this.armSettleTimeout(epoch)
      } catch (_error) {
        this.markFailed('reload_failed', epoch)
      }
    }, delayMs)
  }

  private markFailed(reason: string, epoch: number): void {
    if (!this.isCurrent(epoch) || this.completionNotified) {
      return
    }
    this.completionNotified = true
    this.clearTimers()
    DiagnosticLogger.warn(
      'image',
      'thumbnail_failed',
      `reason=${reason} retries=${this.retriesUsed} urlHash=${DiagnosticLogger.ownerHash(this.src)}`,
    )
    this.onError()
  }

  private armSettleTimeout(epoch: number): void {
    this.clearSettleTimer()
    if (this.settleTimeoutMs <= 0 || !this.isCurrent(epoch) || this.completionNotified) {
      return
    }
    this.settleTimerId = setTimeout((): void => {
      this.settleTimerId = 0
      this.retryOrFail('timeout', this.requestId, epoch)
    }, this.settleTimeoutMs)
  }

  private clearSettleTimer(): void {
    if (this.settleTimerId > 0) {
      clearTimeout(this.settleTimerId)
      this.settleTimerId = 0
    }
  }

  private clearTimers(): void {
    this.clearSettleTimer()
    if (this.retryTimerId > 0) {
      clearTimeout(this.retryTimerId)
      this.retryTimerId = 0
    }
  }

  private isCurrent(epoch: number): boolean {
    return epoch === this.requestEpoch
  }

  private updateNativeRoot(): void {
    if (!this.nativeRootAttached || this.nativeComponentId.length === 0) {
      return
    }
    nativeNode.updateNativeRoot(
      this.nativeComponentId,
      this.option,
      false,
      this.defaultContext(),
    )
  }

  private defaultContext(): common.UIAbilityContext | undefined {
    const context = getContext(this)
    return context === undefined ? undefined : context as common.UIAbilityContext
  }

  private headers(): HeaderOptions[] {
    return ImageKnifeProRuntime.defaultHeaders()
  }

  private imageKnifePriority(): Priority {
    if (this.priority === EH_IMAGE_PRIORITY_HIGH) {
      return Priority.HIGH
    }
    if (this.priority === EH_IMAGE_PRIORITY_LOW) {
      return Priority.LOW
    }
    return Priority.MEDIUM
  }

  private imageKnifeDownSampling(): DownSamplingStrategy {
    if (this.downSampling === EH_IMAGE_DOWNSAMPLING_NONE) {
      return DownSamplingStrategy.NONE
    }
    if (this.downSampling === EH_IMAGE_DOWNSAMPLING_FIT_CENTER_MEMORY) {
      return DownSamplingStrategy.FIT_CENTER_MEMORY
    }
    if (this.downSampling === EH_IMAGE_DOWNSAMPLING_FIT_CENTER_QUALITY) {
      return DownSamplingStrategy.FIT_CENTER_QUALITY
    }
    if (this.downSampling === EH_IMAGE_DOWNSAMPLING_CENTER_INSIDE_MEMORY) {
      return DownSamplingStrategy.CENTER_INSIDE_MEMORY
    }
    if (this.downSampling === EH_IMAGE_DOWNSAMPLING_CENTER_INSIDE_QUALITY) {
      return DownSamplingStrategy.CENTER_INSIDE_QUALITY
    }
    if (this.downSampling === EH_IMAGE_DOWNSAMPLING_AT_LEAST) {
      return DownSamplingStrategy.AT_LEAST
    }
    if (this.downSampling === EH_IMAGE_DOWNSAMPLING_AT_MOST) {
      return DownSamplingStrategy.AT_MOST
    }
    if (this.downSampling === EH_IMAGE_DOWNSAMPLING_DESIRED_SIZE_FILL) {
      return DownSamplingStrategy.DESIRED_SIZE_FILL
    }
    if (this.downSampling === EH_IMAGE_DOWNSAMPLING_DESIRED_SIZE_ASPECT_FIT) {
      return DownSamplingStrategy.DESIRED_SIZE_ASPECT_FIT
    }
    if (this.downSampling === EH_IMAGE_DOWNSAMPLING_DESIRED_SIZE_ASPECT_FILL) {
      return DownSamplingStrategy.DESIRED_SIZE_ASPECT_FILL
    }
    return DownSamplingStrategy.DEFAULT
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      ContentSlot(this.nativeRootSlot)
    }
      .width(this.widthValue)
      .height(this.heightValue)
  }
}
