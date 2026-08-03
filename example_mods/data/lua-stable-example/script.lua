-- Script básico no mesmo local usado pela Psych: mods/data/<song>/script.lua
function onCreatePost()
    makeLuaText('luaStatus', 'Psych Lua OK: ' .. buildTarget, 600, 20, 20)
    setTextSize('luaStatus', 20)
    setTextColor('luaStatus', '00FF88')
    setObjectCamera('luaStatus', 'camHUD')
    addLuaText('luaStatus')
end

function onBeatHit()
    if curBeat % 2 == 0 then
        doTweenAlpha('luaStatusPulse', 'luaStatus', 0.45, 0.12, 'quadOut')
    else
        doTweenAlpha('luaStatusPulse', 'luaStatus', 1, 0.12, 'quadOut')
    end
end

function goodNoteHit(id, direction, noteType, isSustainNote)
    if not isSustainNote then
        setTextString('luaStatus', 'Acerto: ' .. direction .. ' | ' .. noteType)
    end
end
