_addon.name     = 'Debuffing'
_addon.author   = 'original: Auk, Overhauled by Nsane'
_addon.version  = '2025.9.5'
_addon.commands = {'df', 'debuffing'}

require('luau')
local file    = require('files')
local packets = require('packets')
local texts   = require('texts')
local config  = require('config')

local res, windower = res, windower
local player, simulation_mode = nil, false
local owner_key = 'unknown'
local others = require('others')

local function log(msg) windower.add_to_chat(207, ('[Debuffing] %s'):format(tostring(msg))) end

local defaults = {
    keep_buff_after_timer = false,
    auto_update_enabled   = false,
    auto_profiles_enabled = false,
    colors_enabled = true,
    timers_enabled = true,
    pos   = { x = 600, y = 300 },
    text  = { font = 'Consolas', size = 12 },
    flags = { bold = false, draggable = true },
    bg    = { alpha = 255 },
}
local settings = config.load(defaults)

local default_durations_xml = [[<?xml version="1.0"?><settings></settings>]]
local default_profiles_xml  = [[<?xml version="1.0"?><settings></settings>]]

local C = {
    dark={135,135,135}, earth={255,255,28}, ice={0,255,255}, light={255,255,255},
    water={0,150,255}, wind={51,255,20}, fire={255,22,12}, lightning={233,0,255},
}
local GREEN_TIMER = C.wind

local function cs(rgb, s) return ('\\cs(%d,%d,%d)%s\\cr'):format(rgb[1], rgb[2], rgb[3], s) end
local function lerp(a, b, t) return math.floor(a + (b - a) * t + 0.5) end
local function gradient_text(s, rgb_from, rgb_to)
    if not s or s == '' then return s end
    local len = #s
    if len == 1 then return cs(rgb_to, s) end
    local out = {}
    for i = 1, len do
        local t = (i - 1) / (len - 1)
        out[#out+1] = cs({lerp(rgb_from[1], rgb_to[1], t),
                          lerp(rgb_from[2], rgb_to[2], t),
                          lerp(rgb_from[3], rgb_to[3], t)}, s:sub(i, i))
    end
    return table.concat(out)
end

local ELEMENT_RGB = { [0]=C.fire,[1]=C.ice,[2]=C.wind,[3]=C.earth,[4]=C.lightning,[5]=C.water,[6]=C.light,[7]=C.dark }
local ABSORB_PART_COLOR = { STR=C.fire,DEX=C.lightning,VIT=C.earth,INT=C.ice,MND=C.water,CHR=C.light,AGI=C.wind,ACC=C.lightning }

local function base_name(s) local b=s:match('^([^%(]+)') or s; return (b:gsub('%s+$','')) end
local function colorize_absorb(fullname)
    if not settings.colors_enabled then return fullname end
    local bn = base_name(fullname); local stat = bn:match('Absorb%-%s*(%u+)'); if not stat then return fullname end
    local rgb = ABSORB_PART_COLOR[stat]; if not rgb then return fullname end
    local pre, post = fullname:match('^(.-)%s*(%(.+)$'); local main, suffix = pre or fullname, post or ''
    local label_grad = gradient_text(('Absorb-%s'):format(stat), C.dark, rgb)
    return (main:gsub('Absorb%s*%-%s*'..stat, label_grad, 1))..suffix
end

local frame_time, debuffed_mobs, TH, step_duration = 0, {}, {}, {}
local durations, duration_profiles = {}, {}

local debuffs_map = {}
local absorb_map = {
  [242]={effect=242,duration=90},[266]={effect=266,duration=90},[267]={effect=267,duration=90},[268]={effect=268,duration=90},
  [269]={effect=269,duration=90},[270]={effect=270,duration=90},[271]={effect=271,duration=90},[272]={effect=272,duration=90}
}
local ABSORB_IDS=(function() local s=S{} for id in pairs(absorb_map) do s[id]=true end return s end)()
local ja_map = { [150]={effect=149,duration=90}, [170]={effect=149,duration=90} }
local EXTREMES = { [502]={effect=23,element=7,duration=100}, [503]={effect=142,element=7,duration=180} }
local BloodPact_map = { [580]={duration=90},[585]={duration=90},[611]={duration=90},[617]={duration=180},[633]={duration=15},[657]={duration=60},[963]={duration=90},[966]={duration=180} }
local JA_SPELLS = S{496,497,498,499,500,501}
local ERASE_ABILITIES=S{2370,2571,2714,2718,2775,2831}
local PARTIAL_ERASE_ABILITIES=S{1245,1273}

-- Auto-profile state + helpers (case-insensitive keys)
local current_profile = nil
local function _norm_key(s) return tostring(s or ''):lower() end
local function _job_profile_name()
    player = windower.ffxi.get_player()
    if not player or not player.main_job_id then return nil end
    local j = res.jobs[player.main_job_id]
    return j and (j.ens or j.en) or nil
end
local function _deepcopy(t) if type(t)~='table' then return t end local r={} for k,v in pairs(t) do r[k]=_deepcopy(v) end return r end
local function _ensure_profile_tables()
    duration_profiles[owner_key] = duration_profiles[owner_key] or {}
    duration_profiles[owner_key].profiles = duration_profiles[owner_key].profiles or {}
    durations[owner_key] = durations[owner_key] or {}
    durations[owner_key].spells = durations[owner_key].spells or {}
end
local function _resolve_profile_key(name)
    if not name then return nil end
    _ensure_profile_tables()
    local store = duration_profiles[owner_key].profiles
    local want = _norm_key(name)
    if store[want] then return want end
    for k, v in pairs(store) do
        local label = type(v) == 'table' and v.label or nil
        if _norm_key(k) == want or (label and _norm_key(label) == want) then
            return _norm_key(k)
        end
    end
    return want
end
local function _apply_job_profile()
    if not settings.auto_profiles_enabled then current_profile = nil; return end
    _ensure_profile_tables()
    local pname = _job_profile_name(); if not pname then return end
    local key = _resolve_profile_key(pname)
    current_profile = key
    durations[owner_key].spells = {}
    local store = duration_profiles[owner_key].profiles
    store[key] = store[key] or { spells = {} }
    store[key].label = store[key].label or pname
    if store[key].spells then
        durations[owner_key].spells = _deepcopy(store[key].spells)
        log('Auto profile loaded: '..(store[key].label or key))
    else
        log('Auto profile new: '..(store[key].label or key))
    end
    config.save(duration_profiles, 'all')
    config.save(durations, 'all')
