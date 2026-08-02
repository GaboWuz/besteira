package;

import flixel.FlxG;
import flixel.graphics.frames.FlxAtlasFrames;
import flixel.system.FlxAssets.FlxSoundAsset;
import openfl.media.Sound;
import openfl.utils.AssetType;
import openfl.utils.Assets as OpenFlAssets;

#if sys
import sys.FileSystem;
import sys.io.File;
#end

class Paths
{
	inline public static var SOUND_EXT = #if web "mp3" #else "ogg" #end;

	static var currentLevel:String;
	static var externalSoundCache:Map<String, Sound> = new Map<String, Sound>();

	public static function setCurrentLevel(name:String):Void
	{
		currentLevel = name == null ? null : name.toLowerCase();
	}

	static function getPath(file:String, type:AssetType, library:Null<String>):String
	{
		if (library != null)
			return getLibraryPath(file, library);

		if (currentLevel != null)
		{
			var levelPath = getLibraryPathForce(file, currentLevel);
			if (OpenFlAssets.exists(levelPath, type))
				return levelPath;

			levelPath = getLibraryPathForce(file, "shared");
			if (OpenFlAssets.exists(levelPath, type))
				return levelPath;
		}

		return getPreloadPath(file);
	}

	public static function getLibraryPath(file:String, library:String = "preload"):String
	{
		return (library == "preload" || library == "default")
			? getPreloadPath(file)
			: getLibraryPathForce(file, library);
	}

	static inline function getLibraryPathForce(file:String, library:String):String
	{
		return '$library:assets/$library/$file';
	}

	public static inline function getPreloadPath(file:String):String
	{
		return 'assets/$file';
	}

	public static inline function file(file:String, type:AssetType = TEXT, ?library:String):String
	{
		return getPath(file, type, library);
	}

	static function externalModFile(relative:String):Null<String>
	{
		#if sys
		AndroidStorage.init();
		var path = AndroidStorage.modPath(relative);
		if (FileSystem.exists(path) && !FileSystem.isDirectory(path))
			return path;
		#end

		return null;
	}

	public static function getText(path:String):Null<String>
	{
		#if sys
		if (path != null && FileSystem.exists(path) && !FileSystem.isDirectory(path))
			return File.getContent(path);
		#end

		if (path != null && OpenFlAssets.exists(path, TEXT))
			return OpenFlAssets.getText(path);

		trace('[Paths] Arquivo de texto não encontrado: ' + path);
		return null;
	}

	public static inline function vanillaTxt(key:String, ?library:String):String
	{
		return getPath('data/$key.txt', TEXT, library);
	}

	public static function lua(key:String, ?library:String):String
	{
		if (library == null || library == "preload" || library == "default")
		{
			var external = externalModFile('data/$key.lua');
			if (external != null)
				return external;
		}
		return getPath('data/$key.lua', TEXT, library);
	}

	public static function luaImage(key:String, ?library:String):String
	{
		return getPath('data/$key.png', IMAGE, library);
	}

	public static function txt(key:String, ?library:String):String
	{
		if (library == null || library == "preload" || library == "default")
		{
			var external = externalModFile('data/$key.txt');
			if (external != null)
				return external;
		}
		return getPath('data/$key.txt', TEXT, library);
	}

	public static function xml(key:String, ?library:String):String
	{
		if (library == null || library == "preload" || library == "default")
		{
			var external = externalModFile('data/$key.xml');
			if (external != null)
				return external;
		}
		return getPath('data/$key.xml', TEXT, library);
	}

	public static function json(key:String, ?library:String):String
	{
		if (library == null || library == "preload" || library == "default")
		{
			var external = externalModFile('data/$key.json');
			if (external != null)
				return external;
		}
		return getPath('data/$key.json', TEXT, library);
	}

	public static function sound(key:String, ?library:String):FlxSoundAsset
	{
		var external = externalModFile('sounds/$key.$SOUND_EXT');
		var loaded = loadExternalSound(external);
		if (loaded != null)
			return loaded;

		return getPath('sounds/$key.$SOUND_EXT', SOUND, library);
	}

	public static inline function soundRandom(key:String, min:Int, max:Int, ?library:String):FlxSoundAsset
	{
		return sound(key + FlxG.random.int(min, max), library);
	}

	public static function music(key:String, ?library:String):FlxSoundAsset
	{
		var external = externalModFile('music/$key.$SOUND_EXT');
		var loaded = loadExternalSound(external);
		if (loaded != null)
			return loaded;

		return getPath('music/$key.$SOUND_EXT', MUSIC, library);
	}

	public static inline function video(key:String):String
	{
		return Asset2File.getPath('assets/videos/$key.mp4');
	}

	public static function formatToSongPath(song:String):String
	{
		if (song == null)
			return "";

		var result = StringTools.replace(song, " ", "-").toLowerCase();
		switch (result)
		{
			case 'dad-battle': result = 'dadbattle';
			case 'philly-nice': result = 'philly';
		}
		return result;
	}

	static function songSound(song:String, fileName:String):FlxSoundAsset
	{
		var songFolder = formatToSongPath(song);
		var external = externalModFile('songs/$songFolder/$fileName.$SOUND_EXT');
		var loaded = loadExternalSound(external);
		if (loaded != null)
			return loaded;

		return 'songs:assets/songs/$songFolder/$fileName.$SOUND_EXT';
	}

	public static inline function voices(song:String):FlxSoundAsset
	{
		return songSound(song, "Voices");
	}

	public static inline function inst(song:String):FlxSoundAsset
	{
		return songSound(song, "Inst");
	}

	static function loadExternalSound(path:Null<String>):Null<Sound>
	{
		#if sys
		if (path == null)
			return null;

		if (externalSoundCache.exists(path))
			return externalSoundCache.get(path);

		try
		{
			var sound = Sound.fromFile(path);
			if (sound != null)
			{
				externalSoundCache.set(path, sound);
				return sound;
			}
		}
		catch (e:Dynamic)
		{
			trace('[Paths] Falha ao carregar áudio externo "' + path + '": ' + Std.string(e));
		}
		#end

		return null;
	}

	public static inline function image(key:String, ?library:String):String
	{
		return getPath('images/$key.png', IMAGE, library);
	}

	public static inline function font(key:String):String
	{
		return 'assets/fonts/$key';
	}

	public static function getSparrowAtlas(key:String, ?library:String):FlxAtlasFrames
	{
		return FlxAtlasFrames.fromSparrow(image(key, library), file('images/$key.xml', TEXT, library));
	}

	public static function getPackerAtlas(key:String, ?library:String):FlxAtlasFrames
	{
		return FlxAtlasFrames.fromSpriteSheetPacker(image(key, library), file('images/$key.txt', TEXT, library));
	}
}
