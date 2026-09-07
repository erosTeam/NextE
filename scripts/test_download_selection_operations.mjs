// Node.js 22.13+: execute the production scheduler and service methods with controlled I/O.
import assert from 'node:assert/strict'
import fs from 'node:fs'
import vm from 'node:vm'
import { stripTypeScriptTypes } from 'node:module'
const source = fs.readFileSync(new URL('../shared/src/main/ets/settings/DownloadQueueSettings.ets', import.meta.url), 'utf8')
const queueSource = fs.readFileSync(new URL('../shared/src/main/ets/settings/DownloadResumeQueue.ets', import.meta.url), 'utf8').replaceAll('export class', 'class')
function method(name) {
  const match = source.match(new RegExp(`^  (?:private )?static (?:async )?${name}\\(`, 'm'))
  assert(match, name)
  const start = match.index
  return source.slice(start, source.indexOf('\n  }', start) + 4)
}
const names = ['resumeGalleryTasks', 'resumeArchiverTasks', 'canResumeGalleryTask', 'canResumeArchiverTask', 'canPauseGalleryTask', 'canPauseArchiverTask', 'pauseGalleryDownload', 'pauseArchiverDownload', 'cancelGalleryTaskStart', 'cancelArchiverTaskStart', 'galleryCanContinue', 'runPrepareGallerySeeds', 'resolveArchiverBotUrl']
const state = { galleryTasks: [], archiverTasks: [] }
const status = Object.fromEntries(['QUEUED','READY','PAUSED','PARTIAL','ERROR','COMPLETE','DOWNLOADING','PREPARING'].map(x => [x,x]))
let limit = 2
const runtime = vm.createContext({
  DownloadGalleryTaskStatus: status,
  publishDownloadQueueChanged() {}, connectDownloadSettings: () => ({ concurrency: limit }),
  DiagnosticLogger: { info() {}, warn() {}, ownerHash: x => x },
  EhApiService: { getInstance: () => ({ getPreviewImages: async () => [] }) },
})
vm.runInContext(stripTypeScriptTypes(`${queueSource}\nclass DownloadQueueSettings {${names.map(method).join('\n')}}\nthis.service=DownloadQueueSettings;this.Queue=DownloadResumeQueue`), runtime)
const service = runtime.service
const flush = async () => { for (let i=0;i<12;i++) await Promise.resolve() }
const deferred = () => { let resolve; const promise = new Promise(r => {resolve=r}); return {promise,resolve} }
function reset() {
  limit=2; state.galleryTasks=[]; state.archiverTasks=[]
  service.galleryResumeQueue = new runtime.Queue()
  service.archiverResumeQueue = new runtime.Queue()
  service.galleryDownloads = new Map(); service.archiverDownloads = new Map(); service.galleryPreparations = new Map()
  service.cancelledGalleryDownloads = new Set(); service.cancelledArchiverDownloads = new Set()
  service.gallerySeedScheduler = { cancelQueued() {} }
  service.taskKey = (gid,token,original) => `${gid}:${token}:${original}`
  service.findTask = (gid,token,original) => state.galleryTasks.find(t => t.gid===gid && t.token===token && t.preferOriginal===original) ?? null
  service.findArchiverTask = tag => state.archiverTasks.find(t => t.tag===tag) ?? null
  service.clearGalleryRuntimeState = () => {}
  service.persistGalleryTaskHeader = async () => {}
  service.persistArchiverTask = async () => {}
  service.updateGalleryTaskAfterPause = async (_,gid,token,original) => { service.findTask(gid,token,original).status=status.PAUSED }
  service.updateArchiverTask = async (_,tag,update) => { update(service.findArchiverTask(tag)) }
}
function gallery(gid, original=false) {return {gid,token:'fixture',preferOriginal:original,status:status.PAUSED,isDownloadComplete(){return this.status===status.COMPLETE}}}
let failures=0
async function test(name, run) {reset();try {await run();console.log(`PASS ${name}`)}catch(e){failures++;console.error(`FAIL ${name}:`,e)}}
await test('bounded gallery starts; duplicate clicks do not add work; pending pauses never start',async()=>{
  const gates=[deferred(),deferred(),deferred()];const started=[]
  state.galleryTasks=[gallery('1'),gallery('2'),gallery('3')]
  service.downloadGalleryImages=async (_,gid)=>{started.push(gid);await gates[Number(gid)-1].promise}
  assert.equal(service.resumeGalleryTasks({},state.galleryTasks),3)
  assert.equal(service.resumeGalleryTasks({},state.galleryTasks),0)
  assert(state.galleryTasks.every(t=>t.status===status.QUEUED))
  await flush();assert.deepEqual(started,['1','2'])
  await service.pauseGalleryDownload({},'3','fixture',false)
  gates[0].resolve();gates[1].resolve();await flush()
  assert.deepEqual(started,['1','2']);assert.equal(state.galleryTasks[2].status,status.PAUSED)
})
await test('quick pause/resume waits for old work and starts exactly once',async()=>{
  limit=1;const task=gallery('1');state.galleryTasks=[task]
  const old=deferred();const key=service.taskKey('1','fixture',false)
  service.galleryDownloads.set(key,old.promise);task.status=status.DOWNLOADING
  let starts=0;service.downloadGalleryImages=async()=>{starts++}
  await service.pauseGalleryDownload({},'1','fixture',false)
  assert.equal(service.resumeGalleryTasks({},[task]),1)
  await flush();assert.equal(starts,0)
  service.galleryDownloads.delete(key);old.resolve();await flush()
  assert.equal(starts,1);assert(!service.cancelledGalleryDownloads.has(key))
})
await test('pause cancels a resume waiting for an old request; later resume still works',async()=>{
  limit=1;const task=gallery('1');state.galleryTasks=[task]
  const old=deferred();const key=service.taskKey('1','fixture',false)
  service.galleryDownloads.set(key,old.promise)
  let starts=0;service.downloadGalleryImages=async()=>{starts++}
  service.resumeGalleryTasks({},[task]);await flush()
  await service.pauseGalleryDownload({},'1','fixture',false)
  service.galleryDownloads.delete(key);old.resolve();await flush();assert.equal(starts,0)
  service.resumeGalleryTasks({},[task]);await flush();assert.equal(starts,1)
})
await test('same gallery qualities are independent and completed/unselected tasks are untouched',async()=>{
  const normal=gallery('1'),original=gallery('1',true),other=gallery('2'),complete=gallery('3');complete.status=status.COMPLETE
  state.galleryTasks=[normal,original,other,complete];const started=[]
  service.downloadGalleryImages=async(_,gid,token,quality)=>{started.push(`${gid}:${quality}`)}
  assert.equal(service.resumeGalleryTasks({},[original,complete]),1);await flush()
  assert.deepEqual(started,['1:true']);assert.equal(normal.status,status.PAUSED);assert.equal(other.status,status.PAUSED)
})
await test('archive starts are bounded; queued deletion cancels only its own task',async()=>{
  limit=1;const first=deferred();state.archiverTasks=['a','b','c'].map(tag=>({tag,status:status.PAUSED}))
  const started=[];service.downloadArchiver=async(_,tag)=>{started.push(tag);if(tag==='a')await first.promise}
  service.resumeArchiverTasks({},state.archiverTasks);await flush();assert.deepEqual(started,['a'])
  service.cancelArchiverTaskStart('b');state.archiverTasks=state.archiverTasks.filter(t=>t.tag!=='b')
  first.resolve();await flush();assert.deepEqual(started,['a','c'])
})
await test('one resume failure does not block later selected tasks',async()=>{
  limit=1;state.galleryTasks=[gallery('1'),gallery('2')];const started=[]
  service.downloadGalleryImages=async(_,gid)=>{started.push(gid);if(gid==='1')throw new Error('fixture network failure')}
  service.resumeGalleryTasks({},state.galleryTasks);await flush();assert.deepEqual(started,['1','2'])
})
await test('pause during seed preparation prevents later pages and image downloads',async()=>{
  const task=gallery('1');task.status=status.PREPARING;state.galleryTasks=[task]
  const page=deferred();let requests=0,downloads=0,ready=0
  runtime.EhApiService={getInstance:()=>({getPreviewImages:async()=>{requests++;await page.promise;return []}})}
  service.imagesToSeeds=images=>images;service.galleryQuality=()=> 'resample';service.expectedPreviewPageCount=()=>3
  service.updatePreparedTask=async(_,gid,token,s)=>{if(s===status.READY)ready++;task.status=s}
  service.downloadGalleryImages=async()=>{downloads++}
  const preparing=service.runPrepareGallerySeeds({},'1','fixture',false,[{copy(){return this}}],3,false)
  await flush();assert.equal(requests,1)
  await service.pauseGalleryDownload({},'1','fixture',false)
  page.resolve();await preparing
  assert.equal(requests,1);assert.equal(downloads,0);assert.equal(ready,0);assert.equal(task.status,status.PAUSED)
})
await test('gallery detail failure after pause does not replace the paused state',async()=>{
  const task=gallery('1');task.status=status.PREPARING;state.galleryTasks=[task]
  const gate=deferred();service.galleryQuality=()=> 'resample'
  service.fetchGalleryDetailForSeedRefresh=async()=>{await gate.promise;throw new Error('late detail error')}
  service.updateDownloadTaskStatus=async()=>{throw new Error('paused task must not receive an error update')}
  const preparing=service.runPrepareGallerySeeds({},'1','fixture',false,[],3,false);await flush()
  await service.pauseGalleryDownload({},'1','fixture',false);gate.resolve();await preparing
  assert.equal(task.status,status.PAUSED)
})
await test('archive resolver failure after pause does not replace the paused state',async()=>{
  const task={tag:'a',status:status.PREPARING};state.archiverTasks=[task]
  const gate=deferred();runtime.DownloadSettings={archiveBotReady:()=>true}
  runtime.ArchiveBotService={requestResolve:async()=>{await gate.promise;throw new Error('late resolver error')}}
  const resolving=service.resolveArchiverBotUrl({},'a',task);await flush()
  await service.pauseArchiverDownload({},'a');gate.resolve();await resolving
  assert.equal(task.status,status.PAUSED)
})
const pageSource=fs.readFileSync(new URL('../feature/download/src/main/ets/pages/DownloadQueuePage.ets',import.meta.url),'utf8')
const pageNames=['deleteSelected','publishSelection','selectedGalleryTasks','selectedArchiverTasks','visibleSelectionKeys','galleryActionKey','archiverActionKey','taskKey','exitSelection','batchSummary','canPauseTask','canResumeTask','canPauseArchiverTask','canResumeArchiverTask']
const pageMethods=pageNames.map(name=>{
  const match=pageSource.match(new RegExp(`^  private (?:async )?${name}\\(`,'m'));assert(match,name)
  return pageSource.slice(match.index,pageSource.indexOf('\n  }',match.index)+4)
})
runtime.DownloadViewType={GALLERY:'gallery',ARCHIVER:'archiver'}
runtime.AppStrings={get:()=>'%1$s/%2$s/%s'}
vm.runInContext(stripTypeScriptTypes(`class SelectionPage {${pageMethods.join('\n')}};this.Page=SelectionPage`),runtime)
await test('batch deletion is sequential, keeps failures selected and preserves unselected tasks',async()=>{
  const page=new runtime.Page();const first=deferred();const calls=[]
  const a=gallery('a'),b=gallery('b'),untouched=gallery('c');state.galleryTasks=[a,b,untouched]
  page.downloadQueue=state;page.downloadView={viewType:'gallery',selectionMode:true,batchBusy:false};page.galleryTaskGroups=[[a,b,untouched]];page.archiverTaskGroups=[]
  page.selectedKeys=new Set([page.galleryActionKey(a),page.galleryActionKey(b)])
  page.ctx=()=>({});let summary='';page.selectionToast=message=>{summary=message}
  service.removeGallery=async(_,gid)=>{
    calls.push(gid)
    if(gid==='a'){
      await first.promise;state.galleryTasks=state.galleryTasks.filter(t=>t.gid!=='a');page.galleryTaskGroups=[state.galleryTasks]
    }else throw new Error('fixture storage failure')
  }
  const deleting=page.deleteSelected([a,b],[]);await flush()
  assert.deepEqual(calls,['a']);assert(page.downloadView.batchBusy)
  first.resolve();await deleting
  assert.deepEqual(calls,['a','b']);assert.deepEqual(Array.from(page.selectedKeys),[page.galleryActionKey(b)])
  assert(state.galleryTasks.includes(untouched));assert(page.downloadView.selectionMode);assert(!page.downloadView.batchBusy)
  assert(summary.startsWith('1/1/'))
})
await test('selection uses the filtered projection and survives status regrouping',async()=>{
  const page=new runtime.Page();const a=gallery('a'),original=gallery('a',true),hidden=gallery('hidden');state.galleryTasks=[a,original,hidden]
  page.downloadQueue=state;page.downloadView={viewType:'gallery',selectionMode:true};page.galleryTaskGroups=[[a],[original]];page.archiverTaskGroups=[]
  page.selectedKeys=new Set(page.visibleSelectionKeys());page.publishSelection()
  assert.equal(page.downloadView.selectedCount,2);assert(!page.selectedKeys.has(page.galleryActionKey(hidden)))
  a.status=status.COMPLETE;page.galleryTaskGroups=[[original],[],[a]];page.publishSelection()
  assert.equal(page.downloadView.selectedCount,2);assert.equal(page.downloadView.selectedResumable,1)
})
process.exitCode=failures?1:0
