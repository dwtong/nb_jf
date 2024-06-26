local mod = require 'core/mods'
local voice = require 'lib/voice'

local JF_I2C_FREQ = 0.02

if note_players == nil then
    note_players = {}
end

local function add_kit_player()
    local player = {
        counts = {0, 0, 0, 0, 0, 0}
    }

    function player:note_on(note, vel)
        local n = (note - 1)%6 + 1
        self.counts[n] = self.counts[n] + 1
        crow.ii.jf.vtrigger(n, 8*vel)
    end

    function player:note_off(note)
        local n = (note - 1)%6 + 1
        self.counts[n] = self.counts[n] - 1
        if self.counts[n] < 0 then self.counts[n] = 0 end
        if self.counts[n] <= 0 then
            crow.ii.jf.trigger((note - 1)%6 + 1, 0)
        end
    end

    function player:modulate(val)
        crow.ii.jf.transpose(-2*val)
    end

    function player:describe()
        return {
            name = "jf kit",

            supports_bend = false,
            supports_slew = false,
            modulate_description = "time",
            style = "kit",
        }
    end

    function player:stop_all()
        crow.ii.jf.trigger(0, 0)
    end

    function player:delayed_active()
        crow.ii.jf.mode(0)
    end

    note_players["jf kit"] = player
end

local function add_mono_player(idx)
    local player = {
        count = 0,
        bend = 0,
        note = nil
    }

    function player:add_params()
        params:add_group("nb_jf_n_"..idx, "jf n "..idx, 1)
        params:add_control("nb_jf_slew_"..idx, "slew", controlspec.new(0, 1, 'lin', 0, 0, 's', 0.001))
        params:hide("nb_jf_n_"..idx)
    end

    function player:note_on(note, vel)
        self.note = note
        self.count = self.count + 1
        self.old_v8 = player.cur_v8
        self.v8 = (note - 60) / 12
        local v_vel = vel * 5
        local slew = params:get("nb_jf_slew_"..idx)
        if slew == 0 or self.old_v8 == nil or self.old_v8 == self.v8 then
            crow.ii.jf.play_voice(idx, player.v8, v_vel)
            self.cur_v8 = player.v8
        else
            if player.routine ~= nil then
                clock.cancel(player.routine)
            end
            crow.ii.jf.vtrigger(idx, v_vel)
            player.routine = clock.run(function()
                local elapsed = 0
                while elapsed < slew do
                    elapsed = elapsed + JF_I2C_FREQ
                    if elapsed > slew then
                        elapsed = slew
                    end
                    self.cur_v8 = (elapsed/slew)*player.v8 + (1 - elapsed/slew)*player.old_v8
                    crow.ii.jf.pitch(idx, self.cur_v8 + self.bend/12)
                    clock.sleep(JF_I2C_FREQ)
                end
            end)
        end
    end

    function player:set_slew(s)
        params:set("nb_jf_slew_"..idx, s)
    end

    function player:pitch_bend(note, val)
        if note ~= self.note then return end
        self.bend = val
        crow.ii.jf.pitch(idx, self.cur_v8 + self.bend / 12)
    end

    function player:note_off(note)
        self.count = self.count - 1
        if self.count < 0 then self.count = 0 end
        if self.count == 0 then
            crow.ii.jf.trigger(idx, 0)
        end
    end

    function player:describe(note)
        return {
            name = "jf n "..idx,
            supports_bend = true,
            supports_slew = true,
            modulate_description = "unsupported",
        }
    end

    function player:stop_all()
        crow.ii.jf.trigger(0, 0)
    end

    function player:delayed_active()
        crow.ii.jf.mode(1)
        params:show("nb_jf_n_"..idx)
        _menu.rebuild_params()
    end

    function player:inactive()
        self.is_active = false
        if self.active_routine ~= nil then
            clock.cancel(self.active_routine)
        end
        params:hide("nb_jf_n_"..idx)
        _menu.rebuild_params()
    end

    note_players["jf n "..idx] = player
end

local function add_unison_player()
    local player = {
        count = 0
    }

    function player:add_params()
        params:add_group("nb_jf_unison", "jf unison", 1)
        params:add_control("nb_jf_unison_detune", "detune", controlspec.new(0, 100, 'lin', 0, 0, 'c', 0.01))
        params:hide("nb_jf_unison")
    end

    function player:note_on(note, vel)
        self.count = self.count + 1
        self.v8 = (note - 60) / 12
        local v_vel = vel * 5
        local detune = params:get("nb_jf_unison_detune")
        for i=1,6 do
            crow.ii.jf.play_voice(i, self.v8 + (detune/1200)*(math.random() - 0.5) , v_vel/2)
        end
    end

    function player:note_off(note)
        self.count = self.count - 1
        if self.count < 0 then self.count = 0 end
        if self.count == 0 then
            crow.ii.jf.trigger(0, 0)
        end
    end

    function player:describe(note)
        return {
            name = "jf unison",
            supports_bend = false,
            supports_slew = false,
            modulate_description = "unsupported",
        }
    end

    function player:stop_all()
        crow.ii.jf.trigger(0, 0)
    end

    function player:delayed_active()
        crow.ii.jf.mode(1)
        params:show("nb_jf_unison")
        _menu.rebuild_params()
    end

    function player:inactive()
        self.is_active = false
        if self.active_routine ~= nil then
            clock.cancel(self.active_routine)
        end
        params:hide("nb_jf_unison")
        _menu.rebuild_params()
    end

    note_players["jf unison"] = player
