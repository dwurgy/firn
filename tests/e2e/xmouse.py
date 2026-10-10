# A real (system) mouse for the checks, through X's test extension:
#   python3 xmouse.py move X Y | down | up
# Unlike the test tool's mouse, which talks to one page directly, this goes
# through the window system, as a person's mouse does.
import ctypes, sys
x11 = ctypes.cdll.LoadLibrary('libX11.so.6')
xtst = ctypes.cdll.LoadLibrary('libXtst.so.6')
x11.XOpenDisplay.restype = ctypes.c_void_p
d = ctypes.c_void_p(x11.XOpenDisplay(None))
what = sys.argv[1]
if what == 'move':
    xtst.XTestFakeMotionEvent(d, -1, int(sys.argv[2]), int(sys.argv[3]), 0)
else:
    xtst.XTestFakeButtonEvent(d, 1, 1 if what == 'down' else 0, 0)
x11.XFlush(d)
x11.XCloseDisplay(d)
