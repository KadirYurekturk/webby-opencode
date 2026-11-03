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
from theatre import Theatre, web_segments, leg_points, demo_frame

ROOT = Path(__file__).resolve().parent.parent
BG = '#010203'

class Rectangle(ctypes.Structure):
    _fields_ = [('x', ctypes.c_short), ('y', ctypes.c_short), ('width', ctypes.c_ushort), ('height', ctypes.c_ushort)]

class Desktop:
    def __init__(self, demo=False):
        self.demo = demo
        self.demo_at = time.monotonic()
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
        # The front pair is drawn as independent joints; keep the original asset intact.
        self.body = self.sprite.copy()
        w, h = self.body.width(), self.body.height()
        for x0, x1 in ((.12, .36), (.64, .88)):
            for y in range(int(h * .56), int(h * .80)):
                for x in range(int(w * x0), int(w * x1)):
                    self.body.transparency_set(x, y, True)
        self.theatre = Theatre()
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
        if not demo:
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

    def apply_shape(self, rects, input_rects=None):
        if not self.shape: return
        display, window, x11, ext = self.shape
        array = (Rectangle * len(rects))(*(Rectangle(*r) for r in rects))
        ext.XShapeCombineRectangles(display, window, 0, 0, 0, array, len(rects), 0, 0)
        if input_rects is not None:
            inputs = (Rectangle * len(input_rects))(*(Rectangle(*r) for r in input_rects))
            ext.XShapeCombineRectangles(display, window, 2, 0, 0, inputs, len(input_rects), 0, 0)
        x11.XFlush(display)

    def read_events(self):
        for line in sys.stdin:
            try: self.events.put_nowait(json.loads(line))
            except (ValueError, queue.Full): pass
        self.closed = True

    def on_event(self, event):
        kind, data = event.get('type'), event.get('data') or {}
        sid = data.get('sessionID')
        self.theatre.event(kind, data, time.monotonic())
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
        stage = self.theatre.frame(mood, now, not self.motion or bool(self.drag) or self.hover)
        if self.demo and self.motion and not self.drag and not self.hover:
            mood, stage = demo_frame(now - self.demo_at)
            if mood == 'working' and now-self.last_cast >= 4: self.pending = 'code'
        self.stage = stage
        self.canvas.delete('all')
        sy = 76 if self.mode == 'hanging' else 112
        if self.mode == 'hanging': self.canvas.create_line(120, 0, 120, sy+36, fill='#70bda8')
        offset = math.sin(now*3)*2 if self.motion and mood == 'working' else 0
        offset += stage['bob']
        for line in web_segments(stage['web']):
            self.canvas.create_line(*line, fill='#589b8a', width=1, tags='theatre-web')
        if stage['thread']:
            target = (207, 51) if stage['web'] else (120, 3)
            self.canvas.create_line(120, sy+68+offset, *target, fill='#70bda8', tags='theatre-thread')
        self.canvas.create_image(120, sy+56+offset, image=self.body)
        top = sy + 56 + offset - self.body.height()/2
        for side, angle in ((-1, stage['left']), (1, stage['right'])):
            points = leg_points(120, top, self.body.width(), self.body.height(), side, angle)
            coords = [v for point in points for v in point]
            self.canvas.create_line(*coords, fill='#171c29', width=7, joinstyle='miter', tags='theatre-leg')
            self.canvas.create_line(*coords, fill='#43dda8', width=2, joinstyle='miter', tags='theatre-leg')
        if stage['sleep']:
            for x in (120-self.body.width()*.072, 120+self.body.width()*.066):
                y = top + self.body.height()*.57
                self.canvas.create_rectangle(x-5,y,x+5,y+11*stage['sleep'],fill='#303341',outline='',tags='theatre-eyelid')
        rects = []
        if self.mode == 'hanging': rects.append((119,0,3,sy+37))
        # Only opaque sprite pixels capture input on X11.
        left = 120-self.sprite.width()//2; top = int(sy+56+offset-self.sprite.height()//2)
        for y in range(self.sprite.height()):
            start = None
            for x in range(self.sprite.width()+1):
                opaque = x < self.sprite.width() and not self.body.transparency_get(x,y)
                if opaque and start is None: start=x
                if not opaque and start is not None:
                    rects.append((left+start,top+y,x-start,1)); start=None
        if self.motion and not self.drag and not self.hover and mood in ('working','done'):
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
        visual_rects = list(rects)
        for tag in ('theatre-web', 'theatre-thread', 'theatre-leg', 'theatre-eyelid'):
            for item in self.canvas.find_withtag(tag):
                shapes = []
                if self.canvas.type(item) == 'line':
                    # Follow the stroke, not its bounding box: a diagonal line's
                    # box would expose a large opaque background on X11.
                    points = self.canvas.coords(item)
                    radius = math.ceil(float(self.canvas.itemcget(item, 'width'))/2)
                    for i in range(0, len(points)-2, 2):
                        x1,y1,x2,y2 = points[i:i+4]
                        steps = max(1, math.ceil(max(abs(x2-x1), abs(y2-y1))))
                        for n in range(steps+1):
                            x = round(x1+(x2-x1)*n/steps)
                            y = round(y1+(y2-y1)*n/steps)
                            shapes.append((x-radius,y-radius,x+radius+1,y+radius+1))
                else:
                    box = self.canvas.bbox(item)
                    if box: shapes.append(box)
                for x1,y1,x2,y2 in shapes:
                    x1,y1,x2,y2 = max(0,x1),max(0,y1),min(240,x2),min(230,y2)
                    if x2 > x1 and y2 > y1:
                        rect = (x1,y1,x2-x1,y2-y1)
                        visual_rects.append(rect)
                        if tag == 'theatre-leg': rects.append(rect)
        self.apply_shape(visual_rects, rects)
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
    try: Desktop(demo='--demo' in sys.argv[1:]).root.mainloop()
    except (tk.TclError, OSError, RuntimeError): sys.exit(1)
