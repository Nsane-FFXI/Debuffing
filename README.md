<img width="272" height="285" alt="0" src="https://github.com/user-attachments/assets/c8692241-9d50-458a-aef3-d81c5fd0363a" />
<img width="272" height="284" alt="1" src="https://github.com/user-attachments/assets/f97f5717-33ba-4fe0-84cb-4c6f41885050" />

Left Default Profile, Right Custom Profile, was made for saboteur.

<img width="271" height="265" alt="2" src="https://github.com/user-attachments/assets/30a39a1e-f131-4db1-b08e-5381268db226" />
<img width="272" height="227" alt="3" src="https://github.com/user-attachments/assets/12f4d834-6976-4050-ad9c-c2a4c560d81c" />
<img width="271" height="190" alt="4" src="https://github.com/user-attachments/assets/f8647336-42bf-4b38-bac0-2194d5dcf5d8" />

Some debuffs not showned.



# Debuffing — Command Reference

**Prefix:** use `//df` or `//debuffing`. Auto-translate tokens are supported, e.g. `{Paralyze}`.

## GLOBAL DURATION OVERRIDES
Set or remove a spell’s default duration for your character.

**Syntax:**  
`//df {Spell Name}|ID <seconds | remove>`

**Examples:**
```
    //df {Paralyze} 180
    //df 58 120
    //df {Paralyze} remove
```

## KEEP-BUFF DISPLAY
Toggle showing expired debuffs with a green +seconds counter.  
`//df keep_buff`

**Notes:**
- When the debuff finally disappears:
  - If auto is ON: saves the new total duration automatically.
  - If auto is OFF: prints a Timer hint: `//df {Spell} <seconds>`.
- No hint or auto-update if the mob dies prior to timer disappearing off screen.

## AUTO-LEARN DURATIONS
Automatically update the override instead of hinting when a kept debuff vanishes.

- You must be targeting mob upon the debuff wearing.
- Turning this ON/OFF the keep_buff will mimic the ON/OFF  
  `//df auto on | off`

## AUTO-PROFILES (Per Main Job)
Auto-load per-job overrides, and persist changes into that job’s profile.
Not on by default, once on remains on until turned off.
```
 //df auto_profiles on | off
```
Behavior when ON:
- On login and main job change:
  - Clears current overrides.
  - Loads profile named by the job short code (e.g., `WAR`, `WHM`). If missing, creates an empty profile with that label.
- Manual edits and auto-learns saves to job profile automatically.

## UI TOGGLES
- Colored names:   `//df colors on | off`
- Show timers:     `//df timer on | off`

## TESTING (simulation)
If testing Kaustra/Helix spell, can simulate DMG just put a number in anywhere.

**Apply a test debuff to yourself:**
`//df test {Spell Name} | ID`

**Remove that test debuff:**
`//df test {Spell Name} | ID remove`

**Clear all test debuffs:**
`//df test clear`

**Examples:**
```
    //df test {Kaustra}
    //df test 99999 {Kaustra}
    //df test {Kaustra} 99999
```

## CLEAR ACTIVE DEBUFFS
Wipe all debuffs from all targets in the UI box.
`//df clear`

## DURATION PROFILES
- Save current overrides as a profile:  
  `//df save <name>`
- Load a profile:  
  `//df load <name>`
- List profiles:  
  `//df list`
- Delete a profile:  
  `//df delete <name>`

## CLEAR ALL OVERRIDES - TIMER DEFAULTS
Remove all global duration overrides for your current character (profiles untouched):  
`//df reset`

## NOTES
- Commands accept `{Auto-Translate}`, plain names, or IDs.
- Overrides and profiles are per character.
- Files:
  - Overrides: `addons/Debuffing/data/durations.xml`
  - Profiles:  `addons/Debuffing/data/duration_profiles.xml`
