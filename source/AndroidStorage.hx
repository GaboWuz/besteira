package;

import StringTools;
import haxe.io.Path;

using StringTools;

#if sys
import sys.FileSystem;
import sys.io.File;
#end

#if android
import androidmanager.content.Interface;
import androidmanager.os.Environment;
import androidmanager.os.Build.VERSION;
import androidmanager.tools.PermissionUtils;
#end

/**
 * Storage externo opcional da Kadeshing.
 *
 * A pasta desejada e:
 * /storage/emulated/0/KadeshEngine
 *
 * Se a permissao for negada, se a pasta estiver indisponivel ou se qualquer
 * operacao falhar, available fica false e o jogo continua usando os assets
 * internos. Nenhum loader deve depender desta pasta para iniciar o jogo.
 */
class AndroidStorage
{
	public static inline var APP_FOLDER:String = "KadeshEngine";

	public static var root(default, null):String = "";
	public static var saves(default, null):String = "";
	public static var cache(default, null):String = "";
	public static var logs(default, null):String = "";
	public static var mods(default, null):String = "";
	public static var modsData(default, null):String = "";
	public static var modsSongs(default, null):String = "";
	public static var modsImages(default, null):String = "";
	public static var modsCharacters(default, null):String = "";
	public static var modsIcons(default, null):String = "";
	public static var modsSounds(default, null):String = "";
	public static var modsMusic(default, null):String = "";
	public static var modsVideos(default, null):String = "";
	public static var modsScripts(default, null):String = "";
	public static var modsStages(default, null):String = "";
	public static var modsCustomEvents(default, null):String = "";
	public static var modsCustomNoteTypes(default, null):String = "";

	/** true somente quando a estrutura foi criada e o teste de escrita passou. */
	public static var initialized(default, null):Bool = false;
	public static var available(default, null):Bool = false;
	public static var lastError(default, null):String = "";

	static var silentProbeDone:Bool = false;
	static var permissionFlowStarted:Bool = false;
	static var allFilesSettingsOpened:Bool = false;
	static var warningShown:Bool = false;

	/**
	 * Tentativa silenciosa. Pode ser chamada por Paths/Freeplay sem abrir telas.
	 * Nunca deve impedir o jogo de iniciar.
	 */
	public static function init():Void
	{
		if (available || silentProbeDone)
			return;

		silentProbeDone = true;
		tryInitialize();
	}

	/**
	 * Inicia o fluxo de permissao depois que o FlxGame ja foi criado.
	 */
	public static function startPermissionFlow():Void
	{
		if (available || tryInitialize())
			return;

		#if android
		if (permissionFlowStarted)
			return;

		permissionFlowStarted = true;

		// Android 11+ usa a tela especial "Acesso a todos os arquivos".
		// Essa permissao nao aparece na tela comum mostrada no print.
		if (VERSION.SDK_INT >= 30)
		{
			requestAllFilesOrWarn();
			return;
		}

		// Android 6 ate Android 10 usa a permissao tradicional de armazenamento.
		if (VERSION.SDK_INT >= 23 && !PermissionUtils.hasPermission("WRITE_EXTERNAL_STORAGE"))
		{
			try
			{
				PermissionUtils.requestPermissions([
					"READ_EXTERNAL_STORAGE",
					"WRITE_EXTERNAL_STORAGE"
				]);
			}
			catch (e:Dynamic)
			{
				lastError = "Falha ao pedir permissao de armazenamento: " + Std.string(e);
				trace('[AndroidStorage] ' + lastError);
				requestAllFilesOrWarn();
			}

			// Apenas verifica se a permissao foi aceita. Nao abre outra tela por
			// cima do dialogo do Android.
			haxe.Timer.delay(function():Void
			{
				if (!available && PermissionUtils.hasPermission("WRITE_EXTERNAL_STORAGE"))
					tryInitialize();
			}, 1500);
			return;
		}

		requestAllFilesOrWarn();
		#else
		warnOnce("A pasta externa nao esta disponivel neste sistema.");
		#end
	}

