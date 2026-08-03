function onCreate()
    for i = 0, getProperty('unspawnNotes.length') - 1 do
        if getPropertyFromGroup('unspawnNotes', i, 'noteType') == 'My Note' then
            setPropertyFromGroup('unspawnNotes', i, 'multAlpha', 0.7)
        end
    end
end
