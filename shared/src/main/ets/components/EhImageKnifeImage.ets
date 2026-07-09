import { image } from '@kit.ImageKit'
import {
  CacheStrategy,
  DownSamplingStrategy,
  HeaderOptions,
  ImageInfo,
  ImageKnifeComponentV2,
  ImageKnifeOptionV2,
  Priority,
} from '@ohos/imageknifepro'
import { ImageKnifeProRuntime } from '../services/ImageKnifeProRuntime'

export const EH_IMAGE_PRIORITY_HIGH: number = 0
export const EH_IMAGE_PRIORITY_MEDIUM: number = 1
export const EH_IMAGE_PRIORITY_LOW: number = 2

@ComponentV2
export struct EhImageKnifeImage {
  @Param src: string = '';
  @Param objectFit: ImageFit = ImageFit.Cover;
  @Param radius: number = 0;
  @Param widthValue: Length = '100%';
  @Param heightValue: Length = '100%';
  @Param enableCache: boolean = true;
  @Param fileCacheName: string = '';
  @Param signature: string = '';
  @Param priority: number = EH_IMAGE_PRIORITY_MEDIUM;
  @Param downSampling: DownSamplingStrategy = DownSamplingStrategy.DEFAULT;
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
    option.writeCacheStrategy = this.enableCache ? CacheStrategy.DEFAULT : CacheStrategy.NONE
    option.headerOption = this.headers()
    option.priority = this.imageKnifePriority()
    if (this.fileCacheName.length > 0) {
      option.fileCacheName = this.fileCacheName
    }
    if (this.signature.length > 0) {
      option.signature = this.signature
    }
    option.downSampling = this.downSampling
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
    option.onComplete = (_event) => {
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

  build() {
    ImageKnifeComponentV2({
      imageKnifeOption: this.option,
      imageDraggable: false,
    })
      .width(this.widthValue)
      .height(this.heightValue)
  }
}
