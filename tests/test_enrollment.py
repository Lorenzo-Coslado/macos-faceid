"""Guided enrollment without recording a real face or touching user embeddings."""
import base64
import io
import math
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import cv2
import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from faceid import enroll
from faceid.enrollment import HeadCoverage, face_position, landmark_pose


def face_at(x=320, y=240, yaw=0, pitch=0):
    return np.array([x-90, y-110, 180, 220,
                     x-40, y-40, x+40, y-40,
                     x+yaw*80, y+pitch*80,
                     x-30, y+40, x+30, y+40, .99], dtype=np.float32)


def pose_for(sector):
    angle = sector * math.tau / 8
    return (-math.sin(angle) * .18, .5 - math.cos(angle) * .16)


class CoverageTests(unittest.TestCase):
    def test_stationary_face_cannot_complete_circle(self):
        tracker = HeadCoverage()
        self.assertTrue(tracker.capture((0, .5)))
        for _ in range(100):
            self.assertFalse(tracker.capture((0, .5)))
        self.assertEqual(tracker.coverage, [0] * 8)
        self.assertFalse(tracker.complete)

    def test_two_passes_require_frontal_and_all_angles_again(self):
        tracker = HeadCoverage()
        for _ in range(2):
            self.assertTrue(tracker.capture((0, .5)))
            for sector in range(8):
                pose = pose_for(sector)
                self.assertEqual(tracker.direction(pose)[0], sector)
                self.assertTrue(tracker.capture(pose))
                self.assertFalse(tracker.capture(pose))
            self.assertTrue(tracker.complete)
            tracker.reset_pass()
            self.assertFalse(tracker.complete)
            self.assertFalse(tracker.capture(pose_for(0)))

    def test_high_sample_counts_preserve_required_coverage(self):
        tracker = HeadCoverage(samples_per_sector=2)
        tracker.capture((0, .5))
        for sector in range(8):
            tracker.capture(pose_for(sector))
        self.assertFalse(tracker.complete)
        self.assertEqual(tracker.coverage, [.5] * 8)
        for sector in range(8):
            tracker.capture(pose_for(sector))
        self.assertTrue(tracker.complete)

    def test_center_calibration_is_person_specific(self):
        tracker = HeadCoverage()
        tracker.capture((.08, .65))
        self.assertFalse(tracker.capture((.08, .65)))
        self.assertEqual(tracker.direction((.08, .65))[0], None)

    def test_landmarks_ignore_translation_and_scale(self):
        original = landmark_pose(face_at(yaw=.15, pitch=.1))
        shifted = landmark_pose(face_at(x=290, y=220, yaw=.15, pitch=.1))
        scaled = face_at(yaw=.15, pitch=.1)
        scaled[:14] *= .7
        np.testing.assert_allclose(original, shifted, atol=1e-6)
        np.testing.assert_allclose(original, landmark_pose(scaled), atol=1e-6)

    def test_face_framing(self):
        self.assertEqual(face_position(face_at(), (480, 640, 3)), 'move')
        self.assertEqual(face_position(face_at(x=430), (480, 640, 3)), 'center')
        small = face_at(); small[2:4] = [60, 70]
        self.assertEqual(face_position(small, (480, 640, 3)), 'closer')
        large = face_at(); large[2:4] = [400, 420]
        self.assertEqual(face_position(large, (480, 640, 3)), 'farther')

    def test_preview_is_mirrored_decodable_and_square(self):
        frame = np.zeros((480, 640, 3), dtype=np.uint8)
        frame[:, 320:] = 255
        jpeg = enroll._preview(frame)
        decoded = cv2.imdecode(np.frombuffer(base64.b64decode(jpeg), np.uint8), cv2.IMREAD_COLOR)
        self.assertEqual(decoded.shape, (360, 360, 3))
        self.assertGreater(decoded[180, 20].mean(), 240)
        self.assertLess(decoded[180, 340].mean(), 10)