end
local function _sync_profile(spell_id, secs_or_nil)
    if not (settings.auto_profiles_enabled and current_profile) then return end
    _ensure_profile_tables()
    local store = duration_profiles[owner_key].profiles
    store[current_profile] = store[current_profile] or { spells = {} }
    if secs_or_nil == nil then
        store[current_profile].spells[tostring(spell_id)] = nil
    else
        store[current_profile].spells[tostring(spell_id)] = secs_or_nil
    end
    config.save(duration_profiles, 'all')
end

local function color_by_element(name, spell_id)
    if not spell_id then return nil end
    local ext = EXTREMES[spell_id]
    local s = ext or ((others and others.blue_magic and others.blue_magic[spell_id]) and {element=others.blue_magic[spell_id].element}) or res.spells[spell_id]
    if not s or s.element==nil then return nil end
    local rgb = ELEMENT_RGB[s.element]; if not rgb then return nil end
    local pre, post = name:match('^(.-)%s*(%(.+)$'); return pre and (cs(rgb, pre)..' '..post) or cs(rgb, name)
end
local function colorize_name(name, spell_id)
    if not settings.colors_enabled then return name end
    if (spell_id and ABSORB_IDS:contains(spell_id)) or name:find('^Absorb%-') then return colorize_absorb(name) end
    return color_by_element(name, spell_id) or name
end

local function tlen(t) local n=0; for _ in pairs(t or {}) do n=n+1 end; return n end
local function is_threnody_spell(id) local s=res.spells[id]; return s and s.en and s.en:find('Threnody') end
local function is_enemy(id) if not id then return false end local m=windower.ffxi.get_mob_by_id(id) return m and m.is_npc and (m.spawn_type==16 or m.claim_id~=0) end

-- Kaustra helpers
local function is_kaustra(entry)
    if not entry then return false end
    if tonumber(entry.id) == 502 then return true end
    return base_name(tostring(entry.name or '')):lower() == 'kaustra'
end
local function kaustra_store_dmg(tgt, effect_id, raw_param)
    local dmg = tonumber(raw_param) or 0
    local q = dmg / 4
    local n = math.floor(q / 100 + 0.5) * 100
    local label = (n >= 1000) and ((math.floor(n/1000) == n/1000) and string.format('%.0fk', n/1000) or string.format('%.1fk', n/1000)) or tostring(n)
    if debuffed_mobs[tgt] and debuffed_mobs[tgt][effect_id] then debuffed_mobs[tgt][effect_id].kaustra_dmg_str = label end
end

-- Helix helpers
local function is_helix_id(id) local s = res.spells[id]; return s and s.en and s.en:lower():find('helix') end
local function is_helix(entry)
    if not entry then return false end
    if tonumber(entry.id) and is_helix_id(entry.id) then return true end
    return base_name(tostring(entry.name or '')):lower():find('helix') ~= nil
end
local function helix_rgb(id) local s = res.spells[id]; local el = s and s.element; return (el and ELEMENT_RGB[el]) or C.light end
local function helix_store_dmg(tgt, effect_id, raw_param, spell_id)
    local dmg = tonumber(raw_param) or 0
    if dmg <= 0 then return end
    local capped = math.min(dmg, 10000)
    local n = math.floor(capped/100 + 0.5) * 100
    local label = (n >= 1000) and ((math.floor(n/1000) == n/1000) and string.format('%.0fk', n/1000) or string.format('%.1fk', n/1000)) or tostring(n)
    if debuffed_mobs[tgt] and debuffed_mobs[tgt][effect_id] then
        debuffed_mobs[tgt][effect_id].helix_dmg_str = label
        debuffed_mobs[tgt][effect_id].helix_rgb = helix_rgb(spell_id)
    end
end

local function remove_debuff(target, effect, opts)
    opts = opts or {}
    if not (debuffed_mobs[target] and debuffed_mobs[target][effect]) then return end
    local e = debuffed_mobs[target][effect]

    local function maybe_hint_or_auto()
        if not e or type(e) ~= 'table' then return end
        if not e.expired_at then return end
        if e.no_hint then return end
        if simulation_mode and player and target == player.id then return end
        if opts.no_hint then return end
        if not settings.keep_buff_after_timer then return end

        local up    = math.max(0, os.clock() - e.expired_at)
        local base  = tonumber(e.base_dur or 0) or 0
        local total = math.max(0, math.floor(base + up + 0.5))
        local clean = base_name((e.name or ''):gsub('\\cs%(%d+,%d+,%d+%)',''):gsub('\\cr',''))
        local sid   = tonumber(e.id or 0)

        if settings.auto_update_enabled and sid and sid > 0 then
            durations[owner_key] = durations[owner_key] or {}
            durations[owner_key].spells = durations[owner_key].spells or {}
            durations[owner_key].spells[tostring(sid)] = total
            config.save(durations, 'all')
            _sync_profile(sid, total)
            log(('Auto-updated: %s %ds'):format(clean, total))
        else
            log(('Timer hint: //df {%s} %d'):format(clean, total))
        end
    end

    maybe_hint_or_auto()
    debuffed_mobs[target][effect] = nil
end

local function clear_target_debuffs(tid, opts)
    if not debuffed_mobs[tid] then return end
    for eff,_ in pairs(debuffed_mobs[tid]) do remove_debuff(tid, eff, opts) end
    debuffed_mobs[tid] = nil
end

local box = texts.new('${current_string}', settings); box:show()

local function ja_label(spell_id, tier)
    local E = {
        [496] = {'Fire Damage', C.fire}, [497] = {'Ice Damage', C.ice},
        [498] = {'Wind Damage', C.wind}, [499] = {'Earth Damage', C.earth},
        [500] = {'Lightning Damage', C.lightning}, [501] = {'Water Damage', C.water},
    }
    local e = E[spell_id]; if not e then return 'Unknown' end
    local pct = math.max(1, math.min(5, tonumber(tier) or 1)) * 5
    return settings.colors_enabled and (cs(e[2], e[1])..cs(C.light, ' +')..cs(C.light, tostring(pct)..'%'))
           or string.format('%s Damage + %d%%', e[1], pct)
end

