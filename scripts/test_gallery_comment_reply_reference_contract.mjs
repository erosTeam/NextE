#!/usr/bin/env node
import fs from 'fs'
import path from 'path'

const ROOT = path.resolve(new URL('..', import.meta.url).pathname)
const card = fs.readFileSync(path.join(ROOT, 'feature/gallery/src/main/ets/components/GalleryCommentsCard.ets'), 'utf8')

let failures = 0
function ok(name, condition) {
  if (!condition) {
    console.error(`✗ ${name}`)
    failures += 1
  }
}

function codeDigit(code) {
  const map = {
    '····': '0', '···-': '1', '··-·': '2', '··--': '3', '·-··': '4',
    '·-·-': '5', '·--·': '6', '·---': '7', '-···': '8', '-··-': '9',
  }
  return map[code] ?? ''
}

function decode(line) {
  const code = line.replace(/\./g, '·').replace(/[^·-]/g, '')
  if (code.length === 0 || code.length % 4 !== 0) return ''
  let out = ''
  for (let i = 0; i < code.length; i += 4) {
    const digit = codeDigit(code.slice(i, i + 4))
    if (!digit) return ''
    out += digit
  }
  return out
}

ok('BCD reply marker decodes known comment id', decode('···-··-···--') === '123')
ok('dot fallback also decodes known comment id', decode('...-..-...--') === '123')
ok('bad marker does not decode', decode('---') === '')

ok('GalleryCommentsCard decodes BCD and #id# reply ids',
  /private decodeReplyId\(line: string\): string/.test(card) &&
  /private hashReplyId\(line: string\): string/.test(card) &&
  /private replyTargetId\(segment: string\): string/.test(card))
ok('reply parser scans every @ segment like eros_fe parserAllCommentRepty',
  /private replyReferences\(c: EhGalleryComment\): EhGalleryComment\[\][\s\S]*c\.contentText\.split\('@'\)[\s\S]*for \(let i = 1; i < segments\.length; i\+\+\)/.test(card))
ok('reply reference resolves explicit ids and loaded comments only',
  /private commentById\(id: string\): EhGalleryComment \| undefined[\s\S]*candidate\.commentId === id/.test(card) &&
  /this\.pushReply\(out, c, this\.commentById\(id\)\)/.test(card))
ok('reply reference falls back to FE-style recent author matching',
  /private sortedComments\(\): EhGalleryComment\[\][\s\S]*out\.sort/.test(card) &&
  /private candidateComments\(c: EhGalleryComment\): EhGalleryComment\[\]/.test(card) &&
  /private mentionToken\(segment: string\): string/.test(card) &&
  /private findByAuthor\(candidates: EhGalleryComment\[\], name: string\): EhGalleryComment \| undefined/.test(card) &&
  /private findBySpaceAuthor\(candidates: EhGalleryComment\[\], segment: string\): EhGalleryComment \| undefined/.test(card))
ok('resolved reply marker is hidden from the display body',
  /private displayContentText\(c: EhGalleryComment\): string[\s\S]*lines\.slice\(2\)\.join\('\\n'\)\.trim\(\)/.test(card) &&
  /lines\.slice\(1\)\.join\('\\n'\)\.trim\(\)/.test(card))
ok('unresolved reply marker falls back to plain comment text',
  /if \(this\.replyReferences\(c\)\.length === 0\) \{[\s\S]*return c\.contentText/.test(card))
ok('comment card renders a compact quote before the comment body',
  /this\.ReplyReferences\(c\)/.test(card) &&
  /@Builder\s+ReplyQuote\(c: EhGalleryComment\)/.test(card) &&
  /Text\(this\.quoteExcerpt\(c\.contentText\)\)/.test(card))

if (failures === 0) {
  console.log('✓ gallery comment reply reference contract passed')
  process.exit(0)
}
console.error(`✗ gallery comment reply reference contract: ${failures} failure(s)`)
process.exit(1)
