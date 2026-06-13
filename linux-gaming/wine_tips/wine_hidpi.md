https://www.phoronix.com/forums/forum/phoronix/latest-phoronix-articles/1640206-wine-11-11-released-with-wayland-improvements?p=1640257#post1640257

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

