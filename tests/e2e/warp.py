import ctypes, sys
x11 = ctypes.cdll.LoadLibrary('libX11.so.6')
x11.XOpenDisplay.restype = ctypes.c_void_p
d = x11.XOpenDisplay(None)
root = x11.XDefaultRootWindow(ctypes.c_void_p(d))
x11.XWarpPointer(ctypes.c_void_p(d), 0, ctypes.c_ulong(root), 0, 0, 0, 0, int(sys.argv[1]), int(sys.argv[2]))
x11.XFlush(ctypes.c_void_p(d)); x11.XCloseDisplay(ctypes.c_void_p(d))
