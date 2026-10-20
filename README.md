# Line Tracker for Transport Fever 3

A live route map for your lines. It shows every station on a line, and every vehicle on it as a teardrop pointing the way it is travelling, coloured by how full it is.

It appears in three places:

- **Line window:** a "Line Map" section below Balance.
- **Line manager:** a route card right below the stop list of the selected line. It changes as you click through your lines.
- **Vehicle window:** a "Line Map" section showing that vehicle's line. The selected vehicle is in full colour and the others are faded.

Hover a station to see what is waiting there for that line, with cargo icons. Hover a vehicle to see its load (for example "19/95 (20%)" with the passenger icon).

Vehicle colours go from green (empty) through yellow to red (full).

## Install

1. Download this repository: **Code > Download ZIP**, then unzip it.
2. Copy the folder `luke_line_tracker_1` into your Transport Fever 3 user mods folder:

   ```
   C:\Program Files (x86)\Steam\userdata\<your Steam ID>\3493540\local\mods\
   ```

   `3493540` is Transport Fever 3's Steam app ID. If you have more than one numbered folder under `userdata`, use the one that contains `3493540`.

3. **Fully restart the game.** Local mods are only picked up at startup.
4. Enable **Line Tracker** in the mod list when starting or loading a game.

On Windows you can run `install.ps1` instead of copying by hand. It finds the mods folder and copies the mod there:

```
powershell -ExecutionPolicy Bypass -File install.ps1
```

## Good to know

- **Safe for existing saves.** It only changes the interface, so you can add it to a save in progress or remove it at any time.
- **Achievements stay on.** The mod is marked cosmetic.
- **Taller info windows.** Info windows (lines, stations, towns and so on) may grow up to 1300 px tall before they scroll, instead of 900 px, so the Line Map fits without scrolling.
- **Updating.** Replace the `luke_line_tracker_1` folder with the new version and restart the game.

## Problems

If something goes wrong, the game writes a log to:

```
C:\Program Files (x86)\Steam\userdata\<your Steam ID>\3493540\local\crash_dump\stdout.txt
```

Lines starting with `Line Tracker:`, or errors that mention `Luke`, come from this mod. Please include them when you report a problem.