local function update_box()
    local function fmt_timer(entry, remain, is_expired)
        if not settings.timers_enabled then return '' end
        if not is_expired then
            if is_kaustra(entry) then
                local ticks = math.max(0, math.floor(remain / 3))
                return ' : ' .. tostring(ticks) .. ' ' .. cs(C.dark, 'ticks')
            elseif is_helix(entry) then
                local rgb = entry.helix_rgb or helix_rgb(entry.id)
                local tocks = math.max(0, math.floor(remain / 10))
                return ' : ' .. tostring(tocks) .. ' ' .. cs(rgb, 'tocks')
            else
                return ' : ' .. string.format('%.0f', remain)
            end
        else
            local up = math.max(0, os.clock() - (entry.expired_at or os.clock()))
            if is_kaustra(entry) then
                local upticks = math.floor(up / 3)
                return ' : ' .. cs(GREEN_TIMER, '+' .. tostring(upticks)) .. ' ' .. cs(C.dark, 'ticks')
            elseif is_helix(entry) then
                local rgb = entry.helix_rgb or helix_rgb(entry.id)
                local uptocks = math.floor(up / 10)
                return ' : ' .. cs(GREEN_TIMER, '+' .. tostring(uptocks)) .. ' ' .. cs(rgb, 'tocks')
            else
                return ' : ' .. cs(GREEN_TIMER, '+' .. string.format('%.0f', up))
            end
        end
    end

    local current_string = ''
    player = windower.ffxi.get_player()
    local target = windower.ffxi.get_mob_by_target('st') or windower.ffxi.get_mob_by_target('t')

    local function render_target(tid, tname)
        local debuff_table = debuffed_mobs[tid]
        local out = 'Debuffs ['..tname..']'
        if TH[tid] then out = out..'\n- '..TH[tid] end
        if debuff_table then
            for effect, sp in pairs(debuff_table) do
                if type(sp) == 'table' then
                    local remain = (sp.timer or 0) - os.clock()
                    if remain >= 0 then
                        local label = JA_SPELLS:contains(sp.name) and ja_label(sp.name, sp.tier) or colorize_name(sp.name, sp.id)
                        if not JA_SPELLS:contains(sp.name) then
                            if is_kaustra(sp) and sp.kaustra_dmg_str then label = cs(C.dark, sp.kaustra_dmg_str)..' '..label end
                            if is_helix(sp)  and sp.helix_dmg_str  then local rgb = sp.helix_rgb or helix_rgb(sp.id); label = cs(rgb, sp.helix_dmg_str)..' '..label end
                        end
                        out = out..'\n- '..label..fmt_timer(sp, remain, false)
                    elseif settings.keep_buff_after_timer then
                        if not sp.expired_at then sp.expired_at = os.clock() end
                        local label = JA_SPELLS:contains(sp.name) and ja_label(sp.name, sp.tier) or colorize_name(sp.name, sp.id)
                        if not JA_SPELLS:contains(sp.name) then
                            if is_kaustra(sp) and sp.kaustra_dmg_str then label = cs(C.dark, sp.kaustra_dmg_str)..' '..label end
                            if is_helix(sp)  and sp.helix_dmg_str  then local rgb = sp.helix_rgb or helix_rgb(sp.id); label = cs(rgb, sp.helix_dmg_str)..' '..label end
                        end
                        out = out..'\n- '..label..fmt_timer(sp, 0, true)
                    else
                        remove_debuff(tid, effect)
                    end
                elseif sp then
                    local s = res.spells[sp]; local sname = s and s.en or ('ID '..tostring(sp))
                    out = out..'\n- '..colorize_name(sname, sp)
                end
            end
        end
        return out
    end

    if target and is_enemy(target.id) then
        current_string = render_target(target.id, target.name)
    elseif simulation_mode and player and debuffed_mobs[player.id] and tlen(debuffed_mobs[player.id]) > 0 then
        current_string = render_target(player.id, player.name..' (Simulation)')
    elseif simulation_mode and player and (not debuffed_mobs[player.id] or tlen(debuffed_mobs[player.id]) == 0) then
        simulation_mode = false
    end
    box.current_string = current_string
end

local function handle_overwrites(target, new_spell_id, overwrites_list)
    if not debuffed_mobs[target] then return true end
    if is_threnody_spell(new_spell_id) then
        for eff, entry in pairs(debuffed_mobs[target]) do
            if type(entry) == 'table' and entry.name and entry.name:find('Threnody') then remove_debuff(target, eff) end
        end
        return true
    end
    for _, entry in pairs(debuffed_mobs[target]) do
        local old_overwrites = (res.spells[entry.id] and res.spells[entry.id].overwrites) or {}
        for _, v in ipairs(old_overwrites) do if new_spell_id == v then return false end end
    end
    for effect, entry in pairs(debuffed_mobs[target]) do
        for _, v in ipairs(overwrites_list) do if entry.id == v then remove_debuff(target, effect) end end
    end
    return true
end

local function apply_debuff(target, effect, spell_id, duration)
    if not debuffed_mobs[target] then debuffed_mobs[target] = {} end
    if is_threnody_spell(spell_id) then
        for eff, entry in pairs(debuffed_mobs[target]) do
            if type(entry) == 'table' and entry.name and entry.name:find('Threnody') then remove_debuff(target, eff) end
        end
    end
    local overwrites = (res.spells[spell_id] and res.spells[spell_id].overwrites) or {}
    if not handle_overwrites(target, spell_id, overwrites) then return end
    local name = (others and others.blue_magic and others.blue_magic[spell_id] and others.blue_magic[spell_id].en)
              or (res.spells[spell_id] and res.spells[spell_id].en) or 'Unknown'
    debuffed_mobs[target][effect] = { id = spell_id, name = name, timer = os.clock() + (duration or 0), base_dur = tonumber(duration or 0) or 0, expired_at = nil }
    if debuffs_map[spell_id] and type(debuffs_map[spell_id].effect) == 'table' then
        debuffed_mobs[target][effect].name = name..' ('..res.buffs[effect].en..')'
    end
end

local function apply_ja_spells(target, spell_id)
    if not debuffed_mobs[target] then debuffed_mobs[target] = {} end
    local current = debuffed_mobs[target][1000]
    local tier = (current and current.name == spell_id) and math.min((current.tier or 1) + 1, 5) or 1
    local timer = (current and current.name == spell_id) and current.timer or (os.clock() + 60)
    debuffed_mobs[target][1000] = { id = spell_id, name = spell_id, tier = tier, timer = timer, base_dur = 60, expired_at = nil }
end

local function get_pet_owner(id)
    local pet = windower.ffxi.get_mob_by_id(id); if not pet then return id end
    for _,v in pairs(windower.ffxi.get_party()) do
        if type(v)=='table' and v.mob and v.mob.pet_index then
            local p=windower.ffxi.get_mob_by_index(v.mob.pet_index)
            if p and p.id==id then return v.mob.id end
        end
    end
    return id
end

local function is_ally(id)
    if not id then return false end
    local p = windower.ffxi.get_party()
    for _,slot in pairs(p) do
        if type(slot)=='table' and slot.mob then
            if slot.mob.id == id then return true end
            if slot.mob.pet_index then
                local pet = windower.ffxi.get_mob_by_index(slot.mob.pet_index)
                if pet and pet.id == id then return true end
            end
        end
    end
    return false
