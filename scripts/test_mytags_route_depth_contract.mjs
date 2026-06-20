#!/usr/bin/env node
/**
 * Contract: MyTags tagset selection must create real route depth.
 *
 * The tagset landing page and a tagset detail are two navigation states. Tapping a
 * tagset must push a route param so system Back returns to the tagset list, not
 * exit directly to Settings.
 *
 * Run: node scripts/test_mytags_route_depth_contract.mjs
 */
import { readFileSync } from 'node:fs'
import { join } from 'node:path'

const ROOT = process.cwd()
const page = readFileSync(join(ROOT, 'feature/user/src/main/ets/pages/MyTagsPage.ets'), 'utf8')
const routeParams = readFileSync(join(ROOT, 'shared/src/main/ets/model/RouteParams.ets'), 'utf8')
const sharedBarrel = readFileSync(join(ROOT, 'shared/src/main/ets/Index.ets'), 'utf8')
const userBarrel = readFileSync(join(ROOT, 'feature/user/src/main/ets/Index.ets'), 'utf8')
const index = readFileSync(join(ROOT, 'entry/src/main/ets/pages/Index.ets'), 'utf8')
const intake = readFileSync(join(ROOT, 'docs/plans/active/intake/write-operations.md'), 'utf8')
const feMytagsPage = readFileSync(join(ROOT, '../eros_fe/lib/pages/setting/mytags/eh_mytags_page.dart'), 'utf8')

let failures = 0
function ok(condition, message) {
  if (!condition) {
    failures += 1
    console.error(`✗ ${message}`)
  } else {
    console.log(`✓ ${message}`)
  }
}

ok(
  /Get\.toNamed\([\s\S]*EHRoutes\.userTags/.test(feMytagsPage),
  'eros_fe reference pushes a user-tags detail route from the tagset list',
)

ok(
  /export class MyTagsPageParams[\s\S]*tagsetId: string = ''[\s\S]*constructor\(tagsetId: string = ''\)/.test(routeParams) &&
    /MyTagsPageParams/.test(sharedBarrel),
  'NextE exposes typed MyTags route params',
)

ok(
  /import \{ FavoriteSelectorPage, FavoritesPage, MyTagsPage, ViewedHistoryPage \} from 'user'/.test(index) &&
    /name === 'MyTags'[\s\S]*MyTagsPage\(\)/.test(index) &&
    /export \{ MyTagsPage \} from '\.\/pages\/MyTagsPage'/.test(userBarrel),
  'Index still routes MyTags through the shared destination host',
)

ok(
  /private stack: NavPathStack = connectNavStack\(\)\.stack/.test(page) &&
    /private selectTagset\(id: string\): void \{[\s\S]*this\.stack\.pushPathByName\('MyTags', new MyTagsPageParams\(id\)\)/.test(page),
  'selecting a tagset pushes a MyTags detail route with tagset params',
)

ok(
  !/private selectTagset\(id: string\): void \{[\s\S]*this\.load\(id\)/.test(page) &&
    !/private selectTagset\(id: string\): void \{[\s\S]*this\.showingTagsetList = false/.test(page),
  'selectTagset no longer mutates the same page into detail mode',
)

ok(
  /\.onReady\(\(context: NavDestinationContext\) => \{[\s\S]*context\.pathInfo\.param instanceof MyTagsPageParams[\s\S]*this\.params = context\.pathInfo\.param as MyTagsPageParams[\s\S]*this\.load\(this\.params\.tagsetId\)/.test(page),
  'MyTags page consumes route params onReady and loads the routed tagset',
)

ok(
  /Status: implemented \/ pending controller acceptance/.test(intake) &&
    /route depth/.test(intake) &&
    /system back returns to MyTags tagset list/.test(intake),
  'write-operations intake records the route-depth fix status and acceptance target',
)

if (failures > 0) {
  console.error(`\n✗ mytags route-depth contract: ${failures} failure(s)`)
  process.exit(1)
}

console.log('\n✓ mytags route-depth contract passed')
