import { image } from '@kit.ImageKit'
import {
  CacheStrategy,
  DownSamplingStrategy,
  EventImage,
  HeaderOptions,
  ImageInfo,
  ImageKnifeComponentV2,
  ImageKnifeOptionV2,
  Priority,
} from '@ohos/imageknifepro'
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
  @Event onComplete: () => void = () => {};
  @Event onImageInfo: (width: number, height: number) => void = (_width: number, _height: number) => {};
  @Event onError: () => void = () => {};
  @Event onProgress: (progress: number) => void = (_progress: number) => {};
  @Local option: ImageKnifeOptionV2 = new ImageKnifeOptionV2();
  @Local completionNotified: boolean = false;

  aboutToAppear(): void {
    this.applyOption()
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
  )
  onOptionInputChanged(): void {
    this.applyOption()
  }

  private applyOption(): void {
    this.completionNotified = false
    const option: ImageKnifeOptionV2 = new ImageKnifeOptionV2()
    option.loadSrc = this.src
    option.objectFit = this.objectFit
    option.writeCacheStrategy = this.memoryOnly
      ? CacheStrategy.MEMORY
      : (this.enableCache ? CacheStrategy.DEFAULT : CacheStrategy.NONE)
    option.headerOption = this.headers()
    option.priority = this.imageKnifePriority()
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
      this.onProgress(progress)
    }
    option.onLoadListener = {
      onLoadSuccess: (imageInfo: ImageInfo) => {
        if (imageInfo.imageWidth > 0 && imageInfo.imageHeight > 0) {
          this.onImageInfo(imageInfo.imageWidth, imageInfo.imageHeight)
        }
        this.markComplete()
      },
      onLoadFailed: (_err: string, _imageInfo: ImageInfo) => {
        this.onError()
      },
    }
    option.onComplete = (_event: EventImage | undefined) => {
      this.markComplete()
    }
    if (this.radius > 0) {
      option.border = { radius: this.radius }
    }
    this.option = option
  }

  private markComplete(): void {
    if (this.completionNotified) {
      return
    }
    this.completionNotified = true
    this.onComplete()
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
    ImageKnifeComponentV2({
      imageKnifeOption: this.option,
      imageDraggable: false,
    })
      .width(this.widthValue)
      .height(this.heightValue)
  }
}