end

local function handle_shot(target, shot)
    if not debuffed_mobs[target] then return true end
    local function tag(label, rgb) return settings.colors_enabled and (' ('..cs(rgb, label)..')') or (' ('..label..')') end
    local function mult2(rgb) return settings.colors_enabled and cs(rgb, 'x2') or 'x2' end
    if shot == 125 and debuffed_mobs[target][128] then
        local s = debuffed_mobs[target][128]; s.shot = (s.shot or 0) + 1; s.name = s.name .. (s.shot==1 and tag('Fire Shot',C.fire) or mult2(C.fire))
    elseif shot == 126 then
        if debuffed_mobs[target][4] and T{58,80}:contains(debuffed_mobs[target][4].id) and not debuffed_mobs[target][4].shot then
            local s = debuffed_mobs[target][4]; s.shot = 1; s.name = s.name .. tag('Ice Shot', C.ice)
        end
        if debuffed_mobs[target][129] then
            local s = debuffed_mobs[target][129]; s.shot = (s.shot or 0) + 1; s.name = s.name .. (s.shot==1 and tag('Ice Shot',C.ice) or mult2(C.ice))
        end
    elseif shot == 127 and debuffed_mobs[target][130] then
        local s = debuffed_mobs[target][130]; s.shot = (s.shot or 0) + 1; s.name = s.name .. (s.shot==1 and tag('Wind Shot',C.wind) or mult2(C.wind))
    elseif shot == 128 then
        if debuffed_mobs[target][13] and T{56,344,345}:contains(debuffed_mobs[target][13].id) and not debuffed_mobs[target][13].shot then
            local s = debuffed_mobs[target][13]; s.shot = 1; s.name = s.name .. tag('Earth Shot', C.earth)
        end
        if debuffed_mobs[target][131] then
            local s = debuffed_mobs[target][131]; s.shot = (s.shot or 0) + 1; s.name = s.name .. (s.shot==1 and tag('Earth Shot',C.earth) or mult2(C.earth))
        end
    elseif shot == 129 and debuffed_mobs[target][132] then
        local s = debuffed_mobs[target][132]; s.shot = (s.shot or 0) + 1; s.name = s.name .. (s.shot==1 and tag('Thunder Shot',C.lightning) or mult2(C.lightning))
    elseif shot == 130 then
        if debuffed_mobs[target][3] and T{220,221}:contains(debuffed_mobs[target][3].id) and not debuffed_mobs[target][3].shot then
            local s = debuffed_mobs[target][3]; s.shot = 1; s.name = s.name .. tag('Water Shot', C.water)
        end
        if debuffed_mobs[target][133] then
            local s = debuffed_mobs[target][133]; s.shot = (s.shot or 0) + 1; s.name = s.name .. (s.shot==1 and tag('Water Shot',C.water) or mult2(C.water))
        end
    elseif shot == 131 and debuffed_mobs[target][134] and not debuffed_mobs[target][134].shot then
        local s = debuffed_mobs[target][134]; s.shot = 1; s.name = s.name .. tag('Light Shot', C.light)
    elseif shot == 132 then
        if debuffed_mobs[target][5] and T{254,276,347,348}:contains(debuffed_mobs[target][5].id) and not debuffed_mobs[target][5].shot then
            local s = debuffed_mobs[target][5]; s.shot = 1; s.name = s.name .. tag('Dark Shot', C.dark)
        end
        if debuffed_mobs[target][135] and not debuffed_mobs[target][135].shot then
            local s = debuffed_mobs[target][135]; s.shot = 1; s.name = s.name .. tag('Dark Shot', C.dark)
        end
    end
end

