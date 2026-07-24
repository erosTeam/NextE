import { ComicProviderHttpError, ComicProviderStageError } from './ComicResponsesPageAnalyzer'

/** Converts provider/parser errors into fixed non-sensitive UI and diagnostic codes. */
export class ComicTranslationErrorClassifier {
  static classify(error: Error): string {
    if (error instanceof ComicProviderHttpError) {
      if (error.detailCode.length > 0) {
        return `http_${error.statusCode}_${error.detailCode}`
      }
      return `http_${error.statusCode}`
    }
    if (error instanceof ComicProviderStageError) {
      return `provider_${error.stageCode}_${error.detailCode}`
    }
    const message: string = error.message.toLowerCase()
    if (message.includes('project identity mismatch')) {
      return 'output_identity_project'
    }
    if (message.includes('page identity mismatch')) {
      return 'output_identity_page'
    }
    if (message.includes('image identity mismatch')) {
      return 'output_identity_image'
    }
    if (message.includes('image width mismatch') || message.includes('image height mismatch')) {
      return 'output_identity_dimensions'
    }
    if (message.includes('analyzer result identity') || message.includes('repository document identity')) {
      return 'output_identity_runtime'
    }
    if (message.includes('hastext')) {
      return 'output_has_text_invalid'
    }
    if (message.includes('reading order')) {
      return 'output_reading_order_invalid'
    }
    if (message.includes('quality signal')) {
      return 'output_quality_signal_invalid'
    }
    if (message.includes('polygon') || message.includes('region bounds') ||
      message.includes('region is outside the source image')) {
      return 'output_geometry_invalid'
    }
    if (message.includes('block')) {
      return 'output_block_invalid'
    }
    if (message.includes('source origin') || message.includes('translation origin')) {
      return 'output_origin_invalid'
    }
    if (message.includes('payload size') || message.includes('file size')) {
      return 'output_payload_size_invalid'
    }
    if (message.includes('rendered page artifact')) {
      return 'render_artifact_invalid'
    }
    if (message.includes('comic page contains no detected text')) {
      return 'no_translatable_text'
    }
    if (message.includes('stream failed')) {
      return 'provider_stream_failed'
    }
    if (message.includes('harmony device ocr') || message.includes('local comic')) {
      return 'local_visual_unavailable'
    }
    if (message.includes('timeout') || message.includes('network') || message.includes('dns') ||
      message.includes('socket') || message.includes('connection') || message.includes('certificate')) {
      return 'provider_transport_failed'
    }
    if (message.includes('manga rendering service')) {
      return 'rendering_service_configuration'
    }
    if (message.includes('credential') || message.includes('api key') ||
      message.includes('model') || message.includes('base url') || message.includes('oauth')) {
      return 'provider_configuration'
    }
    if (message.includes('manifest') || message.includes('fixture') || message.includes('rawfile')) {
      return 'fixture_invalid'
    }
    if (message.includes('mime type')) {
      return 'image_format_unsupported'
    }
    if (message.includes('image file') || message.includes('image source')) {
      return 'image_unavailable'
    }
    if (message.includes('response') || message.includes('schema') ||
      message.includes('document') || message.includes('json')) {
      if (message.includes('response_format')) {
        return 'provider_model_incompatible'
      }
      return 'structured_output_invalid'
    }
    return 'provider_request_failed'
  }
}
