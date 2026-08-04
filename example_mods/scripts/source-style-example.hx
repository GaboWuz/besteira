package;

import flixel.FlxSprite;
import flixel.tweens.FlxEase;
import flixel.tweens.FlxTween;
import flixel.util.FlxColor;

// Softcode de topo: parece source code, mas não precisa recompilar o jogo.
var sourceOverlay:FlxSprite;
var enabled:Bool = true;

function onCreatePost():Void
{
	sourceOverlay = new FlxSprite(0, 0);
	sourceOverlay.makeGraphic(1280, 720, FlxColor.fromRGB(20, 10, 40));
	sourceOverlay.alpha = 0;
	sourceOverlay.scrollFactor.set(0, 0);
	sourceOverlay.cameras = [camHUD];
	add(sourceOverlay);
}

function onBeatHit():Void
{
	if (!enabled || curBeat % 4 != 0) return;

	sourceOverlay.alpha = 0.12;
	FlxTween.tween(sourceOverlay, {alpha: 0}, 0.35, {
		ease: FlxEase.quadOut
	});
}

function onDestroy():Void
{
	sourceOverlay = null;
}
