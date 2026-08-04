package;

import flixel.FlxSprite;
import flixel.util.FlxColor;

// Stage totalmente criado por código, sem PNG novo.
var backWall:FlxSprite;
var floor:FlxSprite;

function onCreate():Void
{
	backWall = new FlxSprite(-400, -300);
	backWall.makeGraphic(2200, 1200, FlxColor.fromRGB(35, 28, 55));
	backWall.scrollFactor.set(0.7, 0.7);
	addBehindGF(backWall);

	floor = new FlxSprite(-400, 650);
	floor.makeGraphic(2200, 500, FlxColor.fromRGB(75, 55, 80));
	floor.scrollFactor.set(1, 1);
	addBehindDad(floor);
}

function onBeatHit():Void
{
	if (curBeat % 2 == 0)
		floor.alpha = 0.92;
	else
		floor.alpha = 1;
}
