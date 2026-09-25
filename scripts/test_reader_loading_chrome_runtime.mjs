import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { createRequire } from 'node:module'
import { test } from 'node:test'
import vm from 'node:vm'
const require = createRequire(import.meta.url)
const ts = require('/Applications/DevEco-Studio.app/Contents/tools/hvigor/hvigor/node_modules/typescript')
const source = readFileSync(new URL('../feature/reader/src/main/ets/lab/NextEReaderLabPage.ets', import.meta.url), 'utf8')
function method(name) {
  const start = source.indexOf(`  private ${name}(`) >= 0 ? source.indexOf(`  private ${name}(`) : source.indexOf(`  private async ${name}(`)
  assert.ok(start >= 0)
  const end = source.indexOf('\n  }', start) + 4
  return source.slice(start, end)
}
const code = ts.transpileModule(`class Host { ${['prepareChromeShow', 'syncChromeVisible', 'syncStatusBarAfterTakeover'].map(method).join('\n')} }; exports.Host = Host`, { compilerOptions: { target: ts.ScriptTarget.ES2020 } }).outputText
function setup() {
  let resolveWindow, resolveLayout
  const writes = [], layouts = [], exports = {}
  vm.runInNewContext(code, { exports, ReaderTrialLayoutCommit: { wait: (_ui, sample, current) => {
    layouts.push({sample,current}); return new Promise(resolve => { resolveLayout = resolve })
  } } })
  const host = new exports.Host()
  Object.assign(host, { closeRequested:false,hostClosing:false,routeActive:true,labVisibility:{foreground:true},
    managesTrialWindow:true,chromeVisible:false,chromeShowPreparing:false,readerBodyVisible:true,
    request:{readingChrome:true},liveSourceEntry:false,rootOwnedEntryTarget:true,entryTransition:{},entryPhase:'waiting',
    readerThumbnailTransition:{opened:()=>true},readMode:{fullscreen:true},safeArea:{topAvoidHeight:0,bottomAvoidHeight:0},
    getUIContext:()=>({getHostContext:()=>({})}),trialWindow:{
      setStatusBarVisible:value=>writes.push(['visible',value]),open:()=>writes.push(['open']),
      prepareStatusBarVisible:()=>new Promise(resolve=>{resolveWindow=resolve})
    }})
  return {host,writes,layouts,window:value=>resolveWindow(value),layout:value=>resolveLayout(value)}
}
test('waiting image menu prepares the same window and protects visible chrome from entry completion', async () => {
  const v=setup(), owner=v.host.trialWindow
  const ready=v.host.prepareChromeShow(()=>true)
  assert.deepEqual(v.writes,[['visible',true],['open']])
  assert.equal(v.host.chromeShowPreparing,true)
  v.host.entryPhase='finished';v.host.syncStatusBarAfterTakeover()
  assert.equal(v.writes.length,2)
  v.window(true);await new Promise(resolve => setImmediate(resolve))
  assert.equal(v.layouts.length,1);assert.equal(v.layouts[0].sample(),'')
  v.host.safeArea.topAvoidHeight=24;assert.equal(v.layouts[0].sample(),'24:0')
  v.layout(true);assert.equal(await ready,true)
  assert.equal(v.host.trialWindow,owner);assert.equal(v.host.chromeShowPreparing,true)
  v.host.syncChromeVisible(true);assert.equal(v.host.chromeShowPreparing,false)
  v.host.syncStatusBarAfterTakeover();assert.equal(v.writes.length,2)
})
test('closing or failed preparation cannot leave a pending chrome claim', async () => {
  for (const close of [false,true]) {
    const v=setup(),ready=v.host.prepareChromeShow(()=>true)
    v.host.closeRequested=close;v.window(!close ? false : true)
    assert.equal(await ready,false);assert.equal(v.host.chromeShowPreparing,false)
    assert.equal(v.layouts.length,0)
  }
})
