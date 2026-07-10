import { describe, expect, it } from '@ohos/hypium'
import {
  COMMENT_TRANSLATION_PRIORITY_AUTO,
  COMMENT_TRANSLATION_PRIORITY_INTERACTIVE,
  CommentTranslationQueueScheduler,
  CommentTranslationQueueTask,
} from 'shared'

export default function commentTranslationQueueSchedulerTest(): void {
  describe('CommentTranslationQueueScheduler', () => {
    it('limits auto translations and serves interactive work first', 0, (done: Function) => {
      const starts: string[] = []
      const scheduler: CommentTranslationQueueScheduler = new CommentTranslationQueueScheduler()
      const first: CommentTranslationQueueTask = new CommentTranslationQueueTask(
        'first',
        COMMENT_TRANSLATION_PRIORITY_AUTO,
        () => starts.push('first'),
      )
      const second: CommentTranslationQueueTask = new CommentTranslationQueueTask(
        'second',
        COMMENT_TRANSLATION_PRIORITY_AUTO,
        () => starts.push('second'),
      )
      const third: CommentTranslationQueueTask = new CommentTranslationQueueTask(
        'third',
        COMMENT_TRANSLATION_PRIORITY_AUTO,
        () => starts.push('third'),
      )
      const interactive: CommentTranslationQueueTask = new CommentTranslationQueueTask(
        'interactive',
        COMMENT_TRANSLATION_PRIORITY_INTERACTIVE,
        () => starts.push('interactive'),
      )

      scheduler.schedule(first)
      scheduler.schedule(second)
      scheduler.schedule(third)
      scheduler.schedule(interactive)
      expect(starts.join(',')).assertEqual('first,second')
      scheduler.complete(first)
      expect(starts.join(',')).assertEqual('first,second,interactive')
      scheduler.complete(second)
      expect(starts.join(',')).assertEqual('first,second,interactive,third')
      scheduler.complete(interactive)
      scheduler.complete(third)
      expect(third.active).assertEqual(false)

      const promotionStarts: string[] = []
      const promotionScheduler: CommentTranslationQueueScheduler = new CommentTranslationQueueScheduler()
      const activeA: CommentTranslationQueueTask = new CommentTranslationQueueTask(
        'active-a',
        COMMENT_TRANSLATION_PRIORITY_AUTO,
        () => promotionStarts.push('active-a'),
      )
      const activeB: CommentTranslationQueueTask = new CommentTranslationQueueTask(
        'active-b',
        COMMENT_TRANSLATION_PRIORITY_AUTO,
        () => promotionStarts.push('active-b'),
      )
      const queuedAuto: CommentTranslationQueueTask = new CommentTranslationQueueTask(
        'queued-auto',
        COMMENT_TRANSLATION_PRIORITY_AUTO,
        () => promotionStarts.push('queued-auto'),
      )
      const queuedOther: CommentTranslationQueueTask = new CommentTranslationQueueTask(
        'queued-other',
        COMMENT_TRANSLATION_PRIORITY_AUTO,
        () => promotionStarts.push('queued-other'),
      )
      promotionScheduler.schedule(activeA)
      promotionScheduler.schedule(activeB)
      promotionScheduler.schedule(queuedAuto)
      promotionScheduler.schedule(queuedOther)
      promotionScheduler.promote(queuedAuto, COMMENT_TRANSLATION_PRIORITY_INTERACTIVE)
      promotionScheduler.complete(activeA)
      expect(promotionStarts.join(',')).assertEqual('active-a,active-b,queued-auto')
      expect(queuedAuto.priority).assertEqual(COMMENT_TRANSLATION_PRIORITY_INTERACTIVE)
      done()
    })
  })
}
