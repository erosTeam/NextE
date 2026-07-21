import { HdsNavDestination } from '@kit.UIDesignKit'
import {
  AppStrings,
  LayoutSafeAreaState,
  ThemeConstants,
  ToriiWholePageLiveEvaluationPageReport,
  ToriiWholePageLiveEvaluationReport,
  connectLayoutSafeArea,
  immersiveTitleBar,
} from 'shared'

export class ToriiWholePageLiveEvaluationRouteParams {
  report: ToriiWholePageLiveEvaluationReport =
    new ToriiWholePageLiveEvaluationReport()
}

@ComponentV2
export struct ToriiWholePageLiveEvaluationPage {
  @Local private report: ToriiWholePageLiveEvaluationReport =
    new ToriiWholePageLiveEvaluationReport();
  private layout: LayoutSafeAreaState = connectLayoutSafeArea()

  private elapsedText(value: number): string {
    return value >= 1000 ? `${(value / 1000).toFixed(1)} s` : `${value} ms`
  }

  private byteText(value: number): string {
    return value >= 1024 * 1024
      ? `${(value / 1024 / 1024).toFixed(1)} MB`
      : `${Math.max(0, Math.round(value / 1024))} KB`
  }

  private summaryText(): string {
    return AppStrings.get('comic_torii_live_evaluation_summary')
      .replace('%s', this.report.modelId)
      .replace('%s', this.elapsedText(this.report.elapsedMs()))
      .replace('%s', this.byteText(this.report.totalArtifactBytes))
  }

  private originalImage(pageIndex: number): Resource {
    return pageIndex === 0
      ? $rawfile('comic_translation_live_eval_page_01.jpg')
      : $rawfile('comic_translation_live_eval_page_02.jpg')
  }

  private artifactUri(path: string): string {
    return path.startsWith('file://') ? path : `file://${path}`
  }

  private pageTitle(pageIndex: number): string {
    return AppStrings.get('comic_torii_live_evaluation_page')
      .replace('%d', `${pageIndex + 1}`)
  }

  @Builder
  private EvaluationImage(title: ResourceStr, source: ResourceStr) {
    Column({ space: ThemeConstants.SPACE_SM }) {
      Text(title)
        .fontSize(ThemeConstants.FONT_SIZE_BODY)
        .fontColor($r('sys.color.font_secondary'))
        .width('100%')
      Image(source)
        .width('100%')
        .aspectRatio(2 / 3)
        .objectFit(ImageFit.Contain)
        .backgroundColor(Color.Black)
        .borderRadius(ThemeConstants.LIST_ROW_RADIUS)
    }
    .width('100%')
  }

  @Builder
  private PageComparison(page: ToriiWholePageLiveEvaluationPageReport) {
    Column({ space: ThemeConstants.SPACE_MD }) {
      Text(this.pageTitle(page.pageIndex))
        .fontSize(ThemeConstants.FONT_SIZE_LIST_ITEM)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('sys.color.font_primary'))
        .width('100%')
      this.EvaluationImage(
        $r('app.string.comic_torii_live_evaluation_original'),
        this.originalImage(page.pageIndex),
      )
      this.EvaluationImage(
        $r('app.string.comic_torii_live_evaluation_translated'),
        this.artifactUri(page.artifactPath),
      )
    }
    .width('100%')
    .padding(ThemeConstants.SPACE_MD)
    .backgroundColor($r('sys.color.ohos_id_color_background'))
    .borderRadius(ThemeConstants.LIST_ROW_RADIUS)
  }

  build() {
    HdsNavDestination() {
      Scroll() {
        Column({ space: ThemeConstants.SPACE_MD }) {
          Blank().height(this.layout.topAvoidHeight + ThemeConstants.TITLE_BAR_HEIGHT)
          Text(this.summaryText())
            .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
            .fontColor($r('sys.color.font_secondary'))
            .width('100%')
          ForEach(
            this.report.pages,
            (page: ToriiWholePageLiveEvaluationPageReport) => {
              this.PageComparison(page)
            },
            (page: ToriiWholePageLiveEvaluationPageReport) => `${page.pageIndex}:${page.artifactHash}`,
          )
        }
        .width('100%')
        .padding({
          left: ThemeConstants.SPACE_MD,
          right: ThemeConstants.SPACE_MD,
          bottom: this.layout.bottomAvoidHeight + ThemeConstants.SPACE_XL,
        })
      }
      .width('100%')
      .height('100%')
      .edgeEffect(EdgeEffect.Spring)
    }
    .titleBar(immersiveTitleBar($r('app.string.comic_torii_live_evaluation_result_title')))
    .backgroundColor($r('sys.color.ohos_id_color_sub_background'))
    .onReady((context: NavDestinationContext) => {
      const params = context.pathInfo.param as ToriiWholePageLiveEvaluationRouteParams
      if (params !== undefined && params.report.passed()) {
        this.report = params.report
      }
    })
  }
}
