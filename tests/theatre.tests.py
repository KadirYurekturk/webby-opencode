"""Shared timing/cancellation cases run against both desktop implementations."""
import json
import math
import os
from pathlib import Path
import subprocess
import sys
import unittest

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / 'src'))
from theatre import Theatre, web_segments, leg_points, demo_frame


class TheatreTests(unittest.TestCase):
    def test_scenarios(self):
        for case in json.loads((ROOT / 'tests/theatre-cases.json').read_text()):
            with self.subTest(case=case['name']):
                stage = Theatre()
                for step in case['steps']:
                    if 'event' in step:
                        stage.event(step['event'], {'sessionID': step.get('session')}, step['time'])
                    else:
                        frame = stage.frame(step['mood'], step['time'], step.get('blocked', False))
                        for key, value in step['expect'].items():
                            self.assertEqual(frame[key], value, (case['name'], step, frame))

    def test_demo_has_visible_actions(self):
        for at, scene in ((1, 'clean'), (6, 'tug'), (11, 'sleep'), (19, 'think'), (26, 'weave'), (31, 'collect')):
            _, frame = demo_frame(at)
            self.assertEqual(frame['scene'], scene)
            if scene in ('clean', 'tug'): self.assertNotEqual(frame['left'], 0)

    def test_geometry_is_bounded_and_progressive(self):
        self.assertEqual(web_segments(0), [])
        self.assertEqual(len(web_segments(1)), 13)
        self.assertEqual(web_segments(100), web_segments(1))
        for progress in (.01, .25, .5, 1):
            for line in web_segments(progress):
                self.assertTrue(all(0 <= x <= 240 and 0 <= y <= 230 for x, y in zip(line[::2], line[1::2])))
        for side in (-1, 1):
            for angle in range(-50, 51):
                self.assertTrue(all(math.isfinite(v) for p in leg_points(120, 76, 112, 112, side, angle) for v in p))

    @unittest.skipUnless(os.environ.get('WEBBY_PWSH'), 'Set WEBBY_PWSH to compare Windows stage directions')
    def test_windows_parity(self):
        output = subprocess.check_output([os.environ['WEBBY_PWSH'], '-NoProfile', '-File',
                                          str(ROOT / 'tests/theatre.tests.ps1')], text=True)
        windows = json.loads(output)
        expected = []
        for case in json.loads((ROOT / 'tests/theatre-cases.json').read_text()):
            stage = Theatre()
            for step in case['steps']:
                if 'event' in step:
                    stage.event(step['event'], {'sessionID': step.get('session')}, step['time'])
                else:
                    expected.append(stage.frame(step['mood'], step['time'], step.get('blocked', False)))
        self.assertEqual(len(expected), len(windows))
        for py, ps in zip(expected, windows):
            ps = {key.lower(): value for key, value in ps.items()}
            for key, value in py.items():
                if isinstance(value, float): self.assertAlmostEqual(value, ps[key], places=8)
                else: self.assertEqual(value, ps[key])


if __name__ == '__main__': unittest.main()
