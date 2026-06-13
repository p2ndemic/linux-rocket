https://www.phoronix.com/forums/forum/phoronix/latest-phoronix-articles/1640206-wine-11-11-released-with-wayland-improvements?p=1640257#post1640257

https://discuss.cachyos.org/t/how-to-make-wine-applications-bigger-in-kde/30351/2

[https://discuss.cachyos.org/badges/2/member?username=the-burrito-triangle](https://discuss.cachyos.org/u/the-burrito-triangle/summary)

---

As someone who has extensively tested the Wine Wayland "driver", there is still a looooooooooot that needs to be done for general purpose windowing that is utterly broken right now. Like minimize, maximize and un-minimize (window disappears and cannot be restored). As well as window layering (child windows currently go behind the parent). It looks like Etaash Mathamsetty has a bunch of patches queued up to fix some of this, but they haven't yet been merged. Good to finally see someone addressing these grevious issues.

To be fair, gaming with the Wayland driver is mostly good to go. There are a few issues that Remi caused (by enforcing modern Windows behavior) that now require users to enable forced high DPI aware behavior for many games to scale correctly (otherwise they are scaled too large and overflow the screen). This scaling issue affects even some games released this year... That said, most games Just Work (TM).

Forced high DPI aware behavior:

```
Windows Registry Editor Version 5.00

[HKEY_CURRENT_USER\Software\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers]
@="~ HIGHDPIAWARE"
```

Enable Wine Wayland "driver":

```
Windows Registry Editor Version 5.00

[HKEY_CURRENT_USER\Software\Wine\Drivers]
"Graphics"="wayland,x11"
```

---

I use a 4k 27in monitor with 200% scaling, and Windows apps ran via Wine are tiny.

Wine’s app scaling is independent of your desktop environment. You fix Wine scaling by changing Wine’s settings, not some random setting in your desktop environment (except maybe something for letting Xwayland apps scale themselves).

To fix this, you simply change the “DPI” in winecfg:

“100%” Windows native scaling is 96 DPI (tiny on a modern display)

“200%” Windows native scaling is 192 DPI (still somewhat small on a modern display)

NOTE: Use the same scaling as your desktop environment. If you use fractional scaling, then multiply 96 by the fractional scaling factor. E.g., if you use 150% scaling, then set 96*1.5 = 144 DPI in winecfg. This is important to do correctly when you want to use the Wine Wayland driver instead of the Wine x11 driver + Xwayland–otherwise fullscreen apps will be made too large when the desktop environment uses >100% scaling factor.

screenshot2026-05-2701-51-47
screenshot2026-05-2701-51-47818×882 26.8 KB

However, just changing the DPI is not enough: Wine now defaults to bilinear upscaling (i.e. blurry upscaling).

To fix that you need to enable “forced high DPI aware” behavior in Wine:

Open a simple text editor, paste:

Windows Registry Editor Version 5.00

[HKEY_CURRENT_USER\Software\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers]
@="~ HIGHDPIAWARE"

then save as highdpiaware.reg. Finally, run wine regedit /path/to/highdpiaware.reg to import this setting into your prefix’s registry.

This will avoid blurry upscaling.
