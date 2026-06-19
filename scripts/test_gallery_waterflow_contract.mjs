#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';

const root = process.cwd();

function read(rel) {
  return fs.readFileSync(path.join(root, rel), 'utf8');
}

function fail(message) {
  console.error(`gallery waterflow contract failed: ${message}`);
  process.exit(1);
}

function assertIncludes(source, needle, message) {
  if (!source.includes(needle)) {
    fail(message);
  }
}

function assertNotIncludes(source, needle, message) {
  if (source.includes(needle)) {
    fail(message);
  }
}

const scaffoldRel = 'shared/src/main/ets/components/PullRefreshWaterFlowScaffold.ets';
const scaffold = read(scaffoldRel);

assertIncludes(scaffold, 'WaterFlow({ scroller: this.scroller })', 'waterfall scaffold must bind the shared Scroller to native WaterFlow');
assertIncludes(scaffold, '.columnsTemplate(this.columnsTemplate())', 'waterfall scaffold must keep responsive column templates');
assertIncludes(scaffold, 'ResponsiveGrid.columns', 'waterfall scaffold must derive columns from measured content width');
assertIncludes(scaffold, '.onReachEnd(() =>', 'waterfall scaffold must preserve load-more reach-end behavior');
assertIncludes(read('shared/src/main/ets/Index.ets'), "export { PullRefreshWaterFlowScaffold }", 'shared barrel must export the WaterFlow scaffold');

const thumbnails = read('feature/gallery/src/main/ets/pages/GalleryAllThumbnailsPage.ets');
assertIncludes(thumbnails, 'PullRefreshGridScaffold', 'all-thumbnails page must remain a fixed grid, not gallery-card WaterFlow');
assertIncludes(thumbnails, 'GridItem() {', 'all-thumbnails page must keep GridItem thumbnail cells');

console.log('gallery waterflow contract passed');
