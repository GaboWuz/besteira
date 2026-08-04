package;

import flixel.util.FlxColor;

// Em characters/<nome>.hx, "character" é a instância carregada pelo JSON
// ou pelo Character.hx antigo da Kade. O script só acrescenta comportamento.
function onCreate():Void
{
	if (character == null) return;
	character.color = FlxColor.fromRGB(255, 235, 245);
	character.antialiasing = true;
}

function onBeatHit():Void
{
	if (character == null || curBeat % 2 != 0) return;
	character.angle = -1;
	doTweenAngle('characterReturn', characterName, 0, 0.12, 'quadOut');
}

// Para trocar atlas/animações por código, use:
// loadCharacterAtlas('dad', 'characters/MeuPersonagem', 'sparrow');
// addCharacterAnimation('dad', 'idle', 'Idle Prefix', 24, false, 0, 0);
// setCharacterIdle('dad', 'idle');
// setCharacterIcon('dad', 'meu-icone');