local function inc_action(act)
    if act.category == 4 then
        if act.param == 260 and act.targets[1].actions[1].message == 342 then
            local effect = act.targets[1].actions[1].param
            local target = act.targets[1].id
            if is_enemy(target) then remove_debuff(target, effect) end
        end
        if not is_ally(act.actor_id) then return end

        local SUCCESS_GENERIC = S{2,230,252,264,265}
        local SUCCESS_STATUS  = S{236,237,266,267,268,269,270,271,272,277,278,279,280}
        local FAIL_OR_IGNORE  = S{75,85,284,653,655,677,678,423}

        for i = 1, #act.targets do
            local tmsg  = act.targets[i].actions[1].message
            local tgt   = act.targets[i].id
            local spell = act.param
            local actor = tostring(act.actor_id)

            if is_enemy(tgt) then
                if T{2,252,264,265}:contains(tmsg) and JA_SPELLS:contains(act.param) then
                    apply_ja_spells(tgt, act.param)
                else
                    if T{33,34,35,36,37}:contains(spell) then spell = spell - 10 end
                    local bm = others and others.blue_magic and others.blue_magic[spell]
                    local effect   = bm and bm.status or (res.spells[spell] and res.spells[spell].status) or nil
                    local duration = (durations[owner_key] and durations[owner_key].spells and durations[owner_key].spells[tostring(spell)])
                                  or (durations[owner_key] and durations[owner_key][actor] and durations[owner_key][actor][tostring(spell)])
                                  or (EXTREMES[spell] and EXTREMES[spell].duration)
                                  or (bm and bm.duration)
                                  or (res.spells[spell] and res.spells[spell].duration)
                                  or (debuffs_map[spell] and debuffs_map[spell].duration)
                                  or (absorb_map[spell] and absorb_map[spell].duration)
                                  or 0

                    if SUCCESS_STATUS:contains(tmsg) then
                        local msg_effect = act.targets[i].actions[1].param
                        if T{225,226,227,228,229}:contains(spell) then spell = spell - 5 end
                        local conflict = (spell == 719 and debuffed_mobs[tgt] and debuffed_mobs[tgt][133])
                                      or (spell == 535 and debuffed_mobs[tgt] and debuffed_mobs[tgt][128])
                                      or (spell == 705 and debuffed_mobs[tgt] and debuffed_mobs[tgt][132])
                        if not conflict then
                            local s_status = bm and bm.status or (res.spells[spell] and res.spells[spell].status)
                            if s_status and s_status == msg_effect then
                                apply_debuff(tgt, msg_effect, act.param, duration)
                                if is_helix_id(act.param) then helix_store_dmg(tgt, msg_effect, act.targets[i].actions[1].param, act.param) end
                            elseif debuffs_map[spell] and type(debuffs_map[spell].effect) == 'table' then
                                for _, v in pairs(debuffs_map[spell].effect) do apply_debuff(tgt, v, act.param, duration) end
                            elseif debuffs_map[spell] then
                                apply_debuff(tgt, debuffs_map[spell].effect, act.param, duration)
                            elseif EXTREMES[spell] then
                                apply_debuff(tgt, EXTREMES[spell].effect, act.param, duration)
                                if spell == 502 then kaustra_store_dmg(tgt, EXTREMES[spell].effect, act.targets[i].actions[1].param) end
                            elseif absorb_map[spell] then
                                local e = absorb_map[spell].effect
                                if type(e) == 'table' then for _,v in pairs(e) do apply_debuff(tgt, v, spell, duration) end
                                else apply_debuff(tgt, e, spell, duration) end
                            end
                        end
                    elseif SUCCESS_GENERIC:contains(tmsg) then
                        if JA_SPELLS:contains(act.param) then
                            apply_ja_spells(tgt, act.param)
                        else
                            if effect then
                                apply_debuff(tgt, effect, act.param, duration)
                                if is_helix_id(act.param) then helix_store_dmg(tgt, effect, act.targets[i].actions[1].param, act.param) end
                            elseif debuffs_map[spell] then
                                apply_debuff(tgt, debuffs_map[spell].effect, spell, duration)
                            elseif EXTREMES[spell] then
                                apply_debuff(tgt, EXTREMES[spell].effect, act.param, duration)
                                if spell == 502 then kaustra_store_dmg(tgt, EXTREMES[spell].effect, act.targets[i].actions[1].param) end
                            elseif absorb_map[spell] then
                                local e = absorb_map[spell].effect
                                if type(e) == 'table' then for _,v in pairs(e) do apply_debuff(tgt, v, spell, duration) end
                                else apply_debuff(tgt, e, spell, duration) end
                            end
                        end
                    elseif (debuffs_map[spell] or absorb_map[spell] or EXTREMES[spell]) and not FAIL_OR_IGNORE:contains(tmsg) then
                        local map = debuffs_map[spell] and debuffs_map or (absorb_map[spell] and absorb_map or EXTREMES)
                        local e = map[spell].effect
                        if type(e) == 'table' then for _,v in pairs(e) do apply_debuff(tgt, v, spell, duration) end
                        else apply_debuff(tgt, e, spell, duration) end
                        if spell == 502 and EXTREMES[spell] then kaustra_store_dmg(tgt, EXTREMES[spell].effect, act.targets[i].actions[1].param) end
                    end
                end
            end
        end

    elseif act.category == 6 then
        if not is_ally(act.actor_id) then return end
        if T{125,126,127,128,129,130,131,132}:contains(act.param) and act.targets[1].actions[1].message ~= 323 then
            local tgt = act.targets[1].id; if is_enemy(tgt) then handle_shot(tgt, act.param) end
        end

    elseif act.category == 13 then
        local owner = get_pet_owner(act.actor_id); if not is_ally(owner) then return end
        if T{611,657,963}:contains(act.param) then
            for i = 1, #act.targets do
                if T{320,267}:contains(act.targets[i].actions[1].message) then
                    local target = act.targets[i].id
                    if is_enemy(target) then
                        local spell = act.param
                        local effect = (BloodPact_map[spell] and BloodPact_map[spell].effect) or act.targets[i].actions[1].param
                        local duration = (durations[owner_key] and durations[owner_key].spells and durations[owner_key].spells[tostring(spell)])
                                      or (durations[owner_key] and durations[owner_key][owner] and durations[owner_key][owner][tostring(spell)])
                                      or (BloodPact_map[spell] and BloodPact_map[spell].duration)
                                      or 0
                        debuffed_mobs[target] = debuffed_mobs[target] or {}
                        debuffed_mobs[target][effect] = { name = res.job_abilities[spell].en..' ('..res.buffs[effect].en..')', timer = os.clock() + duration, base_dur = duration, expired_at = nil }
                    end
                end
            end
        end

    elseif act.category == 14 then
        if not is_ally(act.actor_id) then return end
        for i = 1, #act.targets do
            if T{519,520,521,591}:contains(act.targets[i].actions[1].message) then
                local target = act.targets[i].id
                if is_enemy(target) then
                    local effect = act.param; local tier = act.targets[i].actions[1].param
                    step_duration[target] = step_duration[target] or {}
                    if tier == 1 or not step_duration[target][effect] then
                        step_duration[target][effect] = os.clock() + 60
                    elseif step_duration[target][effect] - os.clock() >= 90 then
                        step_duration[target][effect] = os.clock() + 120
                    else
                        step_duration[target][effect] = os.clock() + math.max(30, step_duration[target][effect] - os.clock() + 30)
                    end
                    debuffed_mobs[target] = debuffed_mobs[target] or {}
                    debuffed_mobs[target][effect] = { name = res.job_abilities[effect].en.." lv."..tier, timer = step_duration[target][effect], base_dur = 0, expired_at = nil }
                end
            end
        end

    elseif act.category == 15 then
        if not is_ally(act.actor_id) then return end
        if T{372,375}:contains(act.param) and T{320,672}:contains(act.targets[1].actions[1].message) then
            local target = act.targets[1].id; if not is_enemy(target) then return end
            local effect = act.targets[1].actions[1].param; local spell = act.param; local actor = tostring(act.actor_id)
            local duration = (durations[owner_key] and durations[owner_key].spells and durations[owner_key].spells[tostring(spell)])
                          or (durations[owner_key] and durations[owner_key][actor] and durations[owner_key][actor][tostring(spell)])
                          or (EXTREMES[spell] and EXTREMES[spell].duration)
                          or (res.spells[spell] and res.spells[spell].duration)
                          or (debuffs_map[spell] and debuffs_map[spell].duration)
                          or 0
            debuffed_mobs[target] = debuffed_mobs[target] or {}
            debuffed_mobs[target][effect] = { name = res.job_abilities[spell].en, timer = os.clock()+duration, base_dur = duration, expired_at = nil }
        end

    elseif T{1,7,8,11}:contains(act.category) then
        if debuffed_mobs[act.actor_id] then
            if     debuffed_mobs[act.actor_id][2]   then remove_debuff(act.actor_id, 2)
            elseif debuffed_mobs[act.actor_id][7]   then remove_debuff(act.actor_id, 7)
            elseif debuffed_mobs[act.actor_id][28]  then remove_debuff(act.actor_id, 28)
            elseif debuffed_mobs[act.actor_id][193] then remove_debuff(act.actor_id, 193) end
        end
        if act.category == 11 then
            for i = 1, #act.targets do
                local msg = act.targets[i].actions[1].message
                if T{101}:contains(msg) then
                    if ERASE_ABILITIES:contains(act.param) then clear_target_debuffs(act.targets[1].id) end
                elseif T{159}:contains(msg) then
                    if PARTIAL_ERASE_ABILITIES:contains(act.param) then remove_debuff(act.targets[1].id, act.targets[1].actions[1].param) end
                end
            end
        elseif act.category == 1 and act.targets[1].actions[1].has_add_effect and act.targets[1].actions[1].add_effect_message == 603 then
            TH[act.targets[1].id] = 'TH: '..act.targets[1].actions[1].add_effect_param
        end

    elseif act.category == 3 and act.targets[1].actions[1].message == 608 then
        TH[act.targets[1].id] = 'TH: '..act.targets[1].actions[1].param

    elseif act.category == 3 and act.targets[1].actions[1].message == 100 then
        local effect = act.targets[1].actions[1].param
        local spell  = act.param
        if S{150,170}:contains(spell) and effect == 149 then
            local name = (res.job_abilities[spell] and res.job_abilities[spell].en) or 'Unknown'
            local actor = act.actor_id; local target = act.targets[1].id; local merit_name = name:lower()
            local override = (durations[owner_key] and durations[owner_key].spells and durations[owner_key].spells[tostring(spell)])
                          or (durations[owner_key] and durations[owner_key][tostring(actor)] and durations[owner_key][tostring(spell)])
            local base  = (ja_map[spell] and ja_map[spell].duration) or 0
            local merit = (player and actor == player.id) and (30 + ((player.merits[merit_name] or 0)-1)*15) or nil
            local duration = override or merit or base
            debuffed_mobs[target] = debuffed_mobs[target] or {}
            debuffed_mobs[target][effect] = { name = name, timer = os.clock()+duration, base_dur = duration, expired_at = nil }
        end
    end
