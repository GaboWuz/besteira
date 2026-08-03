function onEvent(name, value1, value2)
    if name == 'My Event' then
        debugPrint('My Event: ' .. value1 .. ' / ' .. value2)
    end
end
