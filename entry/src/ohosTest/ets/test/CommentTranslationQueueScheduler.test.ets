import { describe, expect, it } from '@ohos/hypium'
import {
  COMMENT_TRANSLATION_PRIORITY_AUTO,
  COMMENT_TRANSLATION_PRIORITY_INTERACTIVE,
  MAX_PENDING_COMMENT_TRANSLATIONS,
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

    it('bounds waiting work and lets current visible work replace stale automatic work', 0, (done: Function) => {
      const starts: string[] = []
      const discarded: string[] = []
      const scheduler: CommentTranslationQueueScheduler = new CommentTranslationQueueScheduler()
      const activeA: CommentTranslationQueueTask = new CommentTranslationQueueTask(
        'active-a',
        COMMENT_TRANSLATION_PRIORITY_AUTO,
        () => starts.push('active-a'),
      )
      const activeB: CommentTranslationQueueTask = new CommentTranslationQueueTask(
        'active-b',
        COMMENT_TRANSLATION_PRIORITY_AUTO,
        () => starts.push('active-b'),
      )
      scheduler.schedule(activeA)
      scheduler.schedule(activeB)

      const queued: CommentTranslationQueueTask[] = []
      for (let i: number = 0; i < MAX_PENDING_COMMENT_TRANSLATIONS; i++) {
        const task: CommentTranslationQueueTask = new CommentTranslationQueueTask(
          `auto-${i}`,
          COMMENT_TRANSLATION_PRIORITY_AUTO,
          () => starts.push(`auto-${i}`),
          (error: Error): void => {
            discarded.push(error.message)
          },
        )
        queued.push(task)
        scheduler.schedule(task)
      }
      expect(scheduler.pendingCount()).assertEqual(MAX_PENDING_COMMENT_TRANSLATIONS)

      const latestAuto: CommentTranslationQueueTask = new CommentTranslationQueueTask(
        'latest-auto',
        COMMENT_TRANSLATION_PRIORITY_AUTO,
        () => starts.push('latest-auto'),
      )
      scheduler.schedule(latestAuto)
      expect(queued[0].discarded).assertEqual(true)
      expect(latestAuto.discarded).assertEqual(false)
      expect(scheduler.pendingCount()).assertEqual(MAX_PENDING_COMMENT_TRANSLATIONS)

      const interactive: CommentTranslationQueueTask = new CommentTranslationQueueTask(
        'interactive',
        COMMENT_TRANSLATION_PRIORITY_INTERACTIVE,
        () => starts.push('interactive'),
      )
      scheduler.schedule(interactive)
      expect(queued[1].discarded).assertEqual(true)
      scheduler.complete(activeA)
      expect(starts.join(',')).assertEqual('active-a,active-b,interactive')
      expect(discarded.join(',')).assertEqual(
        'comment_translation_queue_evicted,comment_translation_queue_evicted',
      )

      const interactiveOnly: CommentTranslationQueueScheduler = new CommentTranslationQueueScheduler()
      const runningA: CommentTranslationQueueTask = new CommentTranslationQueueTask(
        'running-a',
        COMMENT_TRANSLATION_PRIORITY_AUTO,
        () => {},
      )
      const runningB: CommentTranslationQueueTask = new CommentTranslationQueueTask(
        'running-b',
        COMMENT_TRANSLATION_PRIORITY_AUTO,
        () => {},
      )
      interactiveOnly.schedule(runningA)
      interactiveOnly.schedule(runningB)
      for (let i: number = 0; i < MAX_PENDING_COMMENT_TRANSLATIONS; i++) {
        interactiveOnly.schedule(new CommentTranslationQueueTask(
          `manual-${i}`,
          COMMENT_TRANSLATION_PRIORITY_INTERACTIVE,
          () => {},
        ))
      }
      const rejectedInteractive: CommentTranslationQueueTask = new CommentTranslationQueueTask(
        'manual-overflow',
        COMMENT_TRANSLATION_PRIORITY_INTERACTIVE,
        () => {},
      )
      interactiveOnly.schedule(rejectedInteractive)
      expect(rejectedInteractive.discarded).assertEqual(true)
      expect(interactiveOnly.pendingCount()).assertEqual(MAX_PENDING_COMMENT_TRANSLATIONS)
      done()
    })
  })
}
