Dentro del cuerpo
=================

A first-person game about a remotely piloted micro-drone inside a human body.
Two chapters, about five minutes each, in English and Ukrainian.

Project page, source and issue tracker:
https://github.com/artmsh/dentro-del-cuerpo


Starting the game
-----------------

Run "Dentro del cuerpo.exe" from this folder. Keep the folder together: the
"shaders" folder beside the program is read at startup.

The program is not signed, so the first time it runs Windows SmartScreen may
show "Windows protected your PC". Choose "More info", then "Run anyway".

Requirements: 64-bit Windows 10 or Windows 11 and a graphics card that
supports Direct3D 11. Nothing needs installing. On a machine with no such
graphics card the game uses Windows' software renderer, which is correct but
slow; "Dentro del cuerpo.exe" --software selects it deliberately.


Controls
--------

                        Keyboard and mouse         Controller
Move                    W A S D, Space up, C down  left stick, A up, B down
Boost                   hold Shift                 click LS
Look                    mouse, or arrow keys       right stick
Left arm                hold Q or left button      hold LT
Right arm               hold E or right button     hold RT
Left arm tool           Z next; 1, 2, 3            LB next, d-pad left previous
Right arm tool          X next; 8, 9, 0            RB next, d-pad right previous
Identify / scan         T (or F)                   X
Mucus Tether (ch. 2)    G                          click RS, or d-pad up
Hint                    H                          Y
Skip a comms line       Tab                        View
Pause and resume        Esc                        Menu
Confirm, back           Enter, Esc                 A, B
Switch language         Tab (title, pause)         View, or d-pad left/right
Route map (title)       M                          Y
Full screen             Alt+Enter or F11
Quit                    Alt+F4

Xbox controllers and anything else that presents itself through XInput work
without setup. DualShock 4 and DualSense controllers are read directly over
USB or Bluetooth and show PlayStation button names. The prompts on screen
follow whichever device was used last.


Saved progress
--------------

%APPDATA%\Dentro del cuerpo\save.txt

It holds the chapters unlocked, the best grades, the atlas entries found and
the language. Deleting it starts over. To remove the game, delete this folder
and that one.


Licences
--------

The code is under the Apache License 2.0 (LICENSE.txt) and the artwork and
text under CC BY 4.0 (LICENSE-ARTWORK.txt). The fonts and the font rasteriser
built into the program are under their own licences, in the "licenses" folder.
