import { abilityDelegatorRegistry } from '@kit.TestKit'
import { application } from '@kit.AbilityKit'
import { describe, expect, it } from '@ohos/hypium'
import {
  EhGallery,
  EhGalleryDetailParser,
  EhGalleryImageParser,
  SimpleTag,
  TagGroup,
} from 'shared'

const FIXTURE_MODULE: string = 'entry_test'
const FIXTURE_PATH: string = 'gallery_detail_standard.html'
const FIXTURE_APIKEY: string = '00000000000000000000000000000000'

async function loadFixture(): Promise<string> {
  const delegator = abilityDelegatorRegistry.getAbilityDelegator()
  const ability = await delegator.getCurrentTopAbility()
  const context = await application.createModuleContext(ability.context, FIXTURE_MODULE)
  let bytes: Uint8Array = new Uint8Array(0)
  try {
    bytes = await context.resourceManager.getRawFileContent(FIXTURE_PATH)
  } catch (_error) {
    return ''
  }
  let html: string = ''
  for (let index: number = 0; index < bytes.length; index++) {
    html += String.fromCharCode(bytes[index])
  }
  return html
}

export default function galleryDetailParserTest(): void {
  describe('GalleryDetailParser', () => {
    it('parses the sanitized standard-detail fixture through production parsers', 0, async (done: Function) => {
      const html: string = await loadFixture()
      const gallery = EhGalleryDetailParser.parse(html, '100001', 'fixture-token')
      const images = EhGalleryImageParser.parse(html)

      expect(html.length > 0).assertEqual(true)
      expect(gallery.englishTitle).assertEqual('Fixture English Title')
      expect(gallery.japaneseTitle).assertEqual('Fixture Japanese Title')
      expect(gallery.uploader).assertEqual('fixture')
      expect(gallery.fileCount).assertEqual('24')
      expect(gallery.rating).assertEqual(4.5)
      expect(gallery.ratingCount).assertEqual('42')
      expect(gallery.apiuid).assertEqual('0')
      expect(gallery.apikey).assertEqual(FIXTURE_APIKEY)
      expect(gallery.favcat).assertEqual('')
      expect(gallery.tagGroups.length > 0).assertEqual(true)
      expect(gallery.archiverLink).assertEqual('archiver.php?gid=100001&token=0000000000')
      expect(images.length > 0).assertEqual(true)
      expect(images[0].sUrl.startsWith('https://e-hentai.org/s/0000000000/100001-')).assertEqual(true)
      expect(EhGalleryImageParser.parsePageCount(html) > 1).assertEqual(true)
      done()
    })

    it('prefers the explicit content-language tag over the source-work info row', 0, () => {
      const gallery: EhGallery = new EhGallery()
      gallery.language = 'Japanese'
      gallery.tagGroups = [new TagGroup('language', [
        new SimpleTag('translated'),
        new SimpleTag('ukrainian'),
      ])]
      expect(gallery.contentLanguage()).assertEqual('ukrainian')

      const fallback: EhGallery = new EhGallery()
      fallback.language = 'Japanese'
      expect(fallback.contentLanguage()).assertEqual('Japanese')
    })
  })
}