end

local function inc_action_message(arr)
    if T{6,20,113,406,605,646}:contains(arr.message_id) then
        if is_enemy(arr.target_id) then
            clear_target_debuffs(arr.target_id, { no_hint = true })
            TH[arr.target_id] = nil
        end
    elseif T{204,206}:contains(arr.message_id) then
        if is_enemy(arr.target_id) and debuffed_mobs[arr.target_id] then
            local pid = arr.param_1
            if arr.message_id == 206 then
                if     pid == 136 then remove_debuff(arr.target_id,136); remove_debuff(arr.target_id,266); if step_duration[arr.target_id] then step_duration[arr.target_id][266]=0 end
                elseif pid == 137 then remove_debuff(arr.target_id,137); remove_debuff(arr.target_id,267); if step_duration[arr.target_id] then step_duration[arr.target_id][267]=0 end
                elseif pid == 138 then remove_debuff(arr.target_id,138); remove_debuff(arr.target_id,268); if step_duration[arr.target_id] then step_duration[arr.target_id][268]=0 end
                elseif pid == 139 then remove_debuff(arr.target_id,139); remove_debuff(arr.target_id,269); if step_duration[arr.target_id] then step_duration[arr.target_id][269]=0 end
                elseif pid == 140 then remove_debuff(arr.target_id,140); remove_debuff(arr.target_id,270); if step_duration[arr.target_id] then step_duration[arr.target_id][270]=0 end
                elseif pid == 141 then remove_debuff(arr.target_id,141); remove_debuff(arr.target_id,271); if step_duration[arr.target_id] then step_duration[arr.target_id][271]=0 end
                elseif pid == 142 then remove_debuff(arr.target_id,142); remove_debuff(arr.target_id,272); if step_duration[arr.target_id] then step_duration[arr.target_id][272]=0 end
                elseif pid == 146 then remove_debuff(arr.target_id,146); remove_debuff(arr.target_id,242); if step_duration[arr.target_id] then step_duration[arr.target_id][242]=0 end
                elseif T{386,387,388,389,390}:contains(pid) then remove_debuff(arr.target_id,201); if step_duration[arr.target_id] then step_duration[arr.target_id][201]=0 end
                elseif T{391,392,393,394,395}:contains(pid) then remove_debuff(arr.target_id,202); if step_duration[arr.target_id] then step_duration[arr.target_id][202]=0 end
                elseif T{396,397,398,399,400}:contains(pid) then remove_debuff(arr.target_id,203); if step_duration[arr.target_id] then step_duration[arr.target_id][203]=0 end
                elseif T{448,449,450,451,452}:contains(pid) then remove_debuff(arr.target_id,312); if step_duration[arr.target_id] then step_duration[arr.target_id][312]=0 end
                else remove_debuff(arr.target_id, pid) end
            else
                remove_debuff(arr.target_id, pid)
            end
        end
    end
end

windower.register_event('logout','zone change', function()
    debuffed_mobs = {}
    TH = {}
    player = windower.ffxi.get_player()
end)

windower.register_event('incoming chunk', function(id, data)
    if id == 0x028 then
        inc_action(windower.packets.parse_action(data))
    elseif id == 0x029 then
        local arr = { target_id = data:unpack('I',0x09), param_1 = data:unpack('I',0x0D), message_id = data:unpack('H',0x19) % 32768 }
        inc_action_message(arr)
    elseif id == 0x00E then
        local packet = packets.parse('incoming', data)
        if TH[packet['NPC']] and packet['Status'] == 0 and packet['HP %'] == 100 then TH[packet['NPC']] = nil end
    end
end)

windower.register_event('prerender', function()
    local curr = os.clock()
    if curr > frame_time + 0.1 then frame_time = curr; update_box() end
end)

