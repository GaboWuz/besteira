package;

import flixel.FlxSprite;
import openfl.display.BitmapData;

#if sys
import sys.FileSystem;
#end

class HealthIcon extends FlxSprite
{
	/**
	 * Usado pelo FreeplayState.
	 */
	public var sprTracker:FlxSprite;

	/**
	 * True somente quando o PNG veio de KadeshEngine/mods/images/icons.
	 */
	public var loadedFromMods(default, null):Bool = false;

	public function new(char:String = 'bf', isPlayer:Bool = false)
	{
		super();

		if (!loadModIcon(char, isPlayer))
			loadIconGrid(char, isPlayer);

		scrollFactor.set();
	}

	/**
	 * Ícone estilo Psych:
	 * KadeshEngine/mods/images/icons/icon-personagem.png
	 *
	 * O PNG deve ter 300x150:
	 * - frame 0 (150x150): normal
	 * - frame 1 (150x150): perdendo
	 *
	 * Esta busca acontece SOMENTE no mods folder. Os personagens internos
	 * continuam usando o iconGrid original da Kade.
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

				var frameCount:Int = frames == null ? 0 : frames.frames.length;
				if (frameCount <= 0)
					throw 'Nenhum frame foi criado para "$path".';

				var losingFrame:Int = frameCount > 1 ? 1 : 0;
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

		var selected:String = char;
		if (animation.getByName(selected) == null)
		{
			trace('[HealthIcon] Sem ícone externo ou iconGrid para "$char"; usando face.');
			selected = 'face';
		}

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
