package;

import flixel.FlxSprite;
import flixel.util.FlxColor;

var songMarker:FlxSprite;

function onCreatePost():Void
{
	songMarker = new FlxSprite(20, 100);
	songMarker.makeGraphic(16, 160, FlxColor.CYAN);
	songMarker.cameras = [camHUD];
	add(songMarker);
}

function onStepHit():Void
{
	if (curStep == 64)
		triggerEvent('Camera Follow Pos', '640', '360');
	if (curStep == 96)
		triggerEvent('Camera Follow Pos', '', '');
}
