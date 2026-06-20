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

function branchBetween(source, start, end) {
  const startIndex = source.indexOf(start);
  if (startIndex < 0) {
    return '';
  }
  const endIndex = source.indexOf(end, startIndex + start.length);
  return source.slice(startIndex, endIndex < 0 ? source.length : endIndex);
}

const scaffoldRel = 'shared/src/main/ets/components/PullRefreshWaterFlowScaffold.ets';
const scaffold = read(scaffoldRel);

assertIncludes(scaffold, 'WaterFlow({ scroller: this.scroller })', 'waterfall scaffold must bind the shared Scroller to native WaterFlow');
assertIncludes(scaffold, '.columnsTemplate(this.columnsTemplate())', 'waterfall scaffold must keep responsive column templates');
assertIncludes(scaffold, 'ResponsiveGrid.columns', 'waterfall scaffold must derive columns from measured content width');
assertIncludes(scaffold, '.onReachEnd(() =>', 'waterfall scaffold must preserve load-more reach-end behavior');
assertIncludes(read('shared/src/main/ets/Index.ets'), "export { PullRefreshWaterFlowScaffold }", 'shared barrel must export the WaterFlow scaffold');
assertIncludes(read('shared/src/main/ets/Index.ets'), "export { GalleryWaterfallCard }", 'shared barrel must export the Waterfall card');

const layoutSettings = read('feature/settings/src/main/ets/pages/LayoutSettingsPage.ets');
assertIncludes(layoutSettings, 'ListMode.WATERFALL', 'layout settings must expose ListMode.WATERFALL as a distinct mode');
assertIncludes(layoutSettings, "app.string.view_waterfall", 'layout settings must show a Waterfall label');

const waterfallCard = read('shared/src/main/ets/components/GalleryWaterfallCard.ets');
assertIncludes(waterfallCard, 'export struct GalleryWaterfallCard', 'Waterfall mode must use its own card component');
assertIncludes(waterfallCard, 'private coverRatio(): number', 'Waterfall card must compute a source-aspect cover ratio');
assertIncludes(waterfallCard, 'this.gallery.imgWidth / this.gallery.imgHeight', 'Waterfall cover ratio must use gallery image dimensions');
assertIncludes(waterfallCard, 'EhThumbnail({', 'Waterfall card must render through the shared thumbnail component');
assertIncludes(waterfallCard, 'coverRatio: this.coverRatio()', 'Waterfall card must pass the computed cover ratio');
assertNotIncludes(waterfallCard, 'GALLERY_GRID_INFO_HEIGHT', 'Waterfall card must not reuse fixed Grid card info height');
assertNotIncludes(waterfallCard, 'GALLERY_GRID_TITLE_HEIGHT', 'Waterfall card must not reuse fixed Grid title height');

const galleryPages = [
  'feature/home/src/main/ets/components/GalleryListBody.ets',
  'feature/search/src/main/ets/pages/GallerySearchPage.ets',
  'feature/user/src/main/ets/components/FavcatPage.ets',
];

for (const rel of galleryPages) {
  const source = read(rel);
  const gridBranch = branchBetween(source, 'this.listMode.mode === ListMode.GRID', 'this.listMode.mode === ListMode.WATERFALL');
  const waterfallBranch = branchBetween(source, 'this.listMode.mode === ListMode.WATERFALL', '} else {');
  assertIncludes(source, 'PullRefreshWaterFlowScaffold', `${rel}: Waterfall branch must import the WaterFlow scaffold`);
  assertIncludes(source, 'GalleryWaterfallCard', `${rel}: Waterfall branch must import the Waterfall card`);
  assertIncludes(source, 'this.listMode.mode === ListMode.WATERFALL', `${rel}: must branch on ListMode.WATERFALL`);
  if (!/PullRefreshWaterFlowScaffold\(\{[\s\S]*FlowItem\(\) \{[\s\S]*GalleryWaterfallCard/.test(waterfallBranch)) {
    fail(`${rel}: WATERFALL branch must render FlowItem + GalleryWaterfallCard through PullRefreshWaterFlowScaffold`);
  }
  if (/PullRefreshWaterFlowScaffold/.test(gridBranch) ||
    /FlowItem\(\)/.test(gridBranch)) {
    fail(`${rel}: GRID branch must not use WaterFlow/FlowItem`);
  }
}

const thumbnails = read('feature/gallery/src/main/ets/pages/GalleryAllThumbnailsPage.ets');
assertIncludes(thumbnails, 'PullRefreshGridScaffold', 'all-thumbnails page must remain a fixed grid, not gallery-card WaterFlow');
assertIncludes(thumbnails, 'GridItem() {', 'all-thumbnails page must keep GridItem thumbnail cells');

console.log('gallery waterflow contract passed');
