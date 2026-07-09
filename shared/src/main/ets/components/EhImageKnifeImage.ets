import { ImageKnifeProImageAdapter } from '../services/ImageKnifeProImageAdapter'
import {
  EH_IMAGE_DOWNSAMPLING_DEFAULT,
  EH_IMAGE_PRIORITY_MEDIUM,
} from '../services/ImagePipelineTypes'

export { EH_IMAGE_PRIORITY_HIGH, EH_IMAGE_PRIORITY_LOW, EH_IMAGE_PRIORITY_MEDIUM } from '../services/ImagePipelineTypes'

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
  @Param downSampling: number = EH_IMAGE_DOWNSAMPLING_DEFAULT;
  @Param desiredWidth: number = 0;
  @Param desiredHeight: number = 0;
  @Event onComplete: () => void = () => {};
  @Event onImageInfo: (width: number, height: number) => void = (_width: number, _height: number) => {};
  @Event onError: () => void = () => {};
  @Event onProgress: (progress: number) => void = (_progress: number) => {};

  build() {
    ImageKnifeProImageAdapter({
      src: this.src,
      objectFit: this.objectFit,
      radius: this.radius,
      widthValue: this.widthValue,
      heightValue: this.heightValue,
      enableCache: this.enableCache,
      fileCacheName: this.fileCacheName,
      signature: this.signature,
      priority: this.priority,
      downSampling: this.downSampling,
      desiredWidth: this.desiredWidth,
      desiredHeight: this.desiredHeight,
      onComplete: this.onComplete,
      onImageInfo: this.onImageInfo,
      onError: this.onError,
      onProgress: this.onProgress,
    })
  }
}
