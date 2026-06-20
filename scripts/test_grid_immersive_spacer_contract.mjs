#!/usr/bin/env node
/**
 * Contract: Grid mode must not use Grid top/bottom padding for immersive chrome insets.
 *
 * HarmonyOS Grid hides GridItems that are fully inside the padding area, so top/bottom chrome
 * avoidance must be represented as real full-row GridItems. Near-end paging should use visible
 * Grid indexes instead of waiting for the physical terminal edge.
 */
import { readFileSync } from 'node:fs'
import { join } from 'node:path'

const ROOT = process.cwd()
let failures = 0

function read(rel) {
  return readFileSync(join(ROOT, rel), 'utf8')
}

function ok(condition, message) {
  if (!condition) {
    failures += 1
    console.error(`✗ ${message}`)
  } else {
    console.log(`✓ ${message}`)
  }
}

function gridBranch(source) {
  const start = source.indexOf('this.listMode.mode === ListMode.GRID')
  if (start < 0) {
    return ''
  }
  const nextWaterfall = source.indexOf('this.listMode.mode === ListMode.WATERFALL', start + 1)
  const nextElse = source.indexOf('} else {', start + 1)
  let end = source.length
  if (nextWaterfall >= 0 && nextWaterfall < end) {
    end = nextWaterfall
  }
  if (nextElse >= 0 && nextElse < end) {
    end = nextElse
  }
  return source.slice(start, end)
}

const scaffold = read('shared/src/main/ets/components/PullRefreshGridScaffold.ets')

ok(
  /GridItem\(\) \{[\s\S]*Column\(\) \{[\s\S]*Blank\(\)[\s\S]*\.height\(this\.topSpacerHeight\(\)\)[\s\S]*\}\s*[\s\S]*\.width\('100%'\)[\s\S]*\}\s*[\s\S]*\.columnStart\(0\)[\s\S]*\.columnEnd\(this\.effectiveColumns\(\) - 1\)/.test(scaffold),
  'Grid scaffold uses a full-row top spacer GridItem',
)
ok(
  /GridItem\(\) \{[\s\S]*Column\(\) \{[\s\S]*Blank\(\)[\s\S]*\.height\(this\.bottomSpacerHeight\(\)\)[\s\S]*\}\s*[\s\S]*\.width\('100%'\)[\s\S]*\}\s*[\s\S]*\.columnStart\(0\)[\s\S]*\.columnEnd\(this\.effectiveColumns\(\) - 1\)/.test(scaffold),
  'Grid scaffold uses a full-row bottom spacer GridItem',
)
ok(
  !/\.padding\(\{\s*[\s\S]*top:\s*this\.layout\.topAvoidHeight[\s\S]*bottom:\s*this\.layout\.bottomAvoidHeight/.test(scaffold),
  'Grid scaffold does not put top/bottom immersive insets in Grid.padding',
)
ok(
  /\.padding\(\{\s*[\s\S]*left:\s*this\.horizontalPadding[\s\S]*right:\s*this\.horizontalPadding[\s\S]*\}\)/.test(scaffold),
  'Grid scaffold keeps horizontal padding only',
)
ok(
  /@Param itemCount: number = 0/.test(scaffold) &&
    /@Param nearEndThreshold: number = 0/.test(scaffold) &&
    /@Event onNearEnd\?: \(\) => void/.test(scaffold),
  'Grid scaffold exposes itemCount and near-end paging inputs',
)
ok(
  /\.onScrollIndex\(\(start: number, end: number\) => \{[\s\S]*this\.galleryIndex\(start\)[\s\S]*this\.galleryIndex\(end\)[\s\S]*this\.maybeLoadNearEnd\(adjustedEnd\)/.test(scaffold),
  'Grid scaffold translates raw spacer-inclusive indexes before near-end paging',
)
ok(
  /if \(this\.canStartBottomRefresh && !this\.canStartBottomRefresh\(\)\) \{[\s\S]*return[\s\S]*\}/.test(scaffold),
  'near-end paging respects the same canStartBottomRefresh guard as bottom pull',
)

const surfaces = [
  {
    name: 'Home',
    path: 'feature/home/src/main/ets/components/GalleryListBody.ets',
    viewModelPath: 'feature/home/src/main/ets/viewmodel/GalleryListViewModel.ets',
  },
  {
    name: 'Search',
    path: 'feature/search/src/main/ets/pages/GallerySearchPage.ets',
    viewModelPath: 'feature/search/src/main/ets/viewmodel/SearchViewModel.ets',
  },
  {
    name: 'Favorites',
    path: 'feature/user/src/main/ets/components/FavcatPage.ets',
    viewModelPath: 'feature/user/src/main/ets/viewmodel/FavoritesViewModel.ets',
  },
]

for (const surface of surfaces) {
  const source = read(surface.path)
  const branch = gridBranch(source)
  ok(branch.length > 0, `${surface.name} has a GRID branch`)
  ok(/PullRefreshGridScaffold\(\{/.test(branch), `${surface.name} GRID branch uses PullRefreshGridScaffold`)
  ok(/itemCount:\s*this\.vm\.itemCount/.test(branch), `${surface.name} passes current itemCount into grid scaffold`)
  ok(/nearEndThreshold:\s*4/.test(branch), `${surface.name} enables near-end paging threshold`)
  ok(/onNearEnd:\s*\(\) => \{[\s\S]*this\.vm\.loadMore\(\)/.test(branch), `${surface.name} near-end paging loads the next page`)
  ok(/canStartBottomRefresh:\s*\(\) => this\.vm\.canLoadMore\(\)/.test(branch), `${surface.name} keeps VM load-more guard wired`)

  const viewModel = read(surface.viewModelPath)
  ok(
    /async loadMore\(\): Promise<void> \{[\s\S]*if \([\s\S]*this\.isLoadingMore[\s\S]*!this\.hasMore[\s\S]*\) \{[\s\S]*return[\s\S]*\}/.test(viewModel),
    `${surface.name} ViewModel loadMore rejects duplicate or exhausted loads`,
  )
  ok(
    /canLoadMore\(\): boolean \{[\s\S]*return this\.hasMore && !this\.isLoadingMore/.test(viewModel),
    `${surface.name} ViewModel exposes the same duplicate-load guard to the scaffold`,
  )
}

if (failures > 0) {
  console.error(`\n✗ grid immersive spacer contract: ${failures} failure(s)`)
  process.exit(1)
}

console.log('\n✓ grid immersive spacer contract passed')