end

local function add_poly_player()
    local player = {
        voice_count = 6,
        last_voice = 1,
        release_fn = {},
        alloc_modes = { "jf", "rotate", "random" },
        trigger_modes = { "gate", "trigger" },
    }

    function player:add_params()
        params:add_group("nb_jf_poly", "jf poly", 3)
        params:add_option("nb_jf_poly_trigger_mode", "trigger mode", self.trigger_modes, 1)
        params:add_option("nb_jf_poly_alloc_mode", "alloc mode", self.alloc_modes, 1)
        params:set_action("nb_jf_poly_alloc_mode", function(value)
            if self.alloc_modes[value] ~= "jf" then
                params:set("nb_jf_poly_voice_count", self.voice_count)
            end
        end)
        params:add_number("nb_jf_poly_voice_count", "voice count", 1, 6, 6, function(p)
            local alloc_mode = self.alloc_modes[params:get("nb_jf_poly_alloc_mode")]
            return alloc_mode == "jf" and 6 or p.value
        end)
        params:set_action("nb_jf_poly_voice_count", function(value)
            local alloc_mode = self.alloc_modes[params:get("nb_jf_poly_alloc_mode")]
            if alloc_mode ~= "jf" then
                self.voice_count = value
            end
        end)
        params:hide("nb_jf_poly")
    end

    function player:note_on(note, vel)
        local v8 = (note - 60)/12
        local v_vel =  vel^(3/2) * 5
        local alloc_mode = self.alloc_modes[params:get("nb_jf_poly_alloc_mode")]

        if alloc_mode == "jf" then
            self.release_fn[note] = function()
                crow.ii.jf.play_note(v8, 0)
            end
            crow.ii.jf.play_note(v8, v_vel)
        elseif alloc_mode == "rotate" then
            local next_voice = self.last_voice % self.voice_count + 1
            self.last_voice = next_voice
            self.release_fn[note] = function()
                crow.ii.jf.trigger(next_voice, 0)
            end
            crow.ii.jf.play_voice(next_voice, v8, v_vel)
        elseif alloc_mode == "random" then
            local next_voice = math.random(self.voice_count)
            self.release_fn[note] = function()
                crow.ii.jf.trigger(next_voice, 0)
            end
            crow.ii.jf.play_voice(next_voice, v8, v_vel)
        end
    end

    function player:note_off(note)
        local trigger_mode = self.trigger_modes[params:get("nb_jf_poly_trigger_mode")]

        if trigger_mode == "gate" and self.release_fn[note] then
            self.release_fn[note]()
        end
    end

    function player:describe(note)
        return {
            name = "jf poly",
            supports_bend = false,
            supports_slew = false,
            modulate_description = "unsupported",
        }
    end

    function player:stop_all()
        crow.ii.jf.trigger(0, 0)
    end

    function player:delayed_active()
        crow.ii.jf.mode(1)
        params:show("nb_jf_poly")
        _menu.rebuild_params()
    end

    note_players["jf poly"] = player
end

local function add_mpe_player()
    local player = {
        alloc = voice.new(6, voice.MODE_LRU),
        notes = {},
    }

    function player:note_on(note, vel)
        local slot = self.notes[note]
        if slot == nil then
            slot = self.alloc:get()
            slot.count = 1
        end
        slot.on_release = function()
            crow.ii.jf.trigger(slot.id, 0)
        end
        self.notes[note] = slot
        local v8 = (note - 60)/12
        local v_vel = vel^(3/2) * 5
        crow.ii.jf.pitch(slot.id, v8)
        crow.ii.jf.vtrigger(slot.id, v_vel)
    end

    function player:pitch_bend(note, val)
        local v8 = (note - 60 + val)/12
        local slot = self.notes[note]
        if slot ~= nil then
            crow.ii.jf.pitch(slot.id, v8)
        end
    end

    function player:note_off(note)
        local slot = self.notes[note]
        if slot ~= nil then
            self.alloc:release(slot)
        end
        self.notes[note] = nil
    end

    function player:modulate_note(note, key, value)
        if key == "amp" then
            local v_vel = value^(3/2) * 5
            local slot = self.notes[note]
            if slot == nil then return end
            crow.ii.jf.vtrigger(slot.id, v_vel)
        end
    end

    function player:describe(note)
        return {
            name = "jf poly",
            supports_bend = true,
            supports_slew = false,
            note_mod_targets = {"amp"},
            modulate_description = "unsupported",
        }
    end

    function player:stop_all()
        crow.ii.jf.trigger(0, 0)
    end

    function player:delayed_active()
        crow.ii.jf.mode(1)
    end

    note_players["jf mpe"] = player
end

mod.hook.register("script_pre_init", "nb jf pre init", function()
    for n=1,6 do
        add_mono_player(n)
    end
    add_unison_player()
    add_poly_player()
    add_mpe_player()
    add_kit_player()
end)
