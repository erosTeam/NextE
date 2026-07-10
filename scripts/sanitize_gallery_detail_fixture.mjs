#!/usr/bin/env node
/**
 * Derive a tracked, structural gallery-detail fixture from a local capture without
 * copying account-scoped values, page content, image URLs, or image-page tokens.
 *
 * The input capture must stay outside source control. The output contains only the
 * parser-relevant DOM shells with deterministic placeholder values.
 *
 * Run:
 *   node scripts/sanitize_gallery_detail_fixture.mjs --input <capture.html> --output <fixture.html>
 */
import { readFileSync, writeFileSync } from 'node:fs'

function fail(message) {
  console.error(`✗ gallery-detail fixture sanitizer: ${message}`)
  process.exit(1)
}

function argument(name) {
  const index = process.argv.indexOf(name)
  if (index < 0 || index + 1 >= process.argv.length) {
    fail(`missing ${name}`)
  }
  return process.argv[index + 1]
}

function escapeRegExp(value) {
  return value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')
}

function outerElementById(html, id) {
  const open = new RegExp(`<([A-Za-z][A-Za-z0-9:-]*)\\b[^>]*\\bid=["']${escapeRegExp(id)}["'][^>]*>`, 'i').exec(html)
  if (open === null || open.index === undefined || open[1] === undefined) {
    fail(`missing #${id} in input`)
  }
  return outerElementFromOpen(html, open.index, open[1], `#${id}`)
}

function outerElementByClass(html, className) {
  const open = new RegExp(`<([A-Za-z][A-Za-z0-9:-]*)\\b[^>]*\\bclass=["'][^"']*\\b${escapeRegExp(className)}\\b[^"']*["'][^>]*>`, 'i').exec(html)
  if (open === null || open.index === undefined || open[1] === undefined) {
    fail(`missing .${className} in input`)
  }
  return outerElementFromOpen(html, open.index, open[1], `.${className}`)
}

function outerElementFromOpen(html, start, tagName, label) {
  const token = new RegExp(`<\\/?${escapeRegExp(tagName)}\\b[^>]*>`, 'ig')
  token.lastIndex = start
  let depth = 0
  let match = token.exec(html)
  while (match !== null) {
    const tag = match[0]
    if (tag.startsWith('</')) {
      depth -= 1
      if (depth === 0) {
        return html.substring(start, token.lastIndex)
      }
    } else if (!/\/$/.test(tag)) {
      depth += 1
    }
    match = token.exec(html)
  }
  fail(`unclosed ${label} in input`)
}

function setElementContent(element, content) {
  const openEnd = element.indexOf('>')
  const closeStart = element.lastIndexOf('</')
  if (openEnd < 0 || closeStart <= openEnd) {
    fail('unexpected element shape while setting content')
  }
  return `${element.substring(0, openEnd + 1)}${content}${element.substring(closeStart)}`
}

function replaceDetailCell(html, label, value) {
  const pattern = new RegExp(
    `(<td\\b[^>]*>\\s*${escapeRegExp(label)}\\s*<\\/td>\\s*<td\\b[^>]*>)[\\s\\S]*?(<\\/td>)`,
    'i',
  )
  if (!pattern.test(html)) {
    fail(`missing ${label} metadata cell in input`)
  }
  return html.replace(pattern, `$1${value}$2`)
}

