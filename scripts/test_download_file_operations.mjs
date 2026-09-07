// Run with Node.js 22.13+ (built-in TypeScript stripping); no external dependencies.
import assert from 'node:assert/strict'
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import vm from 'node:vm'
import { stripTypeScriptTypes } from 'node:module'

// Execute the production methods without loading HarmonyOS UI/network modules.
// The encoder adapter preserves the documented encodeInto('') => undefined behavior.
const source = fs.readFileSync(process.argv[2] ?? new URL('../shared/src/main/ets/settings/DownloadQueueSettings.ets', import.meta.url), 'utf8')
const methods = [
  'safePathPart', 'utf8ByteLength', 'pathTitlePart', 'galleryDirName', 'galleryTaskPathTitle',
  'galleryQuality', 'sameGalleryTask', 'joinPath', 'pushUniquePath', 'galleryRootDirs',
  'galleryOwnerDirForFile', 'galleryContentDirs', 'deleteGalleryContent', 'deleteRequiredPath', 'writeTextFile',
]
const bodies = methods.map(name => {
  const start = source.indexOf(`  private static ${name}(`)
  assert(start >= 0, name)
  const end = source.indexOf('\n  }', start)
  return source.slice(start, end + 4)
}).join('\n')
const constants = ['DOWNLOAD_PATH_SEGMENT_MAX_BYTES', 'DOWNLOAD_PATH_TITLE_MAX_LENGTH', 'DOWNLOAD_GALLERY_DIR', 'DOWNLOAD_METADATA_FILE']
  .map(name => source.match(new RegExp(`^const ${name}: [^\\n]+`, 'm'))[0]).join('\n')
const warnings = []
const io = {
  OpenMode: { READ_WRITE: fs.constants.O_RDWR, CREATE: fs.constants.O_CREAT, TRUNC: fs.constants.O_TRUNC },
  openSync: (p, flags) => ({ fd: fs.openSync(p, flags) }),
  closeSync: file => fs.closeSync(file.fd),
  writeSync: (fd, buffer) => fs.writeSync(fd, Buffer.from(buffer)),
  statSync: fs.statSync,
  listFileSync: fs.readdirSync,
  readTextSync: p => fs.readFileSync(p, 'utf8'),
  unlinkSync: fs.unlinkSync,
  rmdirSync: p => fs.rmSync(p, { recursive: true }),
  accessSync: p => {
    try { fs.accessSync(p); return true } catch (error) {
      if (error.code === 'ENOENT') return false
      throw error
    }
  },
}
const context = vm.createContext({
  fs: io,
  util: { TextEncoder: class {
    encodeInto(value) { return value.length === 0 ? undefined : new TextEncoder().encode(value) }
  } },
  DiagnosticLogger: { info() {}, warn: (...args) => warnings.push(args) },
})
vm.runInContext(stripTypeScriptTypes(`${constants}\nclass DownloadQueueSettings {\n${bodies}\n}\nthis.subject = DownloadQueueSettings`), context)
const subject = context.subject
subject.parse = JSON.parse
const fixture = fs.mkdtempSync(path.join(os.tmpdir(), 'nexte-download-files-'))
let failures = 0
const test = (name, body) => {
  try { body(); console.log(`PASS ${name}`) } catch (error) { failures++; console.error(`FAIL ${name}: ${error.message}`) }
}
try {
  test('empty and multilingual UTF-8 byte lengths', () => {
    for (const text of ['', 'A', '中文', '🌍']) assert.equal(subject.utf8ByteLength(text), Buffer.byteLength(text))
  })
  test('resampled and original paths retain separate ownership', () => {
    assert.equal(subject.galleryDirName('100', false, '日本語'), '100-日本語')
    assert.equal(subject.galleryDirName('100', true, '日本語'), '100-日本語-original')
    assert.equal(subject.galleryDirName('100', false, ''), '100')
  })
  test('long multilingual paths respect the 255-byte segment limit', () => {
    for (const original of [false, true]) {
      const name = subject.galleryDirName('100', original, '中文🌍'.repeat(80))
      assert(Buffer.byteLength(name) <= 255)
      assert.equal(Buffer.from(name).toString('utf8'), name)
      assert.equal(name.endsWith('-original'), original)
    }
  })
  test('empty metadata marker creates/truncates a file without an error', () => {
    const marker = path.join(fixture, '.nomedia')
    fs.writeFileSync(marker, 'old contents')
    warnings.length = 0
    subject.writeTextFile(marker, '', 'write-test')
    assert.equal(fs.statSync(marker).size, 0)
    assert.equal(warnings.length, 0)
    fs.unlinkSync(marker)
    subject.writeTextFile(marker, '', 'write-test')
    assert.equal(fs.statSync(marker).size, 0)
    assert.equal(warnings.length, 0)
  })
  test('nonempty metadata preserves UTF-8 content', () => {
    const target = path.join(fixture, 'metadata.json')
    const text = JSON.stringify({ title: '中文🌍' })
    subject.writeTextFile(target, text, 'write-test')
    assert.equal(fs.readFileSync(target, 'utf8'), text)
  })
  test('delete skips ordinary files and preserves the other quality and unrelated tasks', () => {
    subject.downloadPublicRoot = fixture
    const root = path.join(fixture, 'download-gallery')
    fs.mkdirSync(root)
    fs.writeFileSync(path.join(root, '.nomedia'), '')
    fs.writeFileSync(path.join(root, 'notes.txt'), 'keep me')
    const task = { gid: '100', token: 'test', title: 'new title', titleJp: '', preferOriginal: true, imageSeeds: [] }
    // Use original quality here so the pre-fix test reaches directory scanning.
    const current = path.join(root, '100-new title-original')
    const old = path.join(root, '100-old title-original')
    const otherQuality = path.join(root, '100-new title')
    const unrelated = path.join(root, '200-other')
    for (const dir of [current, old, otherQuality, unrelated]) fs.mkdirSync(dir)
    fs.writeFileSync(path.join(old, 'metadata.json'), JSON.stringify([task]))
    fs.writeFileSync(path.join(otherQuality, 'metadata.json'), JSON.stringify([{ ...task, preferOriginal: false }]))
    fs.writeFileSync(path.join(unrelated, 'metadata.json'), JSON.stringify([{ ...task, gid: '200' }]))
    fs.writeFileSync(path.join(current, '0001.jpg'), 'fixture image bytes')
    subject.deleteGalleryContent(task)
    assert(!fs.existsSync(current)); assert(!fs.existsSync(old))
    assert(fs.existsSync(otherQuality)); assert(fs.existsSync(unrelated))
    assert(fs.existsSync(path.join(root, '.nomedia')))
    assert.equal(fs.readFileSync(path.join(root, 'notes.txt'), 'utf8'), 'keep me')
    // Repeating deletion after the owned files are absent is harmless.
    subject.deleteGalleryContent(task)
  })
} finally {
  fs.rmSync(fixture, { recursive: true, force: true })
}
process.exitCode = failures ? 1 : 0