windower.register_event('load','login', function()
    if not windower.dir_exists(windower.addon_path..'data\\') then windower.create_dir(windower.addon_path..'data\\') end
    local durationsFile = file.new('data\\durations.xml', true)
    if not file.exists('data\\durations.xml') then durationsFile:write(default_durations_xml) end
    durations = config.load('data\\durations.xml')

    local profilesFile = file.new('data\\duration_profiles.xml', true)
    if not file.exists('data\\duration_profiles.xml') then profilesFile:write(default_profiles_xml) end
    duration_profiles = config.load('data\\duration_profiles.xml')

    local info = windower.ffxi.get_info(); if not info.logged_in then return end
    player = windower.ffxi.get_player()
    owner_key = (player and player.name and player.name:lower()) or 'unknown'

    durations[owner_key] = durations[owner_key] or {}
    if durations[owner_key].global and not durations[owner_key].spells then
        durations[owner_key].spells = durations[owner_key].global; durations[owner_key].global = nil; config.save(durations, 'all')
    end
    durations[owner_key].spells = durations[owner_key].spells or {}

    duration_profiles[owner_key] = duration_profiles[owner_key] or {}
    duration_profiles[owner_key].profiles = duration_profiles[owner_key].profiles or {}

    -- normalize profiles to lowercase keys, preserve display label, migrate global->spells
    do
        local store = duration_profiles[owner_key].profiles or {}
        local new_store = {}
        for k, v in pairs(store) do
            local nk = _norm_key(k)
            local entry = type(v) == 'table' and v or {}
            entry.spells = entry.spells or entry.global or {}
            entry.global = nil
            entry.label = entry.label or k
            if not new_store[nk] then
                new_store[nk] = entry
            else
                for sid,secs in pairs(entry.spells or {}) do new_store[nk].spells[sid] = secs end
                if not new_store[nk].label then new_store[nk].label = entry.label end
            end
        end
        duration_profiles[owner_key].profiles = new_store
        config.save(duration_profiles, 'all')
    end

    if settings.auto_profiles_enabled then _apply_job_profile() end
end)

windower.register_event('job change', function()
    if settings.auto_profiles_enabled then _apply_job_profile() end
end)

