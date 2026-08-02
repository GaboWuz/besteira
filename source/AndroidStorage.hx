package;

import StringTools;
import haxe.io.Path;

#if sys
import sys.FileSystem;
import sys.io.File;
#end

#if android
import androidmanager.content.Context;
#end

class AndroidStorage
{
	public static var root(default, null):String = "";
	public static var saves(default, null):String = "";
	public static var cache(default, null):String = "";
	public static var logs(default, null):String = "";
	public static var mods(default, null):String = "";

	public static var modsData(default, null):String = "";
	public static var modsSongs(default, null):String = "";
	public static var modsImages(default, null):String = "";
	public static var modsSounds(default, null):String = "";
	public static var modsMusic(default, null):String = "";
	public static var modsVideos(default, null):String = "";
	public static var modsScripts(default, null):String = "";

	public static var initialized(default, null):Bool = false;

	public static function init():Void
	{
		if (initialized)
			return;

		#if sys
		try
		{
			setup(buildRoot());
		}
		catch (e:Dynamic)
		{
			trace('[AndroidStorage] Falha ao preparar o storage principal: ' + Std.string(e));

			// Último fallback para não impedir o jogo de iniciar.
			try
			{
				setup(Path.join([Sys.getCwd(), "KadeEngineStorage"]));
			}
			catch (fallbackError:Dynamic)
			{
				trace('[AndroidStorage] Falha também no fallback: ' + Std.string(fallbackError));
			}
		}
		#end

		initialized = true;
		trace('[AndroidStorage] Pasta raiz: ' + root);
	}

	#if sys
	static function setup(baseRoot:String):Void
	{
		root = normalize(baseRoot);
		saves = join(root, "saves");
		cache = join(root, "cache");
		logs = join(root, "logs");
		mods = join(root, "mods");

		modsData = join(mods, "data");
		modsSongs = join(mods, "songs");
		modsImages = join(mods, "images");
		modsSounds = join(mods, "sounds");
		modsMusic = join(mods, "music");
		modsVideos = join(mods, "videos");
		modsScripts = join(mods, "scripts");

		ensureDir(root);
		ensureDir(saves);
		ensureDir(cache);
		ensureDir(logs);
		ensureDir(mods);
		ensureDir(modsData);
		ensureDir(modsSongs);
		ensureDir(modsImages);
		ensureDir(modsSounds);
		ensureDir(modsMusic);
		ensureDir(modsVideos);
		ensureDir(modsScripts);

		createTextIfMissing(join(mods, "README.txt"),
			"KADE ENGINE - MODS EXTERNOS\n\n" +
			"Chart: mods/data/nome-da-musica/chart.json\n" +
			"Audio: mods/songs/nome-da-musica/Inst.ogg e Voices.ogg\n" +
			"Freeplay: mods/data/freeplaySonglist.txt\n");

		createTextIfMissing(join(modsData, "freeplaySonglist.txt"),
			"# Formato: Nome da Musica:icone:semana\n" +
			"# Exemplo: Minha Musica:dad:0\n");
	}
	#end

	static function buildRoot():String
	{
		#if android
		var base:Null<String> = Context.getExternalFilesDir(null);
		if (base == null || base.length == 0)
			base = Context.getInternalFilesDir();

		if (base == null || base.length == 0)
			return "KadeEngineStorage";

		return join(base, "KadeEngine");
		#elseif sys
		return Path.join([Sys.getCwd(), "KadeEngineStorage"]);
		#else
		return "KadeEngineStorage";
		#end
	}

	public static function modPath(relative:String):String
	{
		init();
		return join(mods, cleanRelative(relative));
	}

	// Alias para não quebrar códigos antigos que já chamavam modFile().
	public static inline function modFile(relative:String):String
	{
		return modPath(relative);
	}

	public static function modExists(relative:String):Bool
	{
		#if sys
		var path = modPath(relative);
		return FileSystem.exists(path) && !FileSystem.isDirectory(path);
		#else
		return false;
		#end
	}

	public static function readText(relative:String, ?fallback:String = null):String
	{
		#if sys
		var path = modPath(relative);
		if (FileSystem.exists(path) && !FileSystem.isDirectory(path))
			return File.getContent(path);
		#end

		return fallback;
	}

	public static function writeText(relative:String, content:String):Bool
	{
		#if sys
		try
		{
			var path = modPath(relative);
			var parent = Path.directory(path);
			if (parent != null && parent.length > 0)
				ensureDir(parent);

			File.saveContent(path, content);
			return true;
		}
		catch (e:Dynamic)
		{
			trace('[AndroidStorage] Não foi possível gravar "' + relative + '": ' + Std.string(e));
		}
		#end

		return false;
	}

	static function cleanRelative(path:String):String
	{
		if (path == null)
			return "";

		var result = StringTools.replace(path, "\\", "/");
		while (StringTools.startsWith(result, "/"))
			result = result.substr(1);

		// Impede que um caminho relativo saia da pasta mods.
		while (result.indexOf("../") != -1)
			result = StringTools.replace(result, "../", "");

		return result;
	}

	static function normalize(path:String):String
	{
		if (path == null)
			return "";
		return StringTools.replace(path, "\\", "/");
	}

	static function join(left:String, right:String):String
	{
		if (left == null || left.length == 0)
			return cleanRelative(right);
		if (right == null || right.length == 0)
			return normalize(left);

		var cleanLeft = normalize(left);
		while (StringTools.endsWith(cleanLeft, "/"))
			cleanLeft = cleanLeft.substr(0, cleanLeft.length - 1);

		return cleanLeft + "/" + cleanRelative(right);
	}

	#if sys
	static function ensureDir(directory:String):Void
	{
		if (directory == null || directory.length == 0 || FileSystem.exists(directory))
			return;

		var parent = Path.directory(directory);
		if (parent != null && parent.length > 0 && parent != directory)
			ensureDir(parent);

		if (!FileSystem.exists(directory))
			FileSystem.createDirectory(directory);
	}

	static function createTextIfMissing(path:String, content:String):Void
	{
		if (FileSystem.exists(path))
			return;

		var parent = Path.directory(path);
		if (parent != null && parent.length > 0)
			ensureDir(parent);

		File.saveContent(path, content);
	}
	#end
}
