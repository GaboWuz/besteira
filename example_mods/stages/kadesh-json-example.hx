// Stage HScript complementar ao JSON acima.
// Ele só roda quando o chart usa "stage": "kadesh-json-example".

var lightOn:Bool = false;

function onCreatePost()
{
    setProperty('skyBlock.alpha', 0.9);
    setProperty('frontShade.visible', true);
    debugPrint('Stage JSON + HScript carregado.', '66FF99');
}

function onBeatHit()
{
    if (curBeat % 4 == 0)
    {
        lightOn = !lightOn;
        doTweenAlpha('stageSkyPulse', 'skyBlock', lightOn ? 0.65 : 0.9, 0.25, 'quadOut');
    }
}

function onEvent(name, value1, value2)
{
    if (name == 'Stage Flash')
        cameraFlash('game', value1 == '' ? 'FFFFFF' : value1, value2 == '' ? 0.25 : Std.parseFloat(value2), true);
}
