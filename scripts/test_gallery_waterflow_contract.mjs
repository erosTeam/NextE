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

assertIncludes(scaffold, 'WaterFlow({ scroller: this.scroller, sections: this.waterFlowSections() })', 'waterfall scaffold must bind the shared Scroller to sectioned native WaterFlow');
assertIncludes(scaffold, 'private waterFlowSections(): WaterFlowSections', 'waterfall scaffold must use WaterFlowSections for full-width top/bottom reserve');
assertIncludes(scaffold, 'itemsCount: 1,\n      crossCount: 1', 'waterfall top/bottom reserve sections must span one full-width column');
assertIncludes(scaffold, 'itemsCount: this.itemCount', 'waterfall content section must be sized from the real rendered item count');
assertIncludes(scaffold, 'crossCount: this.contentColumnCount()', 'waterfall content section must keep a responsive masonry column count');
assertIncludes(scaffold, 'private contentColumnCount(): number', 'waterfall scaffold owns the section column fallback required by WaterFlowSections');
assertIncludes(scaffold, 'ThemeConstants.GALLERY_WATERFALL_MIN_W', 'waterfall scaffold fallback width must be the Waterfall token, not the Grid token');
assertNotIncludes(scaffold, 'ResponsiveGrid', 'waterfall scaffold must not hand-calculate columns through ResponsiveGrid');
assertNotIncludes(scaffold, 'onCellSize', 'waterfall scaffold must not leak hand-calculated cell widths to call sites');
assertIncludes(scaffold, 'private TopSpacer()', 'waterfall scaffold must expose a real top spacer builder');
assertIncludes(scaffold, 'FlowItem() {', 'waterfall scaffold top spacer must be real WaterFlow content');
assertIncludes(scaffold, 'Blank().height(this.topSpacerHeight())', 'waterfall scaffold top spacer must reserve the title chrome height as scroll content');
assertIncludes(scaffold, 'private BottomSpacer()', 'waterfall scaffold must expose a bottom footer spacer builder');
assertIncludes(scaffold, 'Blank().height(this.bottomSpacerHeight())', 'waterfall scaffold bottom footer must reserve bottom chrome height');
assertNotIncludes(scaffold, 'footer: this.BottomSpacer()', 'waterfall bottom reserve must be a section item when sections are active');
assertNotIncludes(scaffold, 'contentStartOffset', 'waterfall scaffold must not use contentStartOffset for title chrome reserve');
assertNotIncludes(scaffold, 'contentEndOffset', 'waterfall scaffold must not use contentEndOffset for bottom chrome reserve');
if (/padding\(\{[\s\S]*top:\s*this\.layout\.topAvoidHeight/.test(scaffold) ||
  /padding\(\{[\s\S]*bottom:\s*this\.layout\.bottomAvoidHeight/.test(scaffold)) {
  fail('waterfall scaffold must not use WaterFlow top/bottom padding as immersive inset');
}
assertIncludes(scaffold, '.onReachEnd(() =>', 'waterfall scaffold must preserve load-more reach-end behavior');
assertIncludes(read('shared/src/main/ets/Index.ets'), "export { PullRefreshWaterFlowScaffold }", 'shared barrel must export the WaterFlow scaffold');
assertIncludes(read('shared/src/main/ets/Index.ets'), "export { GalleryWaterfallCard }", 'shared barrel must export the Waterfall card');

const layoutSettings = read('feature/settings/src/main/ets/pages/LayoutSettingsPage.ets');
assertIncludes(layoutSettings, 'ListMode.WATERFALL', 'layout settings must expose ListMode.WATERFALL as a distinct mode');
assertIncludes(layoutSettings, "app.string.view_waterfall", 'layout settings must show a Waterfall label');

const waterfallCard = read('shared/src/main/ets/components/GalleryWaterfallCard.ets');
assertIncludes(waterfallCard, 'export struct GalleryWaterfallCard', 'Waterfall mode must use its own card component');
assertIncludes(waterfallCard, 'private coverRatio(): number', 'Waterfall card must compute a source-aspect cover ratio with bounds');
assertIncludes(waterfallCard, 'this.gallery.imgWidth / this.gallery.imgHeight', 'Waterfall cover ratio must use gallery image dimensions');
assertIncludes(waterfallCard, 'WATERFALL_MIN_COVER_RATIO', 'Waterfall cover ratio must keep a lower bound for extreme tall covers');
assertIncludes(waterfallCard, 'WATERFALL_MAX_COVER_RATIO', 'Waterfall cover ratio must keep an upper bound for extreme wide covers');
assertIncludes(waterfallCard, 'EhThumbnail({', 'Waterfall card must render through the shared thumbnail component');
assertIncludes(waterfallCard, 'coverRatio: this.coverRatio()', 'Waterfall card must pass its bounded source ratio');
assertIncludes(waterfallCard, 'private isExtremeTallCover(): boolean', 'Waterfall card must detect source ratios below the bounded cover slot');
assertIncludes(waterfallCard, 'forceCoverFit: !this.isExtremeTallCover()', 'Waterfall normal covers may crop, but extreme strip covers must not be full-width Cover scaled');
assertIncludes(waterfallCard, 'containFit: this.isExtremeTallCover()', 'Waterfall extreme strip foreground must preserve true source ratio inside the bounded slot');
assertIncludes(waterfallCard, 'GalleryCategoryCornerBadge', 'Waterfall card must use the same category corner badge as Grid');
assertIncludes(waterfallCard, 'sourceWidth: this.gallery.imgWidth', 'Waterfall card must pass source width so cover rendering can avoid distortion');
assertIncludes(waterfallCard, 'sourceHeight: this.gallery.imgHeight', 'Waterfall card must pass source height so cover rendering can avoid distortion');
assertIncludes(waterfallCard, 'UserTagStore.getInstance().lookup(t.namespace, t.text)', 'Waterfall tag chips must reuse the same user-tag color lookup as list cards');
assertIncludes(waterfallCard, 'connectUserTagSignal()', 'Waterfall tag chips must re-color when My Tags arrive late');
assertIncludes(waterfallCard, 'this.tagSig.version', 'Waterfall tag keys must subscribe to late user-tag color updates');
assertIncludes(waterfallCard, 't.backgroundColor.length > 0', 'Waterfall tag chips must fall back to parsed inline EH background color');
assertIncludes(waterfallCard, 't.color.length > 0', 'Waterfall tag chips must fall back to parsed inline EH text color');
assertIncludes(waterfallCard, 'WATERFALL_TAG_LIMIT', 'Waterfall tag density must use an explicit tag-limit policy, not a four-tag literal');
assertIncludes(waterfallCard, 'WATERFALL_TAG_STRIP_HEIGHT', 'Waterfall tag area must stay fixed-height instead of growing the masonry card');
assertIncludes(waterfallCard, 'private tagRow(offset: number): SimpleTag[]', 'Waterfall tag strip must split tags into two bounded rows');
assertIncludes(waterfallCard, 'this.tagRow(0)', 'Waterfall tag strip must render the first horizontal tag row');
assertIncludes(waterfallCard, 'this.tagRow(1)', 'Waterfall tag strip must render the second horizontal tag row');
assertIncludes(waterfallCard, '.scrollable(ScrollDirection.Horizontal)', 'Waterfall tag strip must overflow horizontally instead of wrapping vertically');
assertIncludes(waterfallCard, '.fontSize(ThemeConstants.FONT_SIZE_CAPTION)', 'Waterfall tag chips must use readable caption-size text');
assertNotIncludes(waterfallCard, 'simpleTags.slice(0, 4)', 'Waterfall tag strip must not regress to a Waterfall-only four-tag cap');
assertNotIncludes(waterfallCard, 'Flex({ wrap: FlexWrap.Wrap })', 'Waterfall tag strip must not use wrapping Flex that can grow the card height');
assertNotIncludes(waterfallCard, ".fontSize(ThemeConstants.FONT_SIZE_TINY)\n              .fontColor(this.chipText(t))", 'Waterfall tag chips must not use tiny unreadable text');
assertNotIncludes(waterfallCard, ".fontColor($r('sys.color.font_secondary'))\n              .backgroundColor($r('sys.color.ohos_id_color_button_normal'))", 'Waterfall tag chips must not be hard-coded neutral when tag color metadata exists');
assertNotIncludes(waterfallCard, '@Param cellWidth', 'Waterfall card must fill the native WaterFlow cell instead of receiving a hand-calculated width');
assertNotIncludes(waterfallCard, 'private cardWidth()', 'Waterfall card must not convert hand-calculated cell widths');
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
  assertIncludes(waterfallBranch, 'minColumnWidth: ThemeConstants.GALLERY_WATERFALL_MIN_W', `${rel}: WATERFALL branch must use a Waterfall-specific width token`);
  assertIncludes(waterfallBranch, 'itemCount: this.vm.itemCount', `${rel}: WATERFALL branch must pass itemCount so section spacers do not consume gallery items`);
  if (!/FlowItem\(\) \{[\s\S]*GalleryWaterfallCard\(\{ gallery: g \}\)[\s\S]*\.width\('100%'\)/.test(waterfallBranch)) {
    fail(`${rel}: WATERFALL branch must let each FlowItem fill its native WaterFlow cell`);
  }
  if (/GALLERY_GRID_MIN_W/.test(waterfallBranch) ||
    /cellWidth/.test(waterfallBranch) ||
    /onCellSize/.test(waterfallBranch)) {
    fail(`${rel}: WATERFALL branch must not share Grid width or hand-calculated cell width plumbing`);
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
