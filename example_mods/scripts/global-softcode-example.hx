// Script HScript global: mods/scripts/*.hx
var greeted:Bool = false;

function onCreatePost()
{
    greeted = true;
    debugPrint('HScript global ativo em Android/PC.', '66CCFF');
}

function onSongStart()
{
    if (greeted)
        triggerEvent('Add Camera Zoom', '0.015', '0.025');
}
