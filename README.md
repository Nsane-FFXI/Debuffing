<img width="272" height="417" alt="df" src="https://github.com/user-attachments/assets/036fe407-b2e8-4374-8e81-2817ddabf2ea" /> <img width="272" height="417" alt="sabo" src="https://github.com/user-attachments/assets/58545240-c492-4528-9925-2bed4e05907c" />


# Debuffing — Command Reference

**Prefix:** use `//df` or `//debuffing`. Auto-translate tokens are supported, e.g. `{Paralyze}`.

## GLOBAL DURATION OVERRIDES
Set or remove a spell’s default duration for your character. No target required.

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
- The total includes +1 second.
- No hint or auto-update if the mob dies prior to timer disappearing off screen.

## AUTO-LEARN DURATIONS
Automatically update the override instead of hinting when a kept debuff vanishes.

- You must be targeting mob upon the buff wearing.
- Turning this ON/OFF the keep_buff will mimic the ON/OFF  
  `//df auto on | off`

## UI TOGGLES
- Colored names:   `//df colors on | off`
- Show timers:     `//df timer on | off`

## TESTING (simulation; no hints, no auto)
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
Wipe all debuffs from all targets in the UI box (no hints, no auto-update):  
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
- Timer learning adds +1 second when saving or hinting.
