#!/usr/bin/env python3
"""Replay the default NextE reader with semantic checkpoints in one leased session."""
import argparse
import json
import os
from pathlib import Path
import sys
import time


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--target', required=True, help='Currently resolved full HDC target')
    parser.add_argument('--hdc', required=True)
    parser.add_argument('--manifest', type=Path, required=True, help='Current device protocol/context')
    parser.add_argument('--anchor-id', required=True, help='Unique cover ID on the current Detail page')
    parser.add_argument('--read-text', default='阅读')
    parser.add_argument('--runs', type=int, default=1)
    parser.add_argument('--output-dir', type=Path, required=True, help='New directory in the device-state partition')
    parser.add_argument('--skill-dir', type=Path,
                        default=Path.home()/'.codex/skills/harmony-run-device-diagnostics')
    args = parser.parse_args()
    if not 1 <= args.runs <= 10:
        parser.error('--runs must be 1..10')
    manifest = json.loads(args.manifest.read_text())
    if manifest.get('target') != args.target or manifest.get('authorizedTarget') != args.target:
        parser.error('Current manifest target and authorizedTarget must match --target')
    sys.path.insert(0, str(args.skill_dir/'scripts'))
    from semantic_session import session, unique, wait_count
    os.environ['PATH'] = str(Path(args.hdc).resolve().parent) + os.pathsep + os.environ['PATH']
    args.output_dir.mkdir(parents=True, exist_ok=False)
    report = {'target': args.target, 'context': manifest['context'], 'display': manifest['display'],
              'scenario': {'anchorId': args.anchor_id, 'readText': args.read_text,
                           'overlayId': 'reader-overlay-navigation'},
              'rounds': [], 'status': 'running',
              'evidenceScope': 'Navigation/anchor geometry only; not image readiness or visual acceptance'}
    started = time.monotonic()
    try:
        with session(args.target, args.hdc) as driver:
            report['startupMs'] = round((time.monotonic()-started)*1000, 1)
            precondition_started = time.monotonic()
            wait_count(driver, {'id': args.anchor_id}, 1)
            wait_count(driver, {'id': 'reader-overlay-navigation'}, 0)
            initial = str(unique(driver, {'id': args.anchor_id}).bounds)
            report['initialAnchorBounds'] = initial
            report['preconditionMs'] = round((time.monotonic()-precondition_started)*1000, 1)
            for index in range(args.runs):
                step = {'index': index, 'timingsMs': {}}
                report['rounds'].append(step)
                tick = time.monotonic()
                read = unique(driver, {'text': args.read_text})
                step['timingsMs']['locateRead'] = round((time.monotonic()-tick)*1000, 1)
                phase_started = time.monotonic()
                read.click()
                step['timingsMs']['clickRead'] = round((time.monotonic()-phase_started)*1000, 1)
                step['reader'] = wait_count(driver, {'id': 'reader-overlay-navigation'}, 1)
                phase_started = time.monotonic()
                driver.go_back()
                step['timingsMs']['back'] = round((time.monotonic()-phase_started)*1000, 1)
                step['readerGone'] = wait_count(driver, {'id': 'reader-overlay-navigation'}, 0)
                step['detail'] = wait_count(driver, {'id': args.anchor_id}, 1)
                step['elapsedMs'] = round((time.monotonic()-tick)*1000, 1)
                phase_started = time.monotonic()
                step['anchorBounds'] = str(unique(driver, {'id': args.anchor_id}).bounds)
                if step['anchorBounds'] != initial:
                    raise AssertionError('Returned Detail anchor geometry changed')
                step['timingsMs']['verifyGeometry'] = round((time.monotonic()-phase_started)*1000, 1)
                step['totalRoundMs'] = round((time.monotonic()-tick)*1000, 1)
                print(json.dumps(step, ensure_ascii=False), flush=True)
            cleanup_started = time.monotonic()
        report['cleanupMs'] = round((time.monotonic()-cleanup_started)*1000, 1)
        report['status'] = 'passed'
    except Exception as exc:
        report.update(status='failed', error=f'{type(exc).__name__}: {exc}',
                      cleanupNotes=getattr(exc, '__notes__', []))
        # Stop dependent input. The caller can now use the existing protocol runner for one
        # failure capture, after this semantic session has closed. Never dumpLayout inside it.
    finally:
        report['totalMs'] = round((time.monotonic()-started)*1000, 1)
        (args.output_dir/'result.json').write_text(json.dumps(report, ensure_ascii=False, indent=2))
    print(json.dumps({'status': report['status'], 'totalMs': report['totalMs'],
                      'result': str(args.output_dir/'result.json')}, ensure_ascii=False))
    return 0 if report['status'] == 'passed' else 1


if __name__ == '__main__':
    raise SystemExit(main())
