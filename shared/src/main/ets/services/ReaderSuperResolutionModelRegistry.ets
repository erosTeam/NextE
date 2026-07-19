import { ReaderSuperResolutionModel } from '../state/ReadModeState'
import { ReaderNativeModelKind, ReaderNativeSuperResolutionConfig } from './ReaderNativeSuperResolution'

export enum ReaderSuperResolutionInstallStrategy {
  DIRECT = 'direct',
  REAL_ESRGAN_X2PLUS_COMPAT = 'realEsrganX2plusCompat',
  ESPCN_ONNX_ZIP = 'espcnOnnxZip',
}

/** Immutable runtime and download contract for one selectable local model. */
export class ReaderSuperResolutionModelDefinition {
  id: string = ''
  directoryName: string = ''
  paramFileName: string = ''
  modelFileName: string = ''
  paramBytes: number = 0
  modelBytes: number = 0
  paramSha256: string = ''
  modelSha256: string = ''
  paramUrls: string[] = []
  modelUrls: string[] = []
  packageBytes: number = 0
  packageSha256: string = ''
  packageUrls: string[] = []
  acceleratedModelFileName: string = ''
  acceleratedModelBytes: number = 0
  acceleratedModelSha256: string = ''
  acceleratedModelUrls: string[] = []
  installStrategy: string = ReaderSuperResolutionInstallStrategy.DIRECT
  pipelineVersion: string = ''
  nativeModelKind: number = ReaderNativeModelKind.WAIFU2X
  tileSize: number = 128
  prepadding: number = 7
  threads: number = 2
  inputName: string = 'Input1'
  outputName: string = 'Eltwise4'
  usageScopeStringKey: string = ''
  reference800pElapsedMs: number = 0
  initialDownloadBytes: number = 0

  bytes(): number {
    return this.paramBytes + this.modelBytes + this.acceleratedModelBytes
  }

  downloadBytes(): number {
    if (this.initialDownloadBytes > 0) {
      return this.initialDownloadBytes
    }
    const runtimeDownloadBytes: number = this.packageBytes > 0
      ? this.packageBytes
      : this.paramBytes + this.modelBytes
    return runtimeDownloadBytes + this.acceleratedModelBytes
  }

  nativeConfig(): ReaderNativeSuperResolutionConfig {
    const config: ReaderNativeSuperResolutionConfig = new ReaderNativeSuperResolutionConfig()
    config.modelKind = this.nativeModelKind
    config.tileSize = this.tileSize
    config.prepadding = this.prepadding
    config.threads = this.threads
    config.inputName = this.inputName
    config.outputName = this.outputName
    return config
  }
}

const WAIFU2X_REVISION: string = '64914665c45893135c9e50c1c296170a121b9f77'
const REAL_CUGAN_REVISION: string = '395302c5c70f1bff604c974e92e0a87e45c9f9ee'
const NCNN_RUNTIME_RELEASE_BASE: string =
  'https://github.com/erosTeam/NextE-Models/releases/download/ncnn-runtime-assets-v1'

