package;

import flixel.FlxSprite;

/**
 * Sprite de cenário para softcode HScript.
 *
 * Mantém a ideia do BGSprite da Psych sem substituir os stages antigos da
 * Kade. A imagem é procurada primeiro em mods/images e depois nos assets.
 */
class KadeshBGSprite extends FlxSprite
{
	public var idleAnimation:String = '';

	public function new(
		image:String,
		x:Float = 0,
		y:Float = 0,
		scrollX:Float = 1,
		scrollY:Float = 1,
		?animations:Array<Dynamic>,
		loop:Bool = true
	)
	{
		super(x, y);
		scrollFactor.set(scrollX, scrollY);

		if (animations != null && animations.length > 0)
		{
			frames = KadeshModAssets.loadAtlas(image, 'sparrow');
			for (raw in animations)
			{
				if (raw == null || !Std.isOfType(raw, Array)) continue;
				var data:Array<Dynamic> = cast raw;
				if (data.length < 2) continue;
				var name:String = Std.string(data[0]);
				var prefix:String = Std.string(data[1]);
				var fps:Int = 24;
				if (data.length > 2)
				{
					var parsedFPS:Null<Int> = Std.parseInt(Std.string(data[2]));
					if (parsedFPS != null && parsedFPS > 0) fps = parsedFPS;
				}
				var animLoop:Bool = data.length > 3 ? data[3] == true : loop;
				animation.addByPrefix(name, prefix, fps, animLoop);
				if (idleAnimation.length == 0) idleAnimation = name;
			}
			if (idleAnimation.length > 0) animation.play(idleAnimation);
		}
		else if (image != null && image.length > 0)
		{
			KadeshModAssets.loadImageInto(this, image);
		}

		antialiasing = true;
	}

	public function dance(?force:Bool = false):Void
	{
		if (idleAnimation.length > 0)
			animation.play(idleAnimation, force);
	}
}