windower.register_event('addon command', function(...)
    local commands = T{...}
    player = windower.ffxi.get_player()
    if not player then return end

    local function _trim(s) return (s or ''):match('^%s*(.-)%s*$') end
    local function _auto(s) return (s and s ~= '' and windower and windower.convert_auto_trans) and windower.convert_auto_trans(s) or s end
    local function _unwrap_token(s)
        s = _trim(s or ''); if s == '' then return s end
        local first,last = s:sub(1,1), s:sub(-1); local pairs = {['\"']='\"', ['{']='}', ['[']=']', ['<']='>'}
        if pairs[first] and last == pairs[first] then return s:sub(2, -2) end
        return s
    end
    local function _norm(s) return (_auto(_unwrap_token(s or '')):lower():gsub('[%s%p]+','')) end

    local function set_toggle(key, val)
        if val == nil then settings[key] = not settings[key]
        else
            local v = tostring(val or ''):lower()
            if v == 'on' or v == 'true' or v == '1' then settings[key] = true
            elseif v == 'off' or v == 'false' or v == '0' then settings[key] = false
            else settings[key] = not settings[key] end
        end
        config.save(settings); log(key..' is now: '..tostring(settings[key]))
    end

    local function normalize_name(n) n=tostring(n or ''):gsub('^%s+',''):gsub('%s+$',''); return n~='' and n or nil end

    local function resolve_spell_id(raw)
        local q=_auto(_unwrap_token(raw)); local qn=_norm(q); local n=tonumber(q)
        if n and (res.spells[n] or (others and others.blue_magic and others.blue_magic[n])) then
            local name=(res.spells[n] and res.spells[n].en) or others.blue_magic[n].en; return n,name
        end
        local function score(name)
            if not name then return -1 end
            local a=_auto(name); local an=_norm(a)
            if a:lower()==q:lower() then return 4000
            elseif an==qn then return 3000
            elseif a:lower():find(q:lower(),1,true) then return 1500
            elseif an:find(qn,1,true) then return 1400
            else return -1 end
        end
        local best,bid,bname=-1,nil,nil
        for _,v in pairs(res.spells) do local sc=score(v and v.en); if sc>best then best,bid,bname=sc,v.id,v.en end end
        if others and others.blue_magic then
            for _,v in pairs(others.blue_magic) do local sc=score(v and v.en); if sc>best then best,bid,bname=sc,v.id,v.en end end
        end
        return bid,bname
    end

    if not commands or not commands[1] then
        log('Invalid command:')
        log('//df|debuffing colors|timer [on|off]')
        log('//df|debuffing auto [on|off]')
        log('//df|debuffing auto_profiles [on|off]')
        log('//df|debuffing keep_buff [on|off]')
        log('//df|debuffing {Spell Name}|ID [seconds|remove]')
        log('//df save <name> | //df load <name> | //df list | //df delete <name>')
        log('//df reset | //df test clear | //df clear')
        return
    end

    local cmd = tostring(commands[1]):lower()

    if cmd == 'keep_buff' then
        local v = tostring(commands[2] or ''):lower()
        if v == 'on' or v == 'true' or v == '1' then settings.keep_buff_after_timer = true
        elseif v == 'off' or v == 'false' or v == '0' then settings.keep_buff_after_timer = false
        else settings.keep_buff_after_timer = not settings.keep_buff_after_timer end
        config.save(settings); log('Keep buff after timer is now: '..tostring(settings.keep_buff_after_timer))

    elseif cmd == 'auto' then
        local v = tostring(commands[2] or ''):lower()
        local new_auto = (v=='on' or v=='true' or v=='1') and true or (v=='off' or v=='false' or v=='0') and false or not settings.auto_update_enabled
        settings.auto_update_enabled = new_auto
        settings.keep_buff_after_timer = new_auto
        config.save(settings)
        log('Auto update is now: '..tostring(settings.auto_update_enabled))
        log('Keep buff after timer is now: '..tostring(settings.keep_buff_after_timer))

    elseif cmd == 'auto_profiles' then
        local before = settings.auto_profiles_enabled
        set_toggle('auto_profiles_enabled', commands[2])
        if settings.auto_profiles_enabled and not before then _apply_job_profile() end

    elseif cmd == 'colors' then
        set_toggle('colors_enabled', commands[2])

    elseif cmd == 'timer' then
        set_toggle('timers_enabled', commands[2])

    elseif cmd == 'reset' then
        durations[owner_key] = durations[owner_key] or {}; durations[owner_key].spells = {}; config.save(durations, 'all')
        log('All durations reverted to default.')

    elseif cmd == 'save' then
        local name = normalize_name(table.concat(commands, ' ', 2)); if not name then return log('Usage: //df save <name>') end
        _ensure_profile_tables()
        local store = duration_profiles[owner_key].profiles
        local key = _resolve_profile_key(name)
        store[key] = { label = name, spells = _deepcopy(durations[owner_key].spells or {}) }
        config.save(duration_profiles, 'all')
        local cnt = 0 for _ in pairs(store[key].spells or {}) do cnt = cnt + 1 end
        log(('Saved %s profile with %d entries.'):format(store[key].label or key, cnt))

    elseif cmd == 'load' then
        local name = normalize_name(table.concat(commands, ' ', 2)); if not name then return log('Usage: //df load <name>') end
        _ensure_profile_tables()
        local store = duration_profiles[owner_key].profiles
        local key = _resolve_profile_key(name)
        if not store[key] then return log('Profile "'..name..'" not found.') end
        durations[owner_key].spells = _deepcopy(store[key].spells or {}); config.save(durations, 'all')
        log('Loaded '..(store[key].label or key)..' profile.')

    elseif cmd == 'list' then
        _ensure_profile_tables()
        local store = duration_profiles[owner_key].profiles
        local count = 0
        for k, pdata in pairs(store) do
            local n = 0 for _ in pairs((pdata and pdata.spells) or {}) do n = n + 1 end
            log(('%s (%d)'):format((pdata and pdata.label) or k, n)); count = count + 1
        end
        if count == 0 then log('No profiles saved') end

    elseif cmd == 'delete' then
        local name = normalize_name(table.concat(commands, ' ', 2)); if not name then return log('Usage: //df delete <name>') end
        _ensure_profile_tables()
        local store = duration_profiles[owner_key].profiles
        local key = _resolve_profile_key(name)
        if not store[key] then return log('Profile '..name..' not found') end
        local label = store[key].label or key
        store[key] = nil; config.save(duration_profiles, 'all'); log('Deleted '..label..' profile.')

    elseif cmd == 'test' then
        if tostring(commands[2] or ''):lower() == 'clear' then
            local self_id = player.id; simulation_mode = false; clear_target_debuffs(self_id, { no_hint = true }); log('Test debuffs cleared'); return
        end

        if #commands < 2 then log('Invalid command: //df test [spell name|id] [damage|remove]'); return end
        local last_is_remove = (commands[#commands] and tostring(commands[#commands]):lower() == 'remove')
        local name_end = last_is_remove and (#commands - 1) or #commands

        local nums, name_parts = {}, {}
        for i = 2, name_end do
            local tok = _auto(_unwrap_token(tostring(commands[i] or '')))
            local n = tonumber(tok); if n then nums[#nums+1] = n else name_parts[#name_parts+1] = tok end
        end
        local dmg_val = (#name_parts > 0 and nums[1]) or nil
        local raw_query = (#name_parts > 0) and table.concat(name_parts, ' ') or table.concat(commands, ' ', 2, name_end)

        local sid, sname
        local idq = tonumber(_auto(_unwrap_token(raw_query)))
        if idq and res.spells[idq] then sid,sname = idq, res.spells[idq].en
        elseif idq and others and others.blue_magic and others.blue_magic[idq] then sid,sname = idq, others.blue_magic[idq].en
        else sid,sname = resolve_spell_id(raw_query) end
        if not sid then log('Spell not found: incorrect spell name/id.'); return end

        local self_id = player.id; simulation_mode = true; debuffed_mobs[self_id] = debuffed_mobs[self_id] or {}

        if last_is_remove then
            for eff, ent in pairs(debuffed_mobs[self_id]) do
                if type(ent) == 'table' and (ent.id == sid or ent.name == sname) then remove_debuff(self_id, eff, { no_hint = true }) end
            end
            log('Removed test debuff: '..sname); return
        end

        local bm = others and others.blue_magic and others.blue_magic[sid]
        local duration = (durations[owner_key] and durations[owner_key].spells and durations[owner_key].spells[tostring(sid)])
                       or (EXTREMES[sid] and EXTREMES[sid].duration)
                       or (bm and bm.duration) or (res.spells[sid] and res.spells[sid].duration)
                       or (debuffs_map[sid] and debuffs_map[sid].duration) or (absorb_map[sid] and absorb_map[sid].duration)
                       or 60

        local s = res.spells[sid]
        local function apply_map_effects_local(map, tgt, spell, dur)
            local e = map[spell].effect
            local function mark_no_hint(t, eff) if t and t[eff] and type(t[eff])=='table' then t[eff].no_hint = true end end
            if type(e) == 'table' then for _, v in pairs(e) do apply_debuff(tgt, v, spell, dur); mark_no_hint(debuffed_mobs[tgt], v) end
            else
                apply_debuff(tgt, e, spell, dur); mark_no_hint(debuffed_mobs[tgt], e)
                if map == EXTREMES and spell == 502 and dmg_val then kaustra_store_dmg(tgt, e, dmg_val) end
            end
        end

        if (bm and bm.status) or (s and s.status) then
            local status_id = (bm and bm.status) or s.status
            apply_debuff(self_id, status_id, sid, duration)
            for eff, ent in pairs(debuffed_mobs[self_id]) do if type(ent) == 'table' and ent.id == sid then ent.no_hint = true end end
            if dmg_val then
                if is_helix_id(sid) then helix_store_dmg(self_id, status_id, dmg_val, sid)
                elseif sid == 502 then kaustra_store_dmg(self_id, status_id, dmg_val) end
            end
        elseif debuffs_map[sid] then
            apply_map_effects_local(debuffs_map, self_id, sid, duration)
        elseif EXTREMES[sid] then
            apply_map_effects_local(EXTREMES, self_id, sid, duration)
        elseif absorb_map[sid] then
            apply_map_effects_local(absorb_map, self_id, sid, duration)
        else
            local name = (bm and bm.en) or (s and s.en) or ('ID '..tostring(sid))
            debuffed_mobs[self_id][sid] = { id = sid, name = name, timer = os.clock()+duration, base_dur = duration, expired_at = nil, no_hint = true }
        end

    elseif cmd == 'clear' then
        local ids = {}; for tid,_ in pairs(debuffed_mobs) do ids[#ids+1] = tid end
        for _,tid in ipairs(ids) do clear_target_debuffs(tid, { no_hint = true }) end
        simulation_mode = false; log('All debuffs cleared')

    else
        if #commands <= 1 then log('Invalid command: //df {Spell Name}|ID [seconds|remove]'); return end
        durations[owner_key] = durations[owner_key] or {}; durations[owner_key].spells = durations[owner_key].spells or {}
        local raw_query = table.concat(commands, ' ', 1, #commands - 1)
        local sid, sname = resolve_spell_id(raw_query); if not sid then log('Spell not found: incorrect spell name/id or outdated resources'); return end
        local last = tostring(commands[#commands] or ''):lower(); local secs = tonumber(last)
        if secs and secs >= 0 then
            durations[owner_key].spells[tostring(sid)] = secs; config.save(durations, 'all')
            _sync_profile(sid, secs)
            log('Global duration for '..sname..' set to '..secs..' seconds')
        elseif last == 'remove' then
            durations[owner_key].spells[tostring(sid)] = nil; config.save(durations, 'all')
            _sync_profile(sid, nil)
            log('Global duration for '..sname..' removed')
        else
            log('Invalid time. Use a non-negative number or "remove".')
        end
    end
end)
