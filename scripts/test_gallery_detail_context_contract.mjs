#!/usr/bin/env node
/**
 * Contract test for gallery-detail request ownership.
 *
 * A detail response contains account-scoped favorite/rating/API fields, so cache reads, gdata,
 * HTML parsing, delayed tag translation, cache writes, and loading ownership must remain bound to
 * the account/site snapshot that issued the request. The model mirrors the ViewModel fence; the
 * source assertions lock the production boundary to the same shape.
 */
import assert from 'node:assert'
import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { dirname, join } from 'node:path'

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..')

class DetailModel {
  constructor() {
    this.epoch = 0
    this.gid = ''
    this.token = ''
    this.context = { member: 'A', pass: 'a', isEx: false }
    this.loading = false
    this.ui = ''
    this.cacheWrites = []
  }

  key(context, gid, token) {
    return `${context.isEx ? 'exhentai' : 'e-hentai'}:member:${context.member}:detail:${gid}:${token}`
  }

  begin(gid, token) {
    this.epoch += 1
    this.gid = gid
    this.token = token
    const context = { ...this.context }
    return {
      epoch: this.epoch,
      gid,
      token,
      ...context,
      cacheKey: this.key(context, gid, token),
    }
  }

  isCurrent(run) {
    return this.epoch === run.epoch &&
      this.gid === run.gid &&
      this.token === run.token &&
      this.context.member === run.member &&
      this.context.pass === run.pass &&
      this.context.isEx === run.isEx
  }

  start(gid = '1', token = 't') {
    const run = this.begin(gid, token)
    this.loading = true
    return run
  }

  publish(run, value) {
    if (!this.isCurrent(run)) return false
    this.ui = value
    this.cacheWrites.push(run.cacheKey)
    return true
  }

  finish(run) {
  if (this.isCurrent(run)) this.loading = false
  }
}

let passed = 0
function ok(name, condition) {
  assert.ok(condition, name)
  passed += 1
}

// An account replacement begins a new run immediately. The old cache/network/translation completion
// cannot repaint or write under the new account key, and cannot release the replacement's loading state.
{
  const vm = new DetailModel()
  const runA = vm.start()
  vm.context = { member: 'B', pass: 'b', isEx: false }
  const runB = vm.start()
  ok('account change makes the old detail run non-current', vm.isCurrent(runA) === false)
  ok('old account response cannot repaint the replacement detail', vm.publish(runA, 'A detail') === false && vm.ui === '')
  ok('old account response cannot write the new account cache', vm.cacheWrites.length === 0)
  vm.finish(runA)
  ok('old completion cannot clear the replacement loading state', vm.loading === true)
  ok('replacement detail publishes under its own account cache key', vm.publish(runB, 'B detail') && vm.cacheWrites[0].includes('member:B'))
  vm.finish(runB)
  ok('current replacement completion clears its own loading state', vm.loading === false)
}

// A site switch can become visible to the cookie store before the page monitor starts its replacement.
// The old translation/cache continuation must still be rejected and retain loading until replacement
// ownership begins, so no stale cursor/detail action can run in the handoff window.
{
  const vm = new DetailModel()
  const run = vm.start()
  vm.context = { member: 'A', pass: 'a', isEx: true }
  ok('site change rejects an old delayed detail translation', vm.publish(run, 'table detail') === false)
  ok('site mismatch prevents the old cache write', vm.cacheWrites.length === 0)
  vm.finish(run)
  ok('a context-only mismatch keeps the stale detail locked until replacement ownership starts', vm.loading === true)
  const replacement = vm.start()
  ok('replacement captures the new site cache scope', replacement.cacheKey.startsWith('exhentai:member:A:'))
}

const detailVm = readFileSync(
  join(ROOT, 'feature/gallery/src/main/ets/viewmodel/GalleryDetailViewModel.ets'),
  'utf8',
)
ok('detail run captures epoch, gallery identity, site, account credentials, and a frozen cache key',
  /class GalleryDetailRun \{[\s\S]*epoch: number[\s\S]*gid: string[\s\S]*token: string[\s\S]*isEx: boolean[\s\S]*memberId: string[\s\S]*passHash: string[\s\S]*cacheKey: string/.test(detailVm) &&
  /private beginDetailRun\(gid: string, token: string\): GalleryDetailRun \{[\s\S]*const isEx: boolean = connectSiteMode\(\)\.isEx[\s\S]*COOKIE_MEMBER_ID[\s\S]*COOKIE_PASS_HASH[\s\S]*EhPageCacheService\.galleryDetailKey\(isEx, gid, token\)/.test(detailVm))
ok('current-detail guard rejects account, credential, site, or gallery identity drift',
  /private isCurrentDetailRun\(run: GalleryDetailRun\): boolean \{[\s\S]*this\.detailEpoch !== run\.epoch[\s\S]*connectSiteMode\(\)\.isEx !== run\.isEx[\s\S]*COOKIE_MEMBER_ID\) === run\.memberId[\s\S]*COOKIE_PASS_HASH\) === run\.passHash/.test(detailVm))
ok('cache read and cache save use the issuing run key rather than a dynamic current-context key',
  /private async applyCachedDetailIfAvailable\(run: GalleryDetailRun\)[\s\S]*run\.cacheKey[\s\S]*!this\.isCurrentDetailRun\(run\)/.test(detailVm) &&
  /private async saveDetailCache\(run: GalleryDetailRun\)[\s\S]*!this\.isCurrentDetailRun\(run\)[\s\S]*saveGalleryDetail\(this\.context, run\.cacheKey, detail\)/.test(detailVm))
ok('network detail and gdata requests retain the issuing site snapshot',
  /getGalleryDetail\([\s\S]*run\.gid,[\s\S]*run\.token,[\s\S]*run\.isEx/.test(detailVm) &&
  /private async enrichFromApi\(run: GalleryDetailRun\)[\s\S]*EhConstants\.baseUrl\(run\.isEx\)/.test(detailVm))
ok('delayed cache translation, network translation, and reapply translation all re-check ownership',
  /translateCachedGalleryLater\([\s\S]*!this\.isCurrentDetailRun\(run\)/.test(detailVm) &&
  /private async fetchAndApply\(run: GalleryDetailRun[\s\S]*await this\.translateGallery\(merged\)[\s\S]*!this\.isCurrentDetailRun\(run\)/.test(detailVm) &&
  /async reapplyTagTranslation\(\): Promise<void> \{[\s\S]*const run: GalleryDetailRun \| null = this\.activeDetailRun[\s\S]*await this\.translateGallery\(source\)[\s\S]*!this\.isCurrentDetailRun\(run\)/.test(detailVm))
ok('replacement starts even while an old request is loading and only a current full context clears loading',
  /async reloadForContext\(\): Promise<void> \{[\s\S]*const run: GalleryDetailRun = this\.beginDetailRun\(this\.gid, this\.token\)[\s\S]*this\.loading = true/.test(detailVm) &&
  /if \(this\.isCurrentDetailRun\(run\)\) \{[\s\S]*this\.loading = false/.test(detailVm))
console.log(`✓ gallery detail context contract: ${passed} assertions passed`)
