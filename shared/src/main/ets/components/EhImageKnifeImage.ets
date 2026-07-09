import {
  CacheStrategy,
  HeaderOptions,
  ImageInfo,
  ImageKnifeComponentV2,
  ImageKnifeOptionV2,
} from '@ohos/imageknifepro'
import { EhConstants } from '../constants/EhConstants'

@ComponentV2
export struct EhImageKnifeImage {
  @Param src: string = '';
  @Param objectFit: ImageFit = ImageFit.Cover;
  @Param radius: number = 0;
  @Param widthValue: Length = '100%';
  @Param heightValue: Length = '100%';
  @Param enableCache: boolean = true;
  @Event onComplete: () => void = () => {};
  @Event onImageInfo: (width: number, height: number) => void = (_width: number, _height: number) => {};
  @Event onError: () => void = () => {};
  @Local option: ImageKnifeOptionV2 = new ImageKnifeOptionV2();

  aboutToAppear(): void {
    this.applyOption()
  }

  @Monitor('src', 'objectFit', 'radius', 'enableCache')
  onOptionInputChanged(): void {
    this.applyOption()
  }

  private applyOption(): void {
    const option: ImageKnifeOptionV2 = new ImageKnifeOptionV2()
    option.loadSrc = this.src
    option.objectFit = this.objectFit
    option.writeCacheStrategy = this.enableCache ? CacheStrategy.DEFAULT : CacheStrategy.NONE
    option.headerOption = this.headers()
    option.onLoadListener = {
      onLoadSuccess: (imageInfo: ImageInfo) => {
        if (imageInfo.imageWidth > 0 && imageInfo.imageHeight > 0) {
          this.onImageInfo(imageInfo.imageWidth, imageInfo.imageHeight)
        }
        this.onComplete()
      },
      onLoadFailed: (_err: string, _imageInfo: ImageInfo) => {
        this.onError()
      },
    }
    option.onComplete = (_event) => {
      this.onComplete()
    }
    if (this.radius > 0) {
      option.border = { radius: this.radius }
    }
    this.option = option
  }

  private headers(): HeaderOptions[] {
    const headers: HeaderOptions[] = []
    headers.push({ key: 'User-Agent', value: EhConstants.USER_AGENT })
    headers.push({ key: 'Accept', value: 'image/avif,image/webp,image/apng,image/*,*/*;q=0.8' })
    headers.push({ key: 'Accept-Language', value: EhConstants.ACCEPT_LANGUAGE })
    return headers
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