function espcnDefinition(): ReaderSuperResolutionModelDefinition {
  const definition: ReaderSuperResolutionModelDefinition =
    new ReaderSuperResolutionModelDefinition()
  definition.id = ReaderSuperResolutionModel.ESPCN_X2
  definition.directoryName = 'espcn-2x-ncnn-v1'
  definition.paramFileName = 'espcn_x2.ncnn.param'
  definition.modelFileName = 'espcn_x2.ncnn.bin'
  definition.paramBytes = 587
  definition.modelBytes = 42780
  definition.paramSha256 = 'f9a70c5588dc2377e301c61729e9e488e564cca268c1f4c8d01bf259a83dd72a'
  definition.modelSha256 = '77d3889bbaf3db5748e87d216fc68c2107c7ca8d7ec1333e5158b566736af3c0'
  definition.packageBytes = 80589
  definition.packageSha256 = '11a286a0a761ec78a4f0ec17b905d2dbe12a19263e6315a25c08c6aaf983410c'
  definition.packageUrls = [
    `${NCNN_RUNTIME_RELEASE_BASE}/espcn-x2.zip`,
    'https://hailo-model-zoo.s3.eu-west-2.amazonaws.com/SuperResolution/' +
      'espcn/espcn_x2/2022-08-02/espcn_x2.zip',
  ]
  definition.acceleratedModelFileName = 'espcn-x2-180-fp16.ms'
  definition.acceleratedModelBytes = 45312
  definition.acceleratedModelSha256 =
    'f2e84f3ce9cfc1d326a5326c116c30b3d92a8ed91dade45c37097863e7cfc7cf'
  definition.acceleratedModelUrls = [
    'https://github.com/erosTeam/NextE-Models/releases/download/' +
      'espcn-x2-nnrt-v1/espcn-x2-180-fp16.ms',
  ]
  definition.initialDownloadBytes = 125901
  definition.installStrategy = ReaderSuperResolutionInstallStrategy.ESPCN_ONNX_ZIP
  definition.pipelineVersion =
    'espcn-x2-hailo-onnx-20220802-ncnn-20260526|nnrt-fp16-v1'
  definition.nativeModelKind = ReaderNativeModelKind.LUMINANCE
  definition.tileSize = 128
  definition.prepadding = 4
  definition.threads = 2
  definition.inputName = 'in0'
  definition.outputName = 'out0'
  definition.usageScopeStringKey = 'settings_reader_super_resolution_scope_fast_general'
  // Internal reference used only to select a device-dependent UI time tier.
  definition.reference800pElapsedMs = 5000
  return definition
}

function githubRawUrls(repository: string, revision: string, path: string): string[] {
  return [
    `https://raw.githubusercontent.com/${repository}/${revision}/${path}`,
    `https://github.com/${repository}/raw/${revision}/${path}`,
  ]
}

function waifu2xDefinition(
  id: string,
  directoryName: string,
  releaseBaseName: string,
  sourcePath: string,
  paramBytes: number,
  modelBytes: number,
  paramSha256: string,
  modelSha256: string,
  prepadding: number,
  usageScopeStringKey: string,
  reference800pElapsedMs: number,
): ReaderSuperResolutionModelDefinition {
  const definition: ReaderSuperResolutionModelDefinition =
    new ReaderSuperResolutionModelDefinition()
  definition.id = id
  definition.directoryName = directoryName
  definition.paramFileName = 'noise0_scale2.0x_model.param'
  definition.modelFileName = 'noise0_scale2.0x_model.bin'
  definition.paramBytes = paramBytes
  definition.modelBytes = modelBytes
  definition.paramSha256 = paramSha256
  definition.modelSha256 = modelSha256
  definition.paramUrls = [
    `${NCNN_RUNTIME_RELEASE_BASE}/${releaseBaseName}.param`,
    ...githubRawUrls(
      'nihui/waifu2x-ncnn-vulkan',
      WAIFU2X_REVISION,
      `${sourcePath}/${definition.paramFileName}`,
    ),
  ]
  definition.modelUrls = [
    `${NCNN_RUNTIME_RELEASE_BASE}/${releaseBaseName}.bin`,
    ...githubRawUrls(
      'nihui/waifu2x-ncnn-vulkan',
      WAIFU2X_REVISION,
      `${sourcePath}/${definition.modelFileName}`,
    ),
  ]
  definition.pipelineVersion = `waifu2x-${WAIFU2X_REVISION}-${directoryName}`
  definition.prepadding = prepadding
  definition.usageScopeStringKey = usageScopeStringKey
  definition.reference800pElapsedMs = reference800pElapsedMs
  return definition
}

function waifu2xPhotoDefinition(): ReaderSuperResolutionModelDefinition {
  const definition: ReaderSuperResolutionModelDefinition = waifu2xDefinition(
    ReaderSuperResolutionModel.WAIFU2X_PHOTO_NOISE0_2X,
    'waifu2x-photo-noise0-2x-ncnn-v1',
    'waifu2x-photo-noise0-2x',
    'models/models-upconv_7_photo',
    1047,
    1106248,
    '413195ffde05b4d43807792c6c020c916cecdf25dcf002ee83f5e28d5cc246c6',
    'fbfc8d57e4333748c9c6db2ec4d5454c98cd1c6aa53289f2989c3bdb4e84b673',
    7,
    'settings_reader_super_resolution_scope_scans_photos',
    3000,
  )
  definition.acceleratedModelFileName = 'waifu2x-photo-noise0-x2-156-fp16.ms'
  definition.acceleratedModelBytes = 1110528
  definition.acceleratedModelSha256 =
    'f39e877d84c3555e2150f63098fe0e21c6d426c7e054a5a32f2371d5e5f8e2c9'
  definition.acceleratedModelUrls = [
    'https://github.com/erosTeam/NextE-Models/releases/download/' +
      'waifu2x-photo-noise0-x2-nnrt-v4/waifu2x-photo-noise0-x2-156-fp16.ms',
  ]
  definition.initialDownloadBytes = 2217823
  definition.pipelineVersion += '|nnrt-fp16-v1'
  return definition
}

