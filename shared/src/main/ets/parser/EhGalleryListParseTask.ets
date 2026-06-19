import { taskpool } from '@kit.ArkTS'
import { EhGallery } from '../model/EhGallery'
import { Favcat } from '../model/Favcat'
import { GalleryList } from '../model/GalleryList'
import { SimpleTag } from '../model/SimpleTag'
import { EhGalleryListParser } from './EhGalleryListParser'

@Concurrent
function parseGalleryListJson(html: string): string {
  return JSON.stringify(EhGalleryListParser.parse(html))
}

/**
 * Runs the expensive EH gallery-list HTML parse off the UI thread, then revives the serialized
 * result back into NextE model classes on the caller thread so existing UI code can keep using
 * methods such as `EhGallery.title()`.
 */
export class EhGalleryListParseTask {
  static async parse(html: string): Promise<GalleryList> {
    let raw: string
    try {
      raw = await taskpool.execute<[string], string>(parseGalleryListJson, html)
    } catch (error) {
      throw new Error(`gallery list task execution failed: ${(error as Error).message}`)
    }
    let parsed: GalleryList
    try {
      parsed = JSON.parse(raw) as GalleryList
    } catch (error) {
      throw new Error(`gallery list task parse failed: ${(error as Error).message}`)
    }
    return EhGalleryListParseTask.revive(parsed)
  }

  private static revive(raw: GalleryList): GalleryList {
    const list: GalleryList = new GalleryList()
    list.gallerys = raw.gallerys.map((g: EhGallery) => EhGalleryListParseTask.reviveGallery(g))
    list.nextGid = raw.nextGid
    list.prevGid = raw.prevGid
    list.maxPage = raw.maxPage
    list.nextPage = raw.nextPage
    list.prevPage = raw.prevPage
    list.favList = raw.favList.map((f: Favcat) => new Favcat(f.favId, f.favTitle, f.totNum))
    list.favOrder = raw.favOrder
    return list
  }

  private static reviveGallery(raw: EhGallery): EhGallery {
    const g: EhGallery = new EhGallery(raw.gid, raw.token)
    g.url = raw.url
    g.thumbUrl = raw.thumbUrl
    g.thumbUrlL = raw.thumbUrlL
    g.imgWidth = raw.imgWidth
    g.imgHeight = raw.imgHeight
    g.englishTitle = raw.englishTitle
    g.japaneseTitle = raw.japaneseTitle
    g.category = raw.category
    g.uploader = raw.uploader
    g.posted = raw.posted
    g.postTime = raw.postTime
    g.language = raw.language
    g.fileCount = raw.fileCount
    g.fileSize = raw.fileSize
    g.fileSizeText = raw.fileSizeText
    g.expunged = raw.expunged
    g.rating = raw.rating
    g.ratingFallBack = raw.ratingFallBack
    g.ratingCount = raw.ratingCount
    g.numberOfReviews = raw.numberOfReviews
    g.colorRating = raw.colorRating
    g.isRated = raw.isRated
    g.favcat = raw.favcat
    g.favTitle = raw.favTitle
    g.favNote = raw.favNote
    g.favoritedCount = raw.favoritedCount
    g.simpleTags = raw.simpleTags.map((t: SimpleTag) => EhGalleryListParseTask.reviveSimpleTag(t))
    g.translated = raw.translated
    g.torrentCount = raw.torrentCount
    g.archiverLink = raw.archiverLink
    g.visible = raw.visible
    g.parentTitle = raw.parentTitle
    g.parentUrl = raw.parentUrl
    g.parentGid = raw.parentGid
    g.parentToken = raw.parentToken
    g.apiuid = raw.apiuid
    g.apikey = raw.apikey
    g.showKey = raw.showKey
    g.pageOfList = raw.pageOfList
    g.lastViewTime = raw.lastViewTime
    return g
  }

  private static reviveSimpleTag(raw: SimpleTag): SimpleTag {
    const tag: SimpleTag = new SimpleTag(raw.text, raw.translat, raw.namespace)
    tag.color = raw.color
    tag.backgroundColor = raw.backgroundColor
    tag.vote = raw.vote
    return tag
  }
}