	#if android
	/** Chamado quando o app volta da tela de permissao/configuracoes. */
	public static function onAppActivate():Void
	{
		if (available || !permissionFlowStarted)
			return;

		if (tryInitialize())
			return;

		// Depois do dialogo tradicional, Android 11+ pode ainda exigir o acesso
		// especial a todos os arquivos para escrever na raiz /storage/emulated/0.
		if (VERSION.SDK_INT >= 30 && !Environment.isExternalStorageManager())
		{
			if (allFilesSettingsOpened)
			{
				warnOnce(
					"O acesso a todos os arquivos nao foi autorizado. " +
					"Os mods externos foram desativados."
				);
			}
			else
			{
				requestAllFilesAccess();
			}
			return;
		}

		warnOnce(
			"Nao foi possivel criar ou escrever em /storage/emulated/0/" + APP_FOLDER + ". " +
			(lastError.length > 0 ? "Detalhe: " + lastError : "Verifique a permissao de arquivos.")
		);
	}

	static function requestAllFilesOrWarn():Void
	{
		if (available || tryInitialize())
			return;

		if (VERSION.SDK_INT >= 30 && !Environment.isExternalStorageManager())
		{
			requestAllFilesAccess();
			return;
		}

		warnOnce(
			"Nao foi possivel acessar /storage/emulated/0/" + APP_FOLDER + ". " +
			"Os mods externos foram desativados."
		);
	}

	static function requestAllFilesAccess():Void
	{
		if (allFilesSettingsOpened)
			return;

		try
		{
			Interface.showConfirm(
				"Permissao para mods externos",
				"Para usar a pasta /storage/emulated/0/" + APP_FOLDER +
				", permita que o jogo gerencie arquivos.\n\n" +
				"Se voce negar, o jogo continuara funcionando apenas com os arquivos internos.",
				"Abrir configuracoes",
				"Continuar sem mods",
				function():Void
				{
					allFilesSettingsOpened = true;
					try
					{
						Interface.requestSetting("MANAGE_APP_ALL_FILES_ACCESS_PERMISSION", 7701);
					}
					catch (e:Dynamic)
					{
						lastError = "Falha ao abrir a configuracao de acesso a arquivos: " + Std.string(e);
						warnOnce(lastError);
					}
				},
				function():Void
				{
					warnOnce("Permissao nao concedida. Os mods externos foram desativados.");
				}
			);
		}
		catch (e:Dynamic)
		{
			lastError = "Falha ao mostrar a solicitacao de permissao: " + Std.string(e);
			warnOnce(lastError);
		}
	}
	#else
	public static function onAppActivate():Void {}
	#end

	/**
	 * Cria a estrutura e confirma que ela realmente aceita escrita.
	 */
	static function tryInitialize():Bool
	{
		#if sys
		try
		{
			setup(buildRoot());

			var probe = join(root, ".kadesh_write_test");
			File.saveContent(probe, "ok");
			if (FileSystem.exists(probe))
				FileSystem.deleteFile(probe);

			available = true;
			initialized = true;
			lastError = "";
			trace('[AndroidStorage] Storage externo pronto: ' + root);
			return true;
		}
		catch (e:Dynamic)
		{
			available = false;
			initialized = false;
			lastError = Std.string(e);
			trace('[AndroidStorage] Storage externo indisponivel: ' + lastError);
			return false;
		}
		#else
		return false;
		#end
	}

