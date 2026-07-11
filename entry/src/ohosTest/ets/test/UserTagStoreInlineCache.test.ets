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

    it('clears server rules and inline fallbacks together at an account boundary', 0, (done: Function) => {
      const store: UserTagStore = new UserTagStore(12)
      const hidden: EhUsertag = new EhUsertag()
      hidden.tag = 'female:fixture'
      hidden.hidden = true
      store.setTags([hidden])
      store.ingestInlineTags([inlineTag('artist', 'fixture', '#112233', '#ddeeff')])

      expect(store.hasAny()).assertEqual(true)
      expect(store.isHidden('f', 'fixture')).assertEqual(true)
      expect(store.lookup('artist', 'fixture') === undefined).assertEqual(false)
      expect(store.inlineCacheSize() > 0).assertEqual(true)

      store.clear()

      expect(store.hasAny()).assertEqual(false)
      expect(store.isHidden('female', 'fixture')).assertEqual(false)
      expect(store.lookup('artist', 'fixture') === undefined).assertEqual(true)
      expect(store.inlineCacheSize()).assertEqual(0)
      done()
    })
  })
}