function realCuganDefinition(): ReaderSuperResolutionModelDefinition {
  const definition: ReaderSuperResolutionModelDefinition =
    new ReaderSuperResolutionModelDefinition()
  definition.id = ReaderSuperResolutionModel.REAL_CUGAN_SE_2X_CONSERVATIVE
  definition.directoryName = 'realcugan-se-2x-conservative-ncnn-v1'
  definition.paramFileName = 'up2x-conservative.param'
  definition.modelFileName = 'up2x-conservative.bin'
  definition.paramBytes = 4761
  definition.modelBytes = 2573648
  definition.paramSha256 = '4b3b5c5710ad1d00503c8243417aa75f13fe497723e8b4952e8b1abfc08f9b84'
  definition.modelSha256 = '91c72c136e7ff8556323d4449c5ceeff22d9829bf8463a01137cadb8d59b84a0'
  definition.paramUrls = githubRawUrls(
    'nihui/realcugan-ncnn-vulkan',
    REAL_CUGAN_REVISION,
    `models/models-se/${definition.paramFileName}`,
  )
  definition.modelUrls = githubRawUrls(
    'nihui/realcugan-ncnn-vulkan',
    REAL_CUGAN_REVISION,
    `models/models-se/${definition.modelFileName}`,
  )
  definition.paramUrls.unshift(
    `${NCNN_RUNTIME_RELEASE_BASE}/realcugan-se-2x-conservative.param`,
  )
  definition.modelUrls.unshift(
    `${NCNN_RUNTIME_RELEASE_BASE}/realcugan-se-2x-conservative.bin`,
  )
  definition.pipelineVersion = `realcugan-${REAL_CUGAN_REVISION}-se-2x-conservative-syncgap0`
  definition.prepadding = 18
  definition.inputName = 'in0'
  definition.outputName = 'out0'
  definition.usageScopeStringKey = 'settings_reader_super_resolution_scope_comics_conservative'
  definition.reference800pElapsedMs = 11598
  return definition
}

function realEsrganAnimeDefinition(): ReaderSuperResolutionModelDefinition {
  const definition: ReaderSuperResolutionModelDefinition =
    new ReaderSuperResolutionModelDefinition()
  definition.id = ReaderSuperResolutionModel.REAL_ESRGAN_ANIMEVIDEO_V3_X2
  definition.directoryName = 'realesrgan-animevideov3-2x-ncnn-v1'
  definition.paramFileName = 'realesr-animevideov3-x2.param'
  definition.modelFileName = 'realesr-animevideov3-x2.bin'
  definition.paramBytes = 3173
  definition.modelBytes = 1247368
  definition.paramSha256 = 'b88ff4f00ebf019a7fdac17fdd45a7fd3665d37509efc5baf2e4da2e24420a04'
  definition.modelSha256 = '548a36f9c3f4ab8da56cd3b13badf23968bee207b396dad14d04b830e5f2ab2d'
  // The pair is byte-verified against the official v0.2.5.0 ncnn release archive. This mirror keeps
  // the two files independently downloadable; the immutable hashes remain the trust boundary.
  definition.paramUrls = [
    'https://huggingface.co/datasets/Pratofeitoo/sd-upscalers/resolve/main/' +
      definition.paramFileName,
  ]
  definition.modelUrls = [
    'https://huggingface.co/datasets/Pratofeitoo/sd-upscalers/resolve/main/' +
      definition.modelFileName,
  ]
  definition.pipelineVersion = 'realesrgan-animevideov3-x2-official-v0.2.5.0'
  definition.nativeModelKind = ReaderNativeModelKind.REAL_ESRGAN
  definition.tileSize = 128
  definition.prepadding = 10
  definition.threads = 4
  definition.inputName = 'data'
  definition.outputName = 'output'
  definition.usageScopeStringKey = 'settings_reader_super_resolution_scope_animation_comics'
  definition.reference800pElapsedMs = 10597
  return definition
}

