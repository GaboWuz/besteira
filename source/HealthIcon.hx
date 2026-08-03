package;

import flixel.FlxSprite;
import openfl.display.BitmapData;

#if sys
import sys.FileSystem;
#end

class HealthIcon extends FlxSprite
{
	/** Usado pelo FreeplayState. */
	public var sprTracker:FlxSprite;
	public var loadedFromMods(default, null):Bool = false;
	public var currentCharacter(default, null):String = '';
	public var isPlayerIcon(default, null):Bool = false;

	public function new(char:String = 'bf', isPlayer:Bool = false)
	{
		super();
		changeIcon(char, isPlayer);
		scrollFactor.set();
	}

	public function changeIcon(char:String, ?isPlayer:Null<Bool>):Void
	{
		if (char == null || char.length == 0)
			char = 'face';

		if (isPlayer != null)
			isPlayerIcon = isPlayer;

		currentCharacter = char;
		loadedFromMods = false;

		if (animation != null)
			animation.destroyAnimations();

		if (!loadModIcon(char, isPlayerIcon))
			loadIconGrid(char, isPlayerIcon);
	}

	/**
	 * Ícone externo estilo Psych, usado somente no mods folder:
	 * KadeshEngine/mods/images/icons/icon-personagem.png
	 *
	 * 300x150 = frame normal + frame perdendo.
	 * 150x150 também funciona, repetindo o mesmo frame.
	 */
	private function loadModIcon(char:String, isPlayer:Bool):Bool
	{
		#if sys
		try
		{
			AndroidStorage.init();

			var candidates:Array<String> = [
				AndroidStorage.modPath('images/icons/icon-$char.png'),
				AndroidStorage.modPath('images/icons/$char.png')
			];

			for (path in candidates)
			{
				if (!FileSystem.exists(path) || FileSystem.isDirectory(path))
					continue;

				var bitmap:BitmapData = BitmapData.fromFile(path);
				if (bitmap == null)
					continue;

				if (bitmap.width < 150 || bitmap.height < 150)
					throw 'O ícone "$path" precisa ter pelo menos 150x150.';

				loadGraphic(bitmap, true, 150, 150);

				var losingFrame:Int = bitmap.width >= 300 ? 1 : 0;
				animation.add(char, [0, losingFrame], 0, false, isPlayer);
				animation.play(char);

				antialiasing = true;
				loadedFromMods = true;
				return true;
			}
		}
		catch (e:Dynamic)
		{
			trace('[HealthIcon] Ícone externo inválido para "$char": ' + Std.string(e));
		}
		#end

		return false;
	}

	private function loadIconGrid(char:String, isPlayer:Bool):Void
	{
		loadGraphic(Paths.image('iconGrid'), true, 150, 150);
		antialiasing = true;

		animation.add('bf', [0, 1], 0, false, isPlayer);
		animation.add('bf-car', [0, 1], 0, false, isPlayer);
		animation.add('bf-christmas', [0, 1], 0, false, isPlayer);
		animation.add('bf-pixel', [21, 21], 0, false, isPlayer);
		animation.add('spooky', [2, 3], 0, false, isPlayer);
		animation.add('pico', [4, 5], 0, false, isPlayer);
		animation.add('mom', [6, 7], 0, false, isPlayer);
		animation.add('mom-car', [6, 7], 0, false, isPlayer);
		animation.add('tankman', [8, 9], 0, false, isPlayer);
		animation.add('face', [10, 11], 0, false, isPlayer);
		animation.add('dad', [12, 13], 0, false, isPlayer);
		animation.add('senpai', [22, 22], 0, false, isPlayer);
		animation.add('senpai-angry', [22, 22], 0, false, isPlayer);
		animation.add('spirit', [23, 23], 0, false, isPlayer);
		animation.add('bf-old', [14, 15], 0, false, isPlayer);
		animation.add('gf', [16], 0, false, isPlayer);
		animation.add('gf-christmas', [16], 0, false, isPlayer);
		animation.add('gf-pixel', [16], 0, false, isPlayer);
		animation.add('parents-christmas', [17, 18], 0, false, isPlayer);
		animation.add('monster', [19, 20], 0, false, isPlayer);
		animation.add('monster-christmas', [19, 20], 0, false, isPlayer);

		var selected:String = animation.getByName(char) != null ? char : 'face';
		if (selected == 'face' && char != 'face')
			trace('[HealthIcon] Sem PNG externo/iconGrid para "$char"; usando face.');

		animation.play(selected);

		switch (selected)
		{
			case 'bf-pixel' | 'senpai' | 'senpai-angry' | 'spirit' | 'gf-pixel':
				antialiasing = false;
		}
	}

	override function update(elapsed:Float):Void
	{
		super.update(elapsed);

		if (sprTracker != null)
			setPosition(sprTracker.x + sprTracker.width + 10, sprTracker.y - 30);
	}
}
