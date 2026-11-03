import importlib.util
import ctypes
import time
import io
import os
import queue
import sys
from pathlib import Path

root = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(root / 'src'))
spec = importlib.util.spec_from_file_location('webby_desktop', root / 'src' / 'desktop.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
read_fd, write_fd = os.pipe()
old_stdin = sys.stdin
sys.stdin = io.open(read_fd, encoding='utf-8')
app = module.Desktop()
try:
    assert app.sprite.width() <= 112 and app.sprite.height() <= 112
    assert app.shape is not None, 'X11 shape support is required on Ubuntu'
    app.on_event({'type':'server.connected','data':{}})
    app.on_event({'type':'session.execution.started','data':{'sessionID':'s'}})
    app.on_event({'type':'session.text.delta','data':{'sessionID':'s','delta':'Hello world '}})
    assert app.connected and 's' in app.sessions and app.pending == 'world'
    app.root.update()
    app.tick()
    assert app.word == 'world' and not app.pending
    app.on_event({'type':'permission.asked','data':{'sessionID':'s','id':'p'}})
    app.tick()
    assert 'p' in app.permissions and not app.word
    app.on_event({'type':'permission.replied','data':{'requestID':'p'}})
    assert not app.permissions
    app.dock('perched')
    assert app.mode == 'perched' and app.y > 0
    app.dock('hanging')
    assert app.mode == 'hanging' and app.y == 0
    # Real canvas rendering and X11 click-through, in addition to pure timing tests.
    app.on_event({'type':'session.reasoning.started','data':{'sessionID':'s'}})
    app.theatre.think_at = time.monotonic()-8
    app.tick()
    assert app.stage['scene'] == 'think' and app.stage['web'] == 1
    assert len(app.canvas.find_withtag('theatre-web')) == 13
    assert len(app.canvas.find_withtag('theatre-leg')) == 4
    display, window, x11, ext = app.shape
    ext.XShapeGetRectangles.argtypes = [ctypes.c_void_p, ctypes.c_ulong, ctypes.c_int, ctypes.POINTER(ctypes.c_int), ctypes.POINTER(ctypes.c_int)]
    ext.XShapeGetRectangles.restype = ctypes.POINTER(module.Rectangle)
    def contains_point(kind, x, y):
        count, order = ctypes.c_int(), ctypes.c_int()
        rects = ext.XShapeGetRectangles(display, window, kind, ctypes.byref(count), ctypes.byref(order))
        try: return any(r.x <= x < r.x+r.width and r.y <= y < r.y+r.height for r in rects[:count.value])
        finally:
            if rects: x11.XFree(rects)
    assert contains_point(0, 220, 12), 'Web must be visible'
    assert not contains_point(2, 220, 12), 'Web must not capture mouse input'
    assert not contains_point(0, 160, 80), 'Empty space beside a diagonal thread must remain transparent'
    app.motion = False
    app.tick()
    assert not app.canvas.find_withtag('theatre-web')
    assert app.stage['left'] == app.stage['right'] == 0
    app.motion = True
    app.on_event({'type':'session.execution.interrupted','data':{'sessionID':'s'}})
    app.theatre.idle_at = time.monotonic()-46
    app.tick()
    assert app.stage['scene'] == 'clean'
    app.theatre.idle_at = time.monotonic()-184
    app.tick()
    assert app.stage['scene'] == 'sleep'
    assert len(app.canvas.find_withtag('theatre-eyelid')) == 2
    app.on_event({'type':'session.execution.started','data':{'sessionID':'s'}})
    app.tick()
    assert app.stage['sleep'] == 0 and not app.canvas.find_withtag('theatre-eyelid')
    print('PASS: theatre rendering, sleep/wake, cancellation and click-through webs')
    print('PASS: Ubuntu Tk window, X11 transparency, events, animation, permissions and docking')
finally:
    app.root.destroy()
    os.close(write_fd)
    sys.stdin = old_stdin