function sanitizeTagList(tagList) {
  let result = tagList
  result = result.replace(
    /(<td\b[^>]*\bclass=["'][^"']*\btc\b[^"']*["'][^>]*>)[\s\S]*?(<\/td>)/gi,
    '$1fixture:$2',
  )
  result = result.replace(/\bid=["']ta_[^"']*["']/gi, 'id="ta_fixture:tag"')
  result = result.replace(/\bhref=["'][^"']*["']/gi, 'href="https://e-hentai.org/tag/fixture:tag"')
  result = result.replace(/\bonclick=["'][^"']*["']/gi, 'onclick="return false"')
  result = result.replace(/\btitle=["'][^"']*["']/gi, 'title="fixture"')
  return result.replace(/(<a\b[^>]*>)[\s\S]*?(<\/a>)/gi, '$1Fixture Tag$2')
}

function sanitizePreviewBlock(block) {
  let result = block
  result = result.replace(
    /href=["']https:\/\/(?:e-|ex)?hentai\.org\/s\/[0-9a-f]+\/\d+-(\d+)["']/gi,
    (_match, page) => `href="https://e-hentai.org/s/0000000000/100001-${page}"`,
  )
  result = result.replace(/url\(https:\/\/[^)]+\)/gi, 'url(https://fixture.invalid/preview-sheet.webp)')
  result = result.replace(/\bsrc=["']https:\/\/[^"']+["']/gi, 'src="https://fixture.invalid/preview.webp"')
  result = result.replace(/\btitle=["']Page\s+(\d+)[^"']*["']/gi, (_match, page) => `title="Page ${page}: fixture"`)
  return result
}

function normalizeSensitiveLinks(html) {
  return html
    .replace(
      /https:\/\/(?:e-|ex)?hentai\.org\/g\/\d+\/[0-9a-f]+\//gi,
      'https://e-hentai.org/g/100002/aaaaaaaaaa/',
    )
    .replace(/\/g\/\d+\/[0-9a-f]+\//gi, '/g/100002/aaaaaaaaaa/')
    .replace(
      /https:\/\/(?:e-|ex)?hentai\.org\/s\/[0-9a-f]+\/\d+-(\d+)/gi,
      (_match, page) => 'https://e-hentai.org/s/0000000000/100001-' + page,
    )
    .replace(/\/s\/[0-9a-f]+\/\d+-(\d+)/gi, (_match, page) => '/s/0000000000/100001-' + page)
    .replace(/\/g\/[^"'\s<)]*/gi, '/g/100002/aaaaaaaaaa/')
    .replace(/\/s\/[^"'\s<)]*/gi, '/s/0000000000/100001-1')
}

function sanitizeFixture(raw) {
  const englishTitle = setElementContent(outerElementById(raw, 'gn'), 'Fixture English Title')
  const japaneseTitle = setElementContent(outerElementById(raw, 'gj'), 'Fixture Japanese Title')
  const category = outerElementById(raw, 'gdc')
  const uploaderElement = outerElementById(raw, 'gdn')
  const uploader = setElementContent(
    uploaderElement,
    '<a href="https://e-hentai.org/uploader/fixture">FixtureUploader</a>',
  )
  const cover = outerElementById(raw, 'gd1').replace(
    /url\(https:\/\/[^)]+\)/gi,
    'url(https://fixture.invalid/cover.webp)',
  )
  let details = outerElementById(raw, 'gdd')
  details = replaceDetailCell(details, 'Posted:', '2026-01-02 03:04')
  details = replaceDetailCell(details, 'Language:', 'English')
  details = replaceDetailCell(details, 'File Size:', '12.3 MiB')
  details = replaceDetailCell(details, 'Length:', '24 pages')
  details = replaceDetailCell(details, 'Favorited:', '12 times')
  details = replaceDetailCell(details, 'Visible:', 'Yes')
  details = replaceDetailCell(
    details,
    'Parent:',
    '<a href="https://e-hentai.org/g/100002/aaaaaaaaaa/">Fixture Parent</a>',
  )
  const ratingCount = setElementContent(outerElementById(raw, 'rating_count'), '42')
  const ratingImage = outerElementById(raw, 'rating_image')
  const favorite = setElementContent(outerElementById(raw, 'fav'), '')
  const tagList = sanitizeTagList(outerElementById(raw, 'taglist'))
  const pageNav = outerElementByClass(raw, 'ptt').replace(/\bhref=["'][^"']*["']/gi, 'href="#"')
  const previews = sanitizePreviewBlock(outerElementById(raw, 'gdt'))

  return normalizeSensitiveLinks([
    '<!doctype html>',
    '<!-- Sanitized structural fixture. Source capture stays local and is never committed. -->',
    englishTitle,
    japaneseTitle,
    category,
    uploader,
    cover,
    details,
    ratingCount,
    ratingImage,
    favorite,
    tagList,
    '<p>Torrent Download (1)</p>',
    '<a onclick="return popUp(\'archiver.php?gid=100001&amp;token=0000000000\')">Archive Download</a>',
    pageNav,
    previews,
    '<script>var average_rating = 4.5; var apiuid = 0; var apikey = "00000000000000000000000000000000";</script>',
    '',
  ].join('\n'))
}

function assertSafeFixture(html) {
  const forbidden = [
    ['comment container', /\bid=["']cdiv["']/i],
    ['EH cookie marker', /\b(?:ipb_member_id|ipb_pass_hash|igneous)\b/i],
    ['image-page control token', /\b(?:showkey|nl|or)=/i],
    ['unredacted image-page token', /\/s\/(?!0000000000\/)/i],
    ['unredacted gallery identity', /\/g\/(?!100002\/aaaaaaaaaa\/)/i],
  ]
  for (const [label, pattern] of forbidden) {
    if (pattern.test(html)) {
      fail(`output still contains ${label}`)
    }
  }
  const apiuidValues = [...html.matchAll(/var\s+apiuid\s*=\s*([^;]+);/gi)].map((match) => match[1].trim())
  if (apiuidValues.length !== 1 || apiuidValues[0] !== '0') {
    fail('output still contains non-placeholder apiuid')
  }
  const apikeyValues = [...html.matchAll(/var\s+apikey\s*=\s*"([^"]+)";/gi)].map((match) => match[1])
  if (apikeyValues.length !== 1 || apikeyValues[0] !== '00000000000000000000000000000000') {
    fail('output still contains non-placeholder apikey')
  }
  if (!html.includes('id="gdt"') || !html.includes('class="ptt"') || !html.includes('id="taglist"')) {
    fail('output lost required parser structure')
  }
}

const input = argument('--input')
const output = argument('--output')
const raw = readFileSync(input, 'utf8')
const fixture = sanitizeFixture(raw)
assertSafeFixture(fixture)
writeFileSync(output, fixture, 'utf8')
console.log(`✓ wrote sanitized gallery-detail fixture (${fixture.length} bytes)`)
