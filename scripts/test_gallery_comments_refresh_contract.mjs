#!/usr/bin/env node
/**
 * Contract for the full GalleryComments page pull-to-refresh.
 *
 * The comments page must not be a stale snapshot forever:
 * eros_fe's CommentPage uses a refresh control, and NextE should re-fetch the current
 * gallery detail and replace only the comments list.
 *
 * Run: node scripts/test_gallery_comments_refresh_contract.mjs
 */
import fs from 'fs'

const read = (p) => fs.readFileSync(new URL(`../${p}`, import.meta.url), 'utf8')
let failures = 0
function ok(name, condition) {
  if (!condition) {
    console.error(`✗ ${name}`)
    failures += 1
  }
}

const params = read('shared/src/main/ets/model/RouteParams.ets')
ok('GalleryCommentsParams carries gid/token for refresh',
  /export class GalleryCommentsParams \{[\s\S]*gid: string = ''[\s\S]*token: string = ''[\s\S]*comments: EhGalleryComment\[\]/.test(params))
ok('GalleryCommentsParams constructor stores gid/token',
  /constructor\([\s\S]*gid: string = ''[\s\S]*token: string = ''[\s\S]*comments: EhGalleryComment\[\] = \[\][\s\S]*this\.gid = gid[\s\S]*this\.token = token/.test(params))

const detail = read('feature/gallery/src/main/ets/pages/GalleryDetailPage.ets')
ok('detail passes gid/token when opening full comments',
  /new GalleryCommentsParams\([\s\S]*this\.params\.gid[\s\S]*this\.params\.token[\s\S]*this\.vm\.comments[\s\S]*this\.navTitle\(\)/.test(detail))

const page = read('feature/gallery/src/main/ets/pages/GalleryCommentsPage.ets')
ok('comments page uses PullRefreshListScaffold, not a static SecondaryListScaffold',
  /PullRefreshListScaffold\(\{[\s\S]*controller: this\.refreshController[\s\S]*onRefresh: async \(\) => \{[\s\S]*await this\.refreshComments\(\)/.test(page) &&
    !/SecondaryListScaffold/.test(page))
ok('comments page keeps a local comments list refreshed from route params',
  /@Local comments: EhGalleryComment\[\] = \[\]/.test(page) &&
    /this\.comments = p\.comments/.test(page) &&
    /ForEach\(\s*this\.visibleComments\(\)[\s\S]*comments:\s*\[comment\][\s\S]*referenceComments:\s*this\.comments/.test(page))
ok('comments page auto-refreshes when opened directly without seeded comments',
  /@Local initialRefreshStarted: boolean = false/.test(page) &&
    /private scheduleInitialRefreshIfNeeded\(\): void[\s\S]*this\.comments\.length > 0[\s\S]*this\.params\.gid\.length === 0[\s\S]*this\.refreshController\.triggerTopRefresh\(\)/.test(page) &&
    /this\.scheduleInitialRefreshIfNeeded\(\)/.test(page))
ok('refresh fetches the same gallery detail and replaces comments',
  /private async refreshComments\(\): Promise<void>[\s\S]*getGalleryDetail\([\s\S]*this\.params\.gid[\s\S]*this\.params\.token[\s\S]*connectSiteMode\(\)\.isEx[\s\S]*this\.comments = result\.comments/.test(page))
ok('refresh backfills api metadata so direct-open comments can vote',
  /this\.params\.apikey = result\.gallery\.apikey/.test(page) &&
    /this\.params\.apiuid = result\.gallery\.apiuid/.test(page))
ok('refresh has bounded diagnostics and failure feedback',
  /comments_refresh_ok[\s\S]*comments=\$\{this\.comments\.length\}/.test(page) &&
    /comments_refresh_failed/.test(page) &&
    /throw new Error\(this\.errorMessage\)/.test(page))
const refreshMethod = page.match(/private async refreshComments\(\): Promise<void>[\s\S]*?^\s*}\n/m)
ok('comments refresh itself does not submit comment writes',
  refreshMethod !== null && !/voteComment|postComment|submitCommentVote/.test(refreshMethod[0]))

if (failures === 0) {
  console.log('✓ gallery comments refresh contract passed')
  process.exit(0)
}
console.error(`✗ gallery comments refresh contract: ${failures} failure(s)`)
process.exit(1)
