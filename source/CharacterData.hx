package;

import flixel.graphics.FlxGraphic;
import flixel.graphics.frames.FlxAtlasFrames;
import haxe.Json;
import openfl.display.BitmapData;

#if sys
import sys.FileSystem;
import sys.io.File;
#end

using StringTools;

/**
 * Carregador opcional de personagens JSON.
 *
 * Prioridade:
 * 1. KadeshEngine/mods/characters/<personagem>.json
 * 2. Character.hx antigo
 * 3. BF/Dad de emergência, caso o nome não exista em nenhum dos dois
 *
 * Portanto, uma falha no mods folder não impede o jogo de abrir.
 */
class CharacterData
{
	public static function tryApply(character:Character, characterId:String):Bool
	{
		#if sys
		try
		{
			AndroidStorage.init();

			var jsonPath:String = AndroidStorage.modPath('characters/$characterId.json');
			if (!FileSystem.exists(jsonPath) || FileSystem.isDirectory(jsonPath))
				return false;

			var raw:String = File.getContent(jsonPath);
			var data:Dynamic = Json.parse(raw);

			applyJson(character, characterId, data);
			trace('[CharacterData] Personagem externo carregado: $characterId');
			return true;
		}
		catch (e:Dynamic)
		{
			trace(
				'[CharacterData] Falha no personagem externo "$characterId". '
				+ 'O jogo tentará o personagem interno: '
				+ Std.string(e)
			);
		}
		#end

		return false;
	}

	static function applyJson(character:Character, characterId:String, data:Dynamic):Void
	{
		if (data == null)
			throw 'JSON vazio.';

		var imageKey:String = readString(data, 'image', null);
		if (imageKey == null || imageKey.length == 0)
			throw 'Campo obrigatório "image" ausente.';

		imageKey = stripImageExtension(imageKey);

		var atlasType:String = readString(data, 'atlas', 'sparrow').toLowerCase();
		var library:String = readString(data, 'library', null);
		character.frames = loadFrames(imageKey, atlasType, library);

		if (character.frames == null)
			throw 'Não foi possível criar o atlas de "$imageKey".';

		character.antialiasing = readBool(data, 'antialiasing', true);
		character.flipX = readBool(data, 'flipX', false);
		character.healthIcon = readString(data, 'healthIcon', characterId);
		character.jsonIdleAnimation = readString(data, 'initialAnimation', 'idle');

		var animations:Dynamic = Reflect.field(data, 'animations');
		if (animations == null || !Std.isOfType(animations, Array))
			throw 'Campo obrigatório "animations" ausente ou inválido.';

		var animationList:Array<Dynamic> = cast animations;
		if (animationList.length == 0)
			throw 'A lista "animations" está vazia.';

		for (animationData in animationList)
			addAnimation(character, animationData);

		validateAnimation(character, character.jsonIdleAnimation);
		validateAnimation(character, 'singLEFT');
		validateAnimation(character, 'singDOWN');
		validateAnimation(character, 'singUP');
		validateAnimation(character, 'singRIGHT');

		var scale:Float = readFloat(data, 'scale', 1);
		if (scale <= 0)
			scale = 1;

		if (scale != 1)
		{
			character.setGraphicSize(Std.int(character.width * scale));
			character.updateHitbox();
		}

		var position:Array<Float> = readFloatArray(data, 'position', [0, 0]);
		if (position.length >= 2)
		{
			character.x += position[0];
			character.y += position[1];
		}

		character.isJsonCharacter = true;
		character.playAnim(character.jsonIdleAnimation, true);
	}

	static function loadFrames(imageKey:String, atlasType:String, library:String):FlxAtlasFrames
	{
		#if sys
		var pngPath:String = AndroidStorage.modPath('images/$imageKey.png');

		if (FileSystem.exists(pngPath) && !FileSystem.isDirectory(pngPath))
		{
			var bitmap:BitmapData = BitmapData.fromFile(pngPath);
			if (bitmap == null)
				throw 'Falha ao ler PNG externo "$pngPath".';

			var graphic:FlxGraphic = FlxGraphic.fromBitmapData(bitmap, false, pngPath);

			if (atlasType == 'packer')
			{
				var txtPath:String = AndroidStorage.modPath('images/$imageKey.txt');
				if (!FileSystem.exists(txtPath))
					throw 'Atlas Packer não encontrado: "$txtPath".';

				return FlxAtlasFrames.fromSpriteSheetPacker(
					graphic,
					File.getContent(txtPath)
				);
			}

			var xmlPath:String = AndroidStorage.modPath('images/$imageKey.xml');
			if (!FileSystem.exists(xmlPath))
				throw 'XML Sparrow não encontrado: "$xmlPath".';

			return FlxAtlasFrames.fromSparrow(
				graphic,
				File.getContent(xmlPath)
			);
		}
		#end

		// Permite testar um JSON externo usando uma imagem interna da Kade.
		if (atlasType == 'packer')
			return Paths.getPackerAtlas(imageKey, library);

		return Paths.getSparrowAtlas(imageKey, library);
	}

