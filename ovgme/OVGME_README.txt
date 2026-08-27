ACTUAL METAR — OvGME package
=============================

This package installs the mod's files via OvGME (or JSGME), with no .exe
involved — for anyone who'd rather avoid the antivirus warning the
installer sometimes triggers (see why below).

Because OvGME can only copy files inside the DCS folder, there is ONE
MANUAL STEP it cannot automate: adding one line to MissionEditor.lua. It's
the only manual step in the whole process.

1. Enable this mod from OvGME like any other, with your profile pointing
   at your DCS World install folder (the one containing MissionEditor\ and
   bin\).

2. Open with Notepad:

     <your DCS install>\MissionEditor\MissionEditor.lua

   and paste this at the END of the file (don't delete anything already
   there, just add these 3 lines at the end):

     -- ACTUAL-METAR-BEGIN (no editar a mano; gestionado por install.ps1)
     require('actual_metar.init')
     -- ACTUAL-METAR-END

   Save the file.

3. FULLY restart DCS World (not just the Mission Editor — the whole game),
   because MissionEditor.lua only loads once per launch.

4. Open the Mission Editor: "ACTUAL METAR" should now be in the top menu
   bar.

To uninstall: disable the mod from OvGME AND manually remove those 3 lines
from MissionEditor.lua (OvGME can't do that for you either, on uninstall).

Note about bin-mt\: if your DCS install doesn't use the multithreaded
build, this package may create a "bin-mt" folder holding 3 unused DLLs.
Harmless — DCS never reads it if it doesn't need it.

Why this package in addition to the .exe? The .exe installer is more
convenient (one click, done), but since it isn't digitally signed, some
antivirus software flags it as suspicious the first time it's downloaded
or run — a known, common false positive for unsigned PyInstaller tools
(see the "Is this safe?" section of the project's README). This package
avoids the problem entirely, since there's no compiled executable at all,
just plain files that OvGME copies over.
