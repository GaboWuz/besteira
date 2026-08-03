// Script específico de música: mods/data/hscript-example/script.hx

function onCreatePost()
{
    makeLuaText('hsInfo', 'HScript da musica funcionando', 520, 20, 90);
    setTextSize('hsInfo', 22);
    setTextColor('hsInfo', '66FF99');
    setObjectCamera('hsInfo', 'hud');
    addLuaText('hsInfo');

    // Mesma semântica de propriedades da API Lua/Psych.
    setProperty('boyfriend.alpha', 0.95);
    setProperty('dad.scale.x', 1.02);
    setProperty('dad.scale.y', 1.02);
}

function onBeatHit()
{
    if (curBeat % 8 == 4)
        triggerEvent('Set Camera Zoom', '0.88', '0.35');
    else if (curBeat % 8 == 0)
        triggerEvent('Set Camera Zoom', '0.82', '0.35');
}

function onDestroy()
{
    removeLuaText('hsInfo', true);
}