	static function buildRoot():String
	{
		#if android
		var base:Null<String> = Environment.getExternalStorageDirectory();
		if (base == null || base.length == 0 || base == "Unknown" || base.startsWith("Error:"))
			throw "O Android nao retornou o caminho do armazenamento compartilhado.";

		return join(base, APP_FOLDER);
		#elseif sys
		return Path.join([Sys.getCwd(), APP_FOLDER]);
		#else
		return APP_FOLDER;
		#end
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
		modsCharacters = join(mods, "characters");
		modsIcons = join(modsImages, "icons");
		modsSounds = join(mods, "sounds");
		modsMusic = join(mods, "music");
		modsVideos = join(mods, "videos");
		modsScripts = join(mods, "scripts");
		modsStages = join(mods, "stages");
		modsCustomEvents = join(mods, "custom_events");
		modsCustomNoteTypes = join(mods, "custom_notetypes");

		ensureDir(root);
		ensureDir(saves);
		ensureDir(cache);
		ensureDir(logs);
		ensureDir(mods);
		ensureDir(modsData);
		ensureDir(modsSongs);
		ensureDir(modsImages);
		ensureDir(modsCharacters);
		ensureDir(modsIcons);
		ensureDir(modsSounds);
		ensureDir(modsMusic);
		ensureDir(modsVideos);
		ensureDir(modsScripts);
		ensureDir(modsStages);
		ensureDir(modsCustomEvents);
		ensureDir(modsCustomNoteTypes);

		createTextIfMissing(join(mods, "README.txt"),
			"KADESHING - MODS EXTERNOS\n\n" +
			"Chart: mods/data/nome-da-musica/nome-da-musica.json\n" +
			"Audio: mods/songs/nome-da-musica/Inst.ogg e Voices.ogg\n" +
			"Freeplay: mods/data/freeplaySonglist.txt\n" +
			"Personagens JSON: mods/characters/nome.json\n" +
			"Ícones Psych: mods/images/icons/icon-nome.png\n" +
			"Lua global: mods/scripts/arquivo.lua\n" +
			"Lua da música: mods/data/nome-da-musica/script.lua\n" +
			"Lua de personagem: mods/characters/personagem.lua\n" +
			"Stage JSON/HScript: mods/stages/nome.json e nome.hx\n" +
			"HScript de personagem: mods/characters/personagem.hx\n" +
			"HScript global: mods/scripts/arquivo.hx\n" +
			"HScript da música: mods/data/nome-da-musica/script.hx\n");

		createTextIfMissing(join(modsData, "freeplaySonglist.txt"),
			"# Formato: Nome da Musica:icone:semana\n" +
			"# Exemplo: Minha Musica:dad:0\n");
	}
	#end

	public static function modPath(relative:String):String
	{
		init();
		if (!available || mods.length == 0)
			return "__KADESH_MODS_DISABLED__/" + cleanRelative(relative);
		return join(mods, cleanRelative(relative));
	}

	public static inline function modFile(relative:String):String
	{
		return modPath(relative);
	}

	public static function modExists(relative:String):Bool
	{
		#if sys
		if (!available)
			return false;
		try
		{
			var path = modPath(relative);
			return FileSystem.exists(path) && !FileSystem.isDirectory(path);
		}
		catch (e:Dynamic) {}
		#end
		return false;
	}

	public static function readText(relative:String, ?fallback:String = null):String
	{
		#if sys
		if (!available)
			return fallback;
		try
		{
			var path = modPath(relative);
			if (FileSystem.exists(path) && !FileSystem.isDirectory(path))
				return File.getContent(path);
		}
		catch (e:Dynamic)
		{
			trace('[AndroidStorage] Falha ao ler "' + relative + '": ' + Std.string(e));
		}
		#end
		return fallback;
	}

	public static function writeText(relative:String, content:String):Bool
	{
		#if sys
		if (!available)
			return false;
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
			trace('[AndroidStorage] Nao foi possivel gravar "' + relative + '": ' + Std.string(e));
		}
		#end
		return false;
	}

	static function warnOnce(message:String):Void
	{
		if (warningShown)
			return;
		warningShown = true;

		var fullMessage = message + "\n\nO jogo continuara usando os arquivos internos normalmente.";
		trace('[AndroidStorage] ' + fullMessage);

		#if android
		try
		{
			Interface.showAlert("Mods externos desativados", fullMessage, "Continuar");
		}
		catch (e:Dynamic)
		{
			trace('[AndroidStorage] Tambem falhou ao mostrar o aviso: ' + Std.string(e));
		}
		#end
	}

	static function cleanRelative(path:String):String
	{
		if (path == null)
			return "";

		var result = StringTools.replace(path, "\\", "/");
		while (result.startsWith("/"))
			result = result.substr(1);
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
		while (cleanLeft.endsWith("/"))
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
