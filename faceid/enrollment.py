"""Head-angle coverage for the two guided enrollment passes.

YuNet supplies five 2D landmarks, not a depth map. Ratios relative to the eyes
and mouth let us follow gentle head movement independently of camera distance.
The first frontal sample calibrates those ratios for this person's face.
"""
import math

import numpy as np


SECTORS = 8


def face_position(face, frame_shape):
    """The preview is a mirrored, central square of the actual capture frame."""
    height, width = frame_shape[:2]
    side = min(width, height)
    x, y, w, h = map(float, face[:4])
    if min(w, h) < 80 or w / side < 0.22:
        return "closer"
    if w / side > 0.72 or h / side > 0.84:
        return "farther"
    cx = (x + w / 2 - width / 2) / side
    cy = (y + h / 2 - height / 2) / side
    if math.hypot(cx, cy) > 0.18:
        return "center"
    return "move"


def landmark_pose(face):
    eyes = np.asarray(face[4:8], dtype=float).reshape(2, 2)
    nose = np.asarray(face[8:10], dtype=float)
    mouth = np.asarray(face[10:14], dtype=float).reshape(2, 2).mean(axis=0)
    eye_center = eyes.mean(axis=0)
    eye_width = float(np.linalg.norm(eyes[1] - eyes[0]))
    vertical = float(mouth[1] - eye_center[1])
    if eye_width < 12 or vertical < 12:
        return None
    # Reject a very tilted head rather than interpreting roll as yaw or pitch.
    if abs(eyes[1, 1] - eyes[0, 1]) / eye_width > 0.45:
        return None
    return ((nose[0] - eye_center[0]) / eye_width,
            (nose[1] - eye_center[1]) / vertical)


class HeadCoverage:
    def __init__(self, samples_per_sector=1):
        self.required = samples_per_sector
        self.neutral = None
        self.reset_pass()

    def reset_pass(self):
        self.counts = [0] * SECTORS
        self.centered = False

    @property
    def coverage(self):
        return [min(1.0, count / self.required) for count in self.counts]

    @property
    def complete(self):
        return self.centered and all(count >= self.required for count in self.counts)

    def direction(self, pose):
        if self.neutral is None:
            return None, 0.0, 0.0
        # Mirror horizontal movement to match the selfie preview. Sector 0 is up.
        x = -(pose[0] - self.neutral[0]) / 0.16
        y = (pose[1] - self.neutral[1]) / 0.14
        if math.hypot(x, y) < 0.72:
            return None, x, y
        angle = math.atan2(x, -y)
        return int(math.floor(angle * SECTORS / math.tau + 0.5)) % SECTORS, x, y

    def capture(self, pose):
        """Return true only when a frame contributes a missing head angle."""
        if self.neutral is None:
            self.neutral = pose
        sector, x, y = self.direction(pose)
        if not self.centered:
            if math.hypot(x, y) > 0.5:
                return False
            self.centered = True
            return True
        if sector is None or self.counts[sector] >= self.required:
            return False
        self.counts[sector] += 1
        return True
