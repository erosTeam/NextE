#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';

const root = process.cwd();
const read = (rel) => fs.readFileSync(path.join(root, rel), 'utf8');

function fail(message) {
  console.error(`reader volume-key contract failed: ${message}`);
  process.exit(1);
}

function ok(message, condition) {
  if (!condition) {
    fail(message);
  }
}

const state = read('shared/src/main/ets/state/ReadModeState.ets');
const settings = read('shared/src/main/ets/settings/ReadModeSettings.ets');
const reader = read('feature/reader/src/main/ets/pages/ReaderPage.ets');
const settingsPage = read('feature/settings/src/main/ets/pages/ReaderSettingsPage.ets');
const base = read('entry/src/main/resources/base/element/string.json');

ok(
  'ReadModeState carries the volume-key turn switch',
  /@Trace\s+volumeKeyTurn:\s*boolean\s*=\s*false/.test(state),
);
ok(
  'ReadModeSettings restores and persists reading.volumeKeyTurn',
  /StorageKeys\.READING_VOLUME_KEY[\s\S]*false/.test(settings) &&
    /setVolumeKeyTurn\(context: common\.UIAbilityContext, enabled: boolean\)/.test(settings) &&
    /store\.putSync\(StorageKeys\.READING_VOLUME_KEY, enabled\)/.test(settings),
);
ok(
  'Reader settings exposes a native switch row for volume-key turning',
  /settings_reader_volume_key/.test(settingsPage) &&
    /hasSwitch:\s*true/.test(settingsPage) &&
    /checked:\s*this\.readMode\.volumeKeyTurn/.test(settingsPage) &&
    /setVolumeKeyTurn/.test(settingsPage),
);
ok(
  'Reader focus surface handles key events',
  /const READER_KEY_SURFACE_ID:\s*string\s*=\s*'reader_key_surface'/.test(reader) &&
    /\.id\(READER_KEY_SURFACE_ID\)[\s\S]*\.focusable\(true\)[\s\S]*\.defaultFocus\(true\)[\s\S]*\.onKeyEvent\(\(event: KeyEvent\): boolean =>/.test(reader) &&
    /requestReaderKeyFocus\(\)/.test(reader),
);
ok(
  'Reader focus request is deferred and cannot crash reader startup',
  /private requestReaderKeyFocus\(\): void[\s\S]*requestReaderKeyFocusAfter\(0\)[\s\S]*requestReaderKeyFocusAfter\(120\)[\s\S]*requestReaderKeyFocusAfter\(360\)/.test(reader) &&
    /private requestReaderKeyFocusAfter\(delayMs: number\): void[\s\S]*setTimeout\(\(\) =>[\s\S]*try[\s\S]*requestFocus\(READER_KEY_SURFACE_ID\)[\s\S]*catch \(err\)[\s\S]*key_focus_request_failed/.test(reader),
);
ok(
  'Reader consumes volume keys only when the setting is enabled',
  /private handleKeyEvent\(event: KeyEvent\): boolean[\s\S]*!this\.readMode\.volumeKeyTurn[\s\S]*return false/.test(reader) &&
    /private turnByVolumeKeyCode\(keyCode: number\): boolean[\s\S]*!this\.readMode\.volumeKeyTurn[\s\S]*return false/.test(reader) &&
    /KeyCode\.KEYCODE_VOLUME_UP/.test(reader) &&
    /KeyCode\.KEYCODE_VOLUME_DOWN/.test(reader),
);
ok(
  'volume down/up map to next/previous existing reader actions',
  /keyCode === KeyCode\.KEYCODE_VOLUME_DOWN[\s\S]*this\.toNext\(\)[\s\S]*else[\s\S]*this\.toPrev\(\)/.test(reader),
);
ok(
  'Reader uses InputKit inputConsumer for system volume keys and unregisters on close',
  /import inputConsumer from '@ohos\.multimodalInput\.inputConsumer'/.test(reader) &&
    /import \{ Action, KeyEvent as InputConsumerKeyEvent \} from '@ohos\.multimodalInput\.keyEvent'/.test(reader) &&
    /private volumeDownConsumer: \(\(event: InputConsumerKeyEvent\) => void\) \| null = null/.test(reader) &&
    /private volumeUpConsumer: \(\(event: InputConsumerKeyEvent\) => void\) \| null = null/.test(reader) &&
    /inputConsumer\.on\('keyPressed'[\s\S]*KeyCode\.KEYCODE_VOLUME_DOWN[\s\S]*inputConsumer\.on\('keyPressed'[\s\S]*KeyCode\.KEYCODE_VOLUME_UP/.test(reader) &&
    /inputConsumer\.off\('keyPressed', this\.volumeDownConsumer\)/.test(reader) &&
    /inputConsumer\.off\('keyPressed', this\.volumeUpConsumer\)/.test(reader) &&
    /aboutToDisappear\(\): void[\s\S]*this\.unregisterVolumeKeyConsumer\(\)/.test(reader),
);
ok(
  'Reader live-applies volume-key setting changes while already open',
  /@Monitor\('readMode\.volumeKeyTurn'\)\s+onVolumeKeyTurnChanged\(\): void/.test(reader) &&
    /onVolumeKeyTurnChanged\(\): void[\s\S]*this\.readMode\.volumeKeyTurn[\s\S]*this\.requestReaderKeyFocus\(\)[\s\S]*this\.registerVolumeKeyConsumer\(\)[\s\S]*else[\s\S]*this\.unregisterVolumeKeyConsumer\(\)/.test(reader),
);
ok(
  'i18n base has the new setting labels',
  /"name": "settings_reader_volume_key"/.test(base) &&
    /"name": "settings_reader_volume_key_hint"/.test(base),
);

console.log('✓ reader volume-key contract passed');