	static function addAnimation(character:Character, data:Dynamic):Void
	{
		var name:String = readString(data, 'name', null);
		var prefix:String = readString(data, 'prefix', null);

		if (name == null || name.length == 0)
			throw 'Uma animação está sem "name".';

		if (prefix == null || prefix.length == 0)
			throw 'A animação "$name" está sem "prefix".';

		var fps:Int = Std.int(readFloat(data, 'fps', 24));
		var loop:Bool = readBool(data, 'loop', false);
		var indicesValue:Dynamic = Reflect.field(data, 'indices');

		if (indicesValue != null && Std.isOfType(indicesValue, Array))
		{
			var indices:Array<Int> = [];
			for (value in (cast indicesValue:Array<Dynamic>))
				indices.push(Std.int(value));

			character.animation.addByIndices(
				name,
				prefix,
				indices,
				"",
				fps,
				loop
			);
		}
		else
		{
			character.animation.addByPrefix(
				name,
				prefix,
				fps,
				loop
			);
		}

		var offset:Array<Float> = readFloatArray(data, 'offset', [0, 0]);
		character.addOffset(
			name,
			offset.length > 0 ? offset[0] : 0,
			offset.length > 1 ? offset[1] : 0
		);
	}

	static function validateAnimation(character:Character, name:String):Void
	{
		if (character.animation.getByName(name) == null)
			throw 'Animação obrigatória ausente: "$name".';
	}

	/**
	 * Evita tela preta/crash caso o chart use um nome inexistente.
	 */
	public static function applyEmergencyFallback(character:Character, isPlayer:Bool):Void
	{
		trace(
			'[CharacterData] Personagem "' + character.curCharacter
			+ '" não existe. Usando fallback interno.'
		);

		character.animOffsets = new Map<String, Array<Dynamic>>();
		character.isJsonCharacter = false;

		if (isPlayer)
		{
			character.frames = Paths.getSparrowAtlas('characters/BOYFRIEND', 'shared');
			character.animation.addByPrefix('idle', 'BF idle dance', 24, false);
			character.animation.addByPrefix('singUP', 'BF NOTE UP0', 24, false);
			character.animation.addByPrefix('singLEFT', 'BF NOTE LEFT0', 24, false);
			character.animation.addByPrefix('singRIGHT', 'BF NOTE RIGHT0', 24, false);
			character.animation.addByPrefix('singDOWN', 'BF NOTE DOWN0', 24, false);

			character.addOffset('idle', -5);
			character.addOffset('singUP', -29, 27);
			character.addOffset('singRIGHT', -38, -7);
			character.addOffset('singLEFT', 12, -6);
			character.addOffset('singDOWN', -10, -50);

			character.healthIcon = 'bf';
			character.jsonIdleAnimation = 'idle';
			character.flipX = true;
		}
		else
		{
			character.frames = Paths.getSparrowAtlas('characters/DADDY_DEAREST', 'shared');
			character.animation.addByPrefix('idle', 'Dad idle dance', 24, false);
			character.animation.addByPrefix('singUP', 'Dad Sing Note UP', 24, false);
			character.animation.addByPrefix('singRIGHT', 'Dad Sing Note RIGHT', 24, false);
			character.animation.addByPrefix('singDOWN', 'Dad Sing Note DOWN', 24, false);
			character.animation.addByPrefix('singLEFT', 'Dad Sing Note LEFT', 24, false);

			character.addOffset('idle');
			character.addOffset('singUP', -6, 50);
			character.addOffset('singRIGHT', 0, 27);
			character.addOffset('singLEFT', -10, 10);
			character.addOffset('singDOWN', 0, -30);

			character.healthIcon = 'dad';
			character.jsonIdleAnimation = 'idle';
			character.flipX = false;
		}

		character.antialiasing = true;
		character.playAnim('idle', true);
	}

	static function stripImageExtension(value:String):String
	{
		var result:String = value.replace('\\', '/');

		if (result.endsWith('.png'))
			result = result.substr(0, result.length - 4);

		while (result.startsWith('/'))
			result = result.substr(1);

		return result;
	}

	static function readString(data:Dynamic, field:String, fallback:String):String
	{
		var value:Dynamic = Reflect.field(data, field);
		return value == null ? fallback : Std.string(value);
	}

	static function readBool(data:Dynamic, field:String, fallback:Bool):Bool
	{
		var value:Dynamic = Reflect.field(data, field);
		return value == null ? fallback : value == true;
	}

	static function readFloat(data:Dynamic, field:String, fallback:Float):Float
	{
		var value:Dynamic = Reflect.field(data, field);
		if (value == null)
			return fallback;

		var parsed:Float = Std.parseFloat(Std.string(value));
		return Math.isNaN(parsed) ? fallback : parsed;
	}

	static function readFloatArray(
		data:Dynamic,
		field:String,
		fallback:Array<Float>
	):Array<Float>
	{
		var value:Dynamic = Reflect.field(data, field);

		if (value == null || !Std.isOfType(value, Array))
			return fallback.copy();

		var result:Array<Float> = [];
		for (item in (cast value:Array<Dynamic>))
		{
			var parsed:Float = Std.parseFloat(Std.string(item));
			result.push(Math.isNaN(parsed) ? 0 : parsed);
		}

		return result;
	}
}
