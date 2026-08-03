-- Demonstra setProperty, grupos, arrays e triggerEvent.
function onCreatePost()
    setProperty('health', 1.5)
    setProperty('boyfriend.alpha', 0.95)
    setProperty('dad.scale.x', 1.03)
    setProperty('dad.scale.y', 1.03)

    -- Strums/grupos:
    setPropertyFromGroup('playerStrums', 0, 'alpha', 0.8)
end

function onBeatHit()
    if curBeat % 8 == 0 then
        triggerEvent('Camera Set Target', 'dad', '')
    elseif curBeat % 8 == 4 then
        triggerEvent('Camera Set Target', 'bf', '')
    end
end
