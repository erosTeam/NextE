import { describe, expect, it } from '@ohos/hypium'
import { EhUsertag, SimpleTag, UserTagStore } from 'shared'

function inlineTag(namespace: string, text: string, background: string, foreground: string): SimpleTag {
  const tag: SimpleTag = new SimpleTag(text, '', namespace)
  tag.backgroundColor = background
  tag.color = foreground
  return tag
}

export default function userTagStoreInlineCacheTest(): void {
  describe('UserTagStore inline fallback cache', () => {
    it('bounds derived aliases without changing the My Tags priority', 0, (done: Function) => {
      const store: UserTagStore = new UserTagStore(3)
      store.ingestInlineTags([inlineTag('artist', 'first', '#111111', '#eeeeee')])
      expect(store.inlineCacheSize()).assertEqual(3)
      expect(store.lookup('artist', 'first') === undefined).assertEqual(false)

      store.ingestInlineTags([inlineTag('artist', 'second', '#222222', '#dddddd')])
      expect(store.inlineCacheSize()).assertEqual(3)
      expect(store.lookup('artist', 'first') === undefined).assertEqual(true)
      const inline: EhUsertag | undefined = store.lookup('a', 'second')
      expect(inline === undefined ? '' : inline.fillColor).assertEqual('#222222')

      const userTag: EhUsertag = new EhUsertag()
      userTag.tag = 'artist:second'
      userTag.colorCode = '#abcdef'
      store.setTags([userTag])
      const resolved: EhUsertag | undefined = store.lookup('artist', 'second')
      expect(resolved === undefined ? '' : resolved.colorCode).assertEqual('#abcdef')
      done()
    })
  })
}
