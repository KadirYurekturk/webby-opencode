"""Small standard-library desktop companion for X11 and macOS Tk.

OpenCode owns this process and sends JSON events on stdin. Text is never logged.
"""
import ctypes
import json
import math
import os
import queue
import re
import sys
import threading
import time
import tkinter as tk
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BG = '#010203'

class Rectangle(ctypes.Structure):
    _fields_ = [('x', ctypes.c_short), ('y', ctypes.c_short), ('width', ctypes.c_ushort), ('height', ctypes.c_ushort)]

class Desktop:
    def __init__(self):
        self.root = tk.Tk(className='Webby')
        self.root.title('Webby')
        self.root.overrideredirect(True)
        self.root.attributes('-topmost', True)
        if sys.platform == 'darwin':
            self.root.config(bg='systemTransparent')
            self.root.attributes('-transparent', True)
            color = 'systemTransparent'
        else:
            self.root.config(bg=BG)
            color = BG
        self.canvas = tk.Canvas(self.root, width=240, height=230, bg=color, highlightthickness=0)
        self.canvas.pack()
        source = tk.PhotoImage(file=str(ROOT / 'assets' / 'webby.png'))
        self.sprite = source.subsample(max(1, math.ceil(source.width() / 112)))
        self.screen_w, self.screen_h = self.root.winfo_screenwidth(), self.root.winfo_screenheight()
        self.x, self.y = max(0, self.screen_w - 260), 0
        self.root.geometry(f'240x230+{self.x}+{self.y}')
        self.events = queue.Queue(maxsize=512)
        self.closed = False
        self.connected = False
        self.sessions, self.permissions = set(), {}
        self.mode = 'hanging'
        self.motion = True
        self.drag = None
        self.hover = False
        self.mood = 'offline'
        self.label = 'Offline'
        self.result_until = 0
        self.word = ''
        self.pending = ''
        self.buffer = ''
        self.buffer_session = None
        self.last_cast = 0
        self.cast_at = 0
        self.menu = tk.Menu(self.root, tearoff=False)
        self.menu.add_command(label='Hang from top edge', command=lambda: self.dock('hanging'))
        self.menu.add_command(label='Perch at bottom edge', command=lambda: self.dock('perched'))
        self.menu.add_command(label='Toggle motion', command=self.toggle_motion)
        self.menu.add_command(label='Close Webby', command=self.root.destroy)
        self.canvas.bind('<ButtonPress-1>', self.press)
        self.canvas.bind('<B1-Motion>', self.move)
        self.canvas.bind('<ButtonRelease-1>', self.release)
        self.canvas.bind('<Button-3>', self.show_menu)
        if sys.platform == 'darwin': self.canvas.bind('<Button-2>', self.show_menu)
        self.canvas.bind('<Enter>', lambda e: setattr(self, 'hover', True))
        self.canvas.bind('<Leave>', lambda e: setattr(self, 'hover', False))
        self.root.bind('<Escape>', lambda e: self.root.destroy())
        self.root.update_idletasks()
        self.shape = self.x11_shape() if sys.platform.startswith('linux') else None
        if sys.platform.startswith('linux') and not self.shape:
            self.root.destroy()
            raise RuntimeError('An X11 display with the Shape extension is required')
        threading.Thread(target=self.read_events, daemon=True).start()
        self.tick()

    def x11_shape(self):
        try:
            x11 = ctypes.CDLL('libX11.so.6'); ext = ctypes.CDLL('libXext.so.6')
            x11.XOpenDisplay.argtypes = [ctypes.c_char_p]; x11.XOpenDisplay.restype = ctypes.c_void_p
            display = x11.XOpenDisplay(None)
            if not display: return None
            x11.XQueryTree.argtypes = [ctypes.c_void_p, ctypes.c_ulong, ctypes.POINTER(ctypes.c_ulong), ctypes.POINTER(ctypes.c_ulong), ctypes.POINTER(ctypes.POINTER(ctypes.c_ulong)), ctypes.POINTER(ctypes.c_uint)]
            x11.XFree.argtypes = [ctypes.c_void_p]; x11.XFlush.argtypes = [ctypes.c_void_p]
            ext.XShapeCombineRectangles.argtypes = [ctypes.c_void_p, ctypes.c_ulong, ctypes.c_int, ctypes.c_int, ctypes.c_int, ctypes.POINTER(Rectangle), ctypes.c_int, ctypes.c_int, ctypes.c_int]
            root, parent, children, n = ctypes.c_ulong(), ctypes.c_ulong(), ctypes.POINTER(ctypes.c_ulong)(), ctypes.c_uint()
            x11.XQueryTree(display, self.root.winfo_id(), ctypes.byref(root), ctypes.byref(parent), ctypes.byref(children), ctypes.byref(n))
            if children: x11.XFree(children)
            return display, parent.value, x11, ext
        except (OSError, AttributeError): return None

    def apply_shape(self, rects):
        if not self.shape: return
        display, window, x11, ext = self.shape
        array = (Rectangle * len(rects))(*(Rectangle(*r) for r in rects))
        ext.XShapeCombineRectangles(display, window, 0, 0, 0, array, len(rects), 0, 0)
        x11.XFlush(display)

    def read_events(self):
        for line in sys.stdin:
            try: self.events.put_nowait(json.loads(line))
            except (ValueError, queue.Full): pass
        self.closed = True

    def on_event(self, event):
        kind, data = event.get('type'), event.get('data') or {}
        sid = data.get('sessionID')
        if kind == 'server.connected': self.connected = True
        elif kind == 'session.execution.started' and sid: self.sessions.add(sid)
        elif kind == 'permission.asked' and sid and data.get('id'): self.permissions[data['id']] = sid
        elif kind == 'permission.replied': self.permissions.pop(data.get('requestID'), None)
        elif kind == 'session.text.delta' and sid:
            if sid != self.buffer_session: self.buffer, self.buffer_session = '', sid
            text = self.buffer + str(data.get('delta', ''))[:2048]
            words = re.findall(r'(?<![\w])[A-Za-zÀ-ÿ]{3,10}(?![\w])(?=[\s.,!?;:])', text)
            if words: self.pending = words[-1]
            tail = re.search(r'[A-Za-zÀ-ÿ]+$', text)
            self.buffer = tail.group(0) if tail and len(tail.group(0)) <= 10 else ''
        elif kind in ('session.execution.succeeded', 'session.execution.failed', 'session.execution.interrupted', 'session.deleted'):
            self.sessions.discard(sid)
            self.permissions = {key: value for key, value in self.permissions.items() if value != sid}
            self.buffer = ''
            if kind in ('session.execution.succeeded', 'session.execution.failed'):
                self.mood = 'done' if kind.endswith('succeeded') else 'error'
                self.result_until = time.monotonic() + 8

    def tick(self):
        if self.closed:
            self.root.destroy(); return
        for _ in range(100):
            try: self.on_event(self.events.get_nowait())
            except queue.Empty: break
        now = time.monotonic()
        mood = 'waiting' if self.permissions else 'working' if self.sessions else self.mood if now < self.result_until else 'idle' if self.connected else 'offline'
        labels = {'waiting':'Permission needed', 'working':'Weaving code...', 'idle':'Ready when you are', 'done':'All done!', 'error':'Something went wrong', 'offline':'Offline'}
        self.canvas.delete('all')
        sy = 76 if self.mode == 'hanging' else 112
        if self.mode == 'hanging': self.canvas.create_line(120, 0, 120, sy+36, fill='#70bda8')
        offset = math.sin(now*3)*2 if self.motion and mood == 'working' else 0
        self.canvas.create_image(120, sy+56+offset, image=self.sprite)
        rects = []
        if self.mode == 'hanging': rects.append((119,0,3,sy+37))
        # Only opaque sprite pixels capture input on X11.
        left = 120-self.sprite.width()//2; top = int(sy+56+offset-self.sprite.height()//2)
        for y in range(self.sprite.height()):
            start = None
            for x in range(self.sprite.width()+1):
                opaque = x < self.sprite.width() and not self.sprite.transparency_get(x,y)
                if opaque and start is None: start=x
                if not opaque and start is not None:
                    rects.append((left+start,top+y,x-start,1)); start=None
        if self.motion and mood in ('working','done'):
            if self.pending and not self.word and now-self.last_cast >= 4:
                self.word, self.pending = self.pending, ''
                self.cast_at = self.last_cast = now
            if self.word:
                elapsed=now-self.cast_at
                if elapsed >= 1.8: self.word=''
                else:
                    pull=max(0,min(1,(elapsed-.3)/1.5)); x=190-70*pull; y=sy+6+50*pull
                    self.canvas.create_line(120,sy+56,x,y,fill='#91eacb')
                    self.canvas.create_text(x,y,text=self.word,fill='#91eacb',font=('Courier',12,'bold'))
                    rects.append((max(0,int(x)-45),max(0,int(y)-12),90,24))
        else: self.pending=''; self.word=''; self.buffer=''
        if self.hover or mood in ('waiting','done','error'):
            y = 208 if self.mode == 'hanging' else 88
            self.canvas.create_text(120,y,text=labels[mood],fill='#ffcf83' if mood=='waiting' else '#91eacb',font=('Helvetica',11,'bold'))
            rects.append((20,y-12,200,24))
        self.apply_shape(rects)
        self.root.after(80,self.tick)

    def dock(self, mode):
        self.mode=mode; self.y=0 if mode=='hanging' else max(0,self.screen_h-270)
        self.x=max(0,min(self.x,self.screen_w-240))
        self.root.geometry(f'240x230+{self.x}+{self.y}')
    def toggle_motion(self): self.motion=not self.motion
    def show_menu(self,event): self.menu.tk_popup(event.x_root,event.y_root)
    def press(self,event): self.drag=(event.x_root,event.y_root,self.x,self.y)
    def move(self,event):
        if self.drag:
            sx,sy,x,y=self.drag; self.x=max(0,x+event.x_root-sx); self.y=max(0,y+event.y_root-sy)
            self.root.geometry(f'240x230+{self.x}+{self.y}')
    def release(self,event):
        if self.drag: self.dock('hanging' if self.y < self.screen_h/2 else 'perched')
        self.drag=None

if __name__ == '__main__':
    try: Desktop().root.mainloop()
    except (tk.TclError, OSError, RuntimeError): sys.exit(1)
