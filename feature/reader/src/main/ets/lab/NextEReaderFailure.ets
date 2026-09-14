import { ReaderAssetFailure } from '@reader-kit/core'
import { AppStrings } from 'shared'

/** NextE owns network semantics and localized copy; reader-kit only carries this presentation value. */
export class NextEReaderFailure {
  static from(error: Error): ReaderAssetFailure {
    const message = error.message.toLowerCase()
    if (message.indexOf('image509') >= 0 || message.indexOf('509') >= 0 || message.indexOf('quota') >= 0) {
      return new ReaderAssetFailure('quota', AppStrings.get('reader_error_quota'),
        AppStrings.get('reader_error_quota_hint'))
    }
    if (message.indexOf('429') >= 0 || message.indexOf('rate') >= 0 || message.indexOf('throttle') >= 0) {
      return new ReaderAssetFailure('rateLimited', AppStrings.get('reader_error_rate_limited'),
        AppStrings.get('reader_error_rate_limited_hint'))
    }
    return new ReaderAssetFailure('generic', AppStrings.get('image_load_failed'),
      AppStrings.get('reader_retry_source_hint'))
  }
}
