"""Quiet, interruptible stage directions; no GUI or conversation text required."""
import math


class Theatre:
    def __init__(self):
        self.thinking = set()
        self.think_at = None
        self.idle_at = None
        self.next_idle = 45.0
        self.idle_index = 0
        self.act_at = None
        self.act = ''
        self.web = 0.0
        self.collect_at = None

    def event(self, kind, data, now):
        sid = data.get('sessionID')
        if kind == 'session.reasoning.started' and sid:
            if not self.thinking:
                self.think_at = now
            self.thinking.add(sid)
        elif kind in ('session.text.delta', 'session.tool.input.started',
                      'session.execution.succeeded', 'session.execution.failed',
                      'session.execution.interrupted', 'session.deleted'):
            self.thinking.discard(sid)
        elif kind == 'transport.disconnected':
            self.thinking.clear()

    def frame(self, mood, now, blocked=False):
        frame = dict(scene='rest', left=0.0, right=0.0, bob=0.0,
                     sleep=0.0, web=0.0, thread=False)
        if blocked or mood in ('waiting', 'offline', 'error'):
            self.idle_at = self.act_at = self.think_at = self.collect_at = None
            self.thinking.clear()
            self.web = 0.0
            self.next_idle = 45.0
            return frame
        if mood != 'idle':
            self.idle_at = self.act_at = None
            self.next_idle = 45.0
        if mood == 'working':
            self.collect_at = None
            if self.thinking:
                if self.think_at is None:
                    self.think_at = now
                elapsed = max(0, now - self.think_at)
                self.web = max(self.web, min(1, elapsed / 8))
                frame.update(scene='think', left=-18 + math.sin(elapsed * 4) * 12,
                             right=12 + math.sin(elapsed * 4 + 2) * 15,
                             thread=True)
            else:
                frame.update(scene='weave', left=math.sin(now * 5) * 14,
                             right=math.sin(now * 5 + math.pi) * 14)
        elif mood == 'done' or (mood == 'idle' and self.web > 0):
            if self.collect_at is None:
                self.collect_at = now
                self.collect_web = self.web
            p = min(1, max(0, (now - self.collect_at) / 3))
            self.web = self.collect_web * (1 - p)
            frame.update(scene='collect' if p < 1 else 'rest',
                         left=math.sin(p * math.pi * 6) * 18 * (1 - p),
                         right=-math.sin(p * math.pi * 6) * 18 * (1 - p),
                         thread=self.web > 0)
        elif mood == 'idle':
            if self.idle_at is None:
                self.idle_at = now
            elapsed = now - self.idle_at
            if elapsed >= 180:
                frame.update(scene='sleep', sleep=min(1, (elapsed - 180) / 3),
                             bob=math.sin(now * 1.3) * 1.5)
            else:
                if self.act_at is None and elapsed >= self.next_idle:
                    self.act = ('clean', 'tug')[self.idle_index % 2]
                    self.idle_index += 1
                    self.act_at = now
                if self.act_at is not None:
                    t = now - self.act_at
                    if t >= 3.2:
                        self.act_at = None
                        self.next_idle = elapsed + (45 if self.idle_index % 2 else 57)
                    else:
                        envelope = math.sin(t / 3.2 * math.pi)
                        frame['scene'] = self.act
                        if self.act == 'clean':
                            frame.update(left=-32 * envelope + math.sin(t * 14) * 5 * envelope,
                                         right=32 * envelope - math.sin(t * 14) * 5 * envelope)
                        else:
                            frame.update(left=-42 * envelope, right=22 * envelope,
                                         bob=-abs(math.sin(t * 4)) * 4 * envelope,
                                         thread=True)
        frame['web'] = self.web
        return frame


def web_segments(progress):
    """A bounded little web in the companion's upper right corner."""
    lines = [(228, 12, 162, 12), (228, 12, 167, 39),
             (228, 12, 182, 61), (228, 12, 211, 76)]
    for radius in (22, 43, 66):
        points = [(228 - radius, 12), (228 - radius * .92, 12 + radius * .41),
                  (228 - radius * .70, 12 + radius * .74),
                  (228 - radius * .26, 12 + radius * .97)]
        lines.extend((*a, *b) for a, b in zip(points, points[1:]))
    result = []
    for index, (x1, y1, x2, y2) in enumerate(lines):
        p = max(0, min(1, progress * len(lines) - index))
        if p:
            result.append((x1, y1, x1 + (x2 - x1) * p, y1 + (y2 - y1) * p))
    return result


def leg_points(cx, top, width, height, side, angle):
    root = (cx + side * width * .15, top + height * .62)
    radians = math.radians(angle)
    points = [root]
    for dx, dy in ((side * width * .16, height * .02),
                   (side * width * .19, height * .15)):
        points.append((root[0] + dx * math.cos(radians) - dy * math.sin(radians),
                       root[1] + dx * math.sin(radians) + dy * math.cos(radians)))
    return points


def demo_frame(now):
    """Thirty-six-second tour without a server or model request."""
    t = now % 36
    stage = Theatre()
    if t < 15:
        stage.frame('idle', 0)
        if t < 5:
            stage.frame('idle', 45)
            return 'idle', stage.frame('idle', 45 + t)
        if t < 10:
            stage.idle_index = 1
            stage.frame('idle', 45)
            return 'idle', stage.frame('idle', 45 + t - 5)
        return 'idle', stage.frame('idle', 183 + t - 10)
    stage.event('session.reasoning.started', {'sessionID': 'demo'}, 0)
    if t < 25:
        return 'working', stage.frame('working', t - 15)
    stage.frame('working', 8)
    stage.event('session.text.delta', {'sessionID': 'demo'}, 8)
    if t < 30:
        return 'working', stage.frame('working', t - 17)
    stage.frame('done', 0)
    return 'done', stage.frame('done', t - 30)
