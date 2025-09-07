<img width="272" height="285" alt="0" src="https://github.com/user-attachments/assets/c8692241-9d50-458a-aef3-d81c5fd0363a" />
<img width="272" height="284" alt="1" src="https://github.com/user-attachments/assets/f97f5717-33ba-4fe0-84cb-4c6f41885050" />

Left Default Profile, Right Custom Profile, was made for saboteur.

<img width="271" height="265" alt="2" src="https://github.com/user-attachments/assets/30a39a1e-f131-4db1-b08e-5381268db226" />
<img width="272" height="227" alt="3" src="https://github.com/user-attachments/assets/12f4d834-6976-4050-ad9c-c2a4c560d81c" />
<img width="271" height="190" alt="4" src="https://github.com/user-attachments/assets/f8647336-42bf-4b38-bac0-2194d5dcf5d8" />

Some debuffs not showned.



# Debuffing — Command Reference

**Prefix:** use `//df` or `//debuffing`. Auto-translate tokens are supported, e.g. `{Paralyze}`.

---

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

---

## KEEP-BUFF DISPLAY
Toggle showing expired debuffs with a green +seconds counter.  
`//df keep_buff`

**Notes:**
- When the debuff finally disappears:
  - If auto is ON: saves the new total duration automatically.
  - If auto is OFF: prints a Timer hint: `//df {Spell} <seconds>`.
- No hint or auto-update if the mob dies prior to timer disappearing off screen.

---

## AUTO-LEARN DURATIONS
Automatically update the override instead of hinting when a kept debuff vanishes.

- You must be targeting the mob when the debuff wears.
- Turning this ON/OFF will also toggle `keep_buff`.  
  `//df auto on | off`

---

## AUTO-PROFILES (Per Main Job)
Auto-load per-job overrides, and persist changes into that job’s profile.  
Not on by default, once on remains on until turned off.
```
 //df auto_profiles on | off
```
Behavior when ON:
- On login and main job change:
  - Clears current overrides.
  - Loads profile named by the job short code (e.g., `WAR`, `WHM`).  
    If missing, creates an empty profile with that label.
- Manual edits and auto-learns save to job profile automatically.

---

## UI TOGGLES
- Colored names:   `//df colors on | off`
- Show timers:     `//df timer on | off`

---

## WEAPONS (WS-created debuff timers)
Track debuffs created by weapon skills. Toggle WS rows and define per-TP durations.

**Toggle WS rows in the UI**
```
    //df weapons on
    //df weapons off
```

**Create or update a WS→Buff rule**
```
    //df create <WS Name|ID> <Buff Name|ID> <sec[, sec, sec]>
```
- Provide either one duration (applies to all TP tiers) or three durations for 1000/2000/3000 TP in that order.
- Auto-translate tokens are allowed for both WS and Buff.

**Examples**
```
    //df create "Shell Crusher" "Defense Down" 180, 360, 540
    //df create "Tachi: Gekko" Silence 45
    //df create 42 7 90, 120, 150
```

**Delete a WS rule**
```
    //df delete <WS Name|ID>
```

**Notes**
- WS rows are labeled `<WS Name> (<Buff Name>)`.
- WS rows respect the global UI toggles (`colors`, `timer`) and the `weapons` visibility setting.

---

## TESTING (simulation)
If testing Kaustra/Helix spell, you can simulate DMG by including a number anywhere.

**Apply a test debuff to yourself:**
```
    //df test {Spell Name} | ID
```

**Remove that test debuff:**
```
    //df test {Spell Name} | ID remove
```

**Clear all test debuffs:**
```
    //df test clear
```

**Examples:**
```
    //df test {Kaustra}
    //df test 99999 {Kaustra}
    //df test {Kaustra} 99999
```

---

## UI VISIBILITY
The UI box is hidden until there is something to show.

**When it appears**
- At least one active debuff on your current target, or
- Simulation mode has at least one test entry.

**Force it to show (Simulation)**
Apply any test debuff to yourself:
```
    //df test {Paralyze}
    //df test {Kaustra}
```

**Clear simulation entries**
```
    //df test clear
```

---

## CLEAR ACTIVE DEBUFFS
Wipe all debuffs from all targets in the UI box.  
`//df clear`

---

## DURATION PROFILES
- Save current overrides as a profile:  
  `//df save <name>`
- Load a profile:  
  `//df load <name>`
- List profiles:  
  `//df list`
- Delete a profile:  
  `//df delete <name>`

---

## CLEAR ALL OVERRIDES — TIMER DEFAULTS
Remove all global duration overrides for your current character (profiles untouched):  
`//df reset`

---

## NOTES
- Commands accept `{Auto-Translate}`, plain names, or IDs.
- Overrides and profiles are per character.
- Files:
  - Overrides: `addons/Debuffing/data/durations.xml`
  - Profiles:  `addons/Debuffing/data/duration_profiles.xml`

---

## CHEAT SHEET

| Command | Description | Example |
|---------|-------------|---------|
| `//df {Spell}|ID <sec>` | Set duration override | `//df {Paralyze} 180` |
| `//df {Spell}|ID remove` | Remove override | `//df 58 remove` |
| `//df keep_buff` | Toggle expired buff display | `//df keep_buff` |
| `//df auto on|off` | Toggle auto-learn durations | `//df auto on` |
| `//df auto_profiles on|off` | Per-job profiles | `//df auto_profiles on` |
| `//df colors on|off` | Toggle colored names | `//df colors off` |
| `//df timer on|off` | Toggle timer display | `//df timer on` |
| `//df weapons on|off` | Show/hide WS rows | `//df weapons off` |
| `//df create <WS> <Buff> <sec[,sec,sec]>` | Create WS rule | `//df create "Shell Crusher" "Defense Down" 180,360,540` |
| `//df delete <WS>` | Delete WS rule | `//df delete "Shell Crusher"` |
| `//df test {Spell}` | Apply test debuff | `//df test {Kaustra}` |
| `//df test {Spell} remove` | Remove test debuff | `//df test {Kaustra} remove` |
| `//df test clear` | Clear test debuffs | `//df test clear` |
| `//df clear` | Clear all debuffs from UI | `//df clear` |
| `//df save <name>` | Save profile | `//df save WHM` |
| `//df load <name>` | Load profile | `//df load WHM` |
| `//df list` | List profiles | `//df list` |
| `//df delete <name>` | Delete profile | `//df delete WHM` |
| `//df reset` | Reset overrides | `//df reset` |
