import importlib.util
import io
import os
import queue
import sys
from pathlib import Path

root = Path(__file__).resolve().parent.parent
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
    print('PASS: Ubuntu Tk window, X11 transparency, events, animation, permissions and docking')
finally:
    app.root.destroy()
    os.close(write_fd)
    sys.stdin = old_stdin