class GuidedSessionTests(unittest.TestCase):
    def run_session(self, commands='CONTINUE\n', no_face=False, multiple=False):
        # Exercise the capture loop, including first-pass pause and pipe EOF.
        poses = [(0, .5)] + [pose_for(i) for i in range(8)]
        faces = [face_at(yaw=p[0], pitch=p[1]-.5) for p in poses * 2]
        engine = type('Engine', (), {})()
        def detect(_):
            if no_face:
                return []
            if multiple:
                return [face_at(), face_at()]
            return [faces.pop(0) if faces else face_at()]
        engine.detect = detect
        engine.feature = lambda *_: np.ones(128, dtype=np.float32)
        cap = type('Camera', (), {'read': lambda _: (True, np.zeros((480, 640, 3), np.uint8))})()
        events = []
        ticks = iter(i * .4 for i in range(1000))
        with patch.object(enroll, 'emit', lambda **e: events.append(e)), \
             patch.object(enroll, '_preview', return_value=None), \
             patch.object(enroll.time, 'monotonic', side_effect=lambda: next(ticks)), \
             patch.object(enroll.select, 'select', return_value=([sys.stdin], [], [])), \
             patch.object(enroll.sys, 'stdin', io.StringIO(commands)), \
             patch.object(enroll.config, 'ENROLL_SAMPLES', 12), \
             patch.object(enroll.config, 'ENROLL_TIMEOUT_S', 10):
            samples = enroll._guided_samples(engine, cap)
        return samples, events

    def test_complete_session_waits_for_continue_and_records_both_passes(self):
        samples, events = self.run_session()
        self.assertEqual(len(samples), 18)
        self.assertEqual(sum(e['event'] == 'progress' for e in events), 18)
        self.assertEqual(sum(e['event'] == 'pass-complete' for e in events), 1)
        self.assertEqual(sum(e['event'] == 'pass-start' for e in events), 1)
        self.assertEqual(events[-1]['coverage'], [1] * 8)
        self.assertEqual(events[-1]['passIndex'], 2)

    def test_closed_ui_between_passes_cancels_without_saving(self):
        samples, events = self.run_session(commands='')
        self.assertIsNone(samples)
        self.assertEqual(sum(e['event'] == 'progress' for e in events), 9)

    def test_no_face_never_advances_and_times_out(self):
        samples, events = self.run_session(no_face=True)
        self.assertIsNone(samples)
        self.assertFalse(any(e['event'] == 'progress' for e in events))
        self.assertEqual(events[-1]['msg'], 'enroll-timeout')

    def test_multiple_faces_never_advance(self):
        samples, events = self.run_session(multiple=True)
        self.assertIsNone(samples)
        self.assertFalse(any(e['event'] == 'progress' for e in events))
        self.assertTrue(any(e.get('hint') == 'one-face' for e in events))


class PersistenceTests(unittest.TestCase):
    def session(self, samples, appending):
        cap = type('Camera', (), {
            'isOpened': lambda _: True, 'set': lambda *_: None,
            'read': lambda _: (True, None),
            'release': lambda obj: setattr(obj, 'released', True),
        })()
        with tempfile.TemporaryDirectory() as directory:
            folder = Path(directory)
            path = folder / 'embeddings.npy'
            existing = np.full((3, 128), .25, dtype=np.float32)
            np.save(path, existing)
            before = path.read_bytes()
            with patch.object(enroll.config, 'APP_DIR', folder), \
                 patch.object(enroll.config, 'EMBEDDINGS_PATH', path), \
                 patch.object(enroll, 'GUIDED', True), \
                 patch.object(enroll, 'APPEND', appending), \
                 patch.object(enroll.FaceEngine, '__init__', return_value=None), \
                 patch.object(enroll.cv2, 'VideoCapture', return_value=cap), \
                 patch.object(enroll, '_guided_samples', return_value=samples), \
                 patch.object(enroll, 'emit'):
                code = enroll.main()
            return code, cap.released, before, path.read_bytes(), np.load(path)

    def test_interrupted_scan_releases_camera_and_keeps_existing_face(self):
        code, released, before, after, _ = self.session(None, False)
        self.assertEqual(code, 1)
        self.assertTrue(released)
        self.assertEqual(before, after)

    def test_completed_guided_appearance_is_appended_after_camera_release(self):
        samples = [np.ones(128, dtype=np.float32) for _ in range(18)]
        code, released, _, _, saved = self.session(samples, True)
        self.assertEqual(code, 0)
        self.assertTrue(released)
        self.assertEqual(saved.shape, (21, 128))
        np.testing.assert_array_equal(saved[:3], np.full((3, 128), .25))


if __name__ == '__main__':
    unittest.main()