function realEsrganPhotoDefinition(): ReaderSuperResolutionModelDefinition {
  const definition: ReaderSuperResolutionModelDefinition =
    new ReaderSuperResolutionModelDefinition()
  definition.id = ReaderSuperResolutionModel.REAL_ESRGAN_X2PLUS
  definition.directoryName = 'realesrgan-x2plus-ncnn-fp32-v1'
  definition.paramFileName = 'realesrgan_x2plus.compat.param'
  definition.modelFileName = 'realesrgan_x2plus.bin'
  definition.paramBytes = 288376
  definition.modelBytes = 66814088
  definition.paramSha256 = 'b17f57a46574e28bbe405ed1d95edc99d6fa2abc777b477a2ba8399ffa3ea4dd'
  definition.modelSha256 = '80154ed738cd609c639fed031e9d2bc5d612f4895b91b73e623e88fa0c19f8b9'
  definition.acceleratedModelFileName = 'realesrgan-x2plus-180-fp16.ms'
  definition.acceleratedModelBytes = 33735064
  definition.acceleratedModelSha256 =
    'b6ee78c1e01d79fa5fb4ccb0b1bca039f804eb9c8f77e6c37b065869eb25866a'
  definition.acceleratedModelUrls = [
    'https://github.com/erosTeam/NextE-Models/releases/download/' +
      'realesrgan-x2plus-nnrt-v1/realesrgan-x2plus-180-fp16.ms',
  ]
  definition.initialDownloadBytes = 100841392
  definition.installStrategy = ReaderSuperResolutionInstallStrategy.REAL_ESRGAN_X2PLUS_COMPAT
  definition.pipelineVersion = 'realesrgan-x2plus-ncnn-fp32-compat-v1'
  definition.nativeModelKind = ReaderNativeModelKind.REAL_ESRGAN
  definition.tileSize = 128
  definition.prepadding = 10
  definition.threads = 4
  definition.inputName = 'input'
  definition.outputName = 'output'
  definition.usageScopeStringKey = 'settings_reader_super_resolution_scope_photos_textures'
  definition.reference800pElapsedMs = 88766
  return definition
}

const MODEL_DEFINITIONS: ReaderSuperResolutionModelDefinition[] = [
  espcnDefinition(),
  waifu2xPhotoDefinition(),
  waifu2xDefinition(
    ReaderSuperResolutionModel.WAIFU2X_ART_NOISE0_2X,
    'waifu2x-art-noise0-2x-ncnn-v1',
    'waifu2x-art-noise0-2x',
    'models/models-upconv_7_anime_style_art_rgb',
    1047,
    1106248,
    '413195ffde05b4d43807792c6c020c916cecdf25dcf002ee83f5e28d5cc246c6',
    'e1d2c4d91be98e72c0d48d08626cbe7d879aa2b80f740133dcc0d860eabb4189',
    7,
    'settings_reader_super_resolution_scope_comics_illustrations',
    7643,
  ),
  realEsrganAnimeDefinition(),
  waifu2xDefinition(
    ReaderSuperResolutionModel.WAIFU2X_CUNET_NOISE0_2X,
    'waifu2x-cunet-noise0-2x-ncnn-v1',
    'waifu2x-cunet-noise0-2x',
    'models/models-cunet',
    7249,
    2776400,
    'ccc3b2f1c9fad829ecdda40cac8dc853fcddf14917170efba888b256fbf9074a',
    '5329a9375c9cfb64a60a2903fd8ae6e2851d9b069556bf025dbab9d0216fb27c',
    18,
    'settings_reader_super_resolution_scope_comics_detail',
    11882,
  ),
  realCuganDefinition(),
  realEsrganPhotoDefinition(),
]

export class ReaderSuperResolutionModelRegistry {
  static all(): ReaderSuperResolutionModelDefinition[] {
    return MODEL_DEFINITIONS
  }

  static find(model: string): ReaderSuperResolutionModelDefinition | null {
    for (let i: number = 0; i < MODEL_DEFINITIONS.length; i++) {
      if (MODEL_DEFINITIONS[i].id === model) {
        return MODEL_DEFINITIONS[i]
      }
    }
    return null
  }
}
