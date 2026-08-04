package;

import openfl.display.BlendMode;
import openfl.text.TextFormat;
import openfl.display.Application;
import flixel.util.FlxColor;
import flixel.FlxG;
import flixel.FlxGame;
import flixel.FlxState;
import openfl.Assets;
import openfl.Lib;
import openfl.display.FPS;
import openfl.display.Sprite;
import openfl.events.Event;

class Main extends Sprite
{
	var gameWidth:Int = 1280;
	var gameHeight:Int = 720;
	var initialState:Class<FlxState> = TitleState;
	var zoom:Float = -1;
	var framerate:Int = 120;
	var skipSplash:Bool = true;
	var startFullscreen:Bool = false;

	public static var watermarks:Bool = true;

	// Alias da Psych para setPropertyFromClass('Main', 'fpsVar.visible', ...).
	public static var fpsVar:FPS = null;

	public var game:FlxGame;
	public var fpsCounter:FPS;

	#if android
	private var storageBootFrames:Int = 0;
	private var storageBootStarted:Bool = false;

	private var storageRecheckFrames:Int = 0;
	private var storageRecheckPending:Bool = false;
	#end

	public static function main():Void
	{
		Lib.current.addChild(new Main());
	}

	public function new()
	{
		super();

		if (stage != null)
			init();
		else
			addEventListener(Event.ADDED_TO_STAGE, init);
	}

	private function init(?event:Event):Void
	{
		if (hasEventListener(Event.ADDED_TO_STAGE))
			removeEventListener(Event.ADDED_TO_STAGE, init);

		setupGame();
	}

	private function setupGame():Void
	{
		var stageWidth:Int = Lib.current.stage.stageWidth;
		var stageHeight:Int = Lib.current.stage.stageHeight;

		if (zoom == -1)
		{
			var ratioX:Float = stageWidth / gameWidth;
			var ratioY:Float = stageHeight / gameHeight;

			zoom = Math.min(ratioX, ratioY);
			gameWidth = Math.ceil(stageWidth / zoom);
			gameHeight = Math.ceil(stageHeight / zoom);
		}

		// O jogo nasce antes de qualquer tentativa de storage/permissão.
		game = new FlxGame(
			gameWidth,
			gameHeight,
			initialState,
			#if (flixel < "5.0.0") zoom, #end
			framerate,
			framerate,
			skipSplash,
			startFullscreen
		);

		addChild(game);

		fpsCounter = new FPS(10, 3, 0xFFFFFF);
		fpsVar = fpsCounter;
		addChild(fpsCounter);

		var showFPS:Bool = false;

		try
		{
			if (FlxG.save != null && FlxG.save.data != null)
				showFPS = FlxG.save.data.fps == true;
		}
		catch (e:Dynamic)
		{
			trace('[Main] Não foi possível ler a configuração de FPS: ' + Std.string(e));
		}

		toggleFPS(showFPS);

		#if android
		/*
		 * Não usamos haxe.Timer.delay.
		 * As chamadas do android-manager ficam no loop principal do OpenFL.
		 */
		Lib.current.stage.addEventListener(Event.ENTER_FRAME, startStorageAfterBoot);
		Lib.current.stage.addEventListener(Event.ACTIVATE, onAndroidActivate);
		#else
		try
		{
			AndroidStorage.init();
		}
		catch (e:Dynamic)
		{
			trace(
				'[Main] Storage opcional indisponível; continuando com assets internos: '
				+ Std.string(e)
			);
		}
		#end
	}

	#if android
	/**
	 * Espera o jogo renderizar antes de abrir qualquer solicitação do Android.
	 */
	private function startStorageAfterBoot(event:Event):Void
	{
		if (storageBootStarted)
		{
			Lib.current.stage.removeEventListener(
				Event.ENTER_FRAME,
				startStorageAfterBoot
			);
			return;
		}

		storageBootFrames++;

		// Em 120 FPS são cerca de 0,5 s; em 60 FPS, cerca de 1 s.
		if (storageBootFrames < 60)
			return;

		storageBootStarted = true;

		Lib.current.stage.removeEventListener(
			Event.ENTER_FRAME,
			startStorageAfterBoot
		);

		try
		{
			AndroidStorage.startPermissionFlow();
		}
		catch (e:Dynamic)
		{
			// Mods externos são opcionais. O jogo continua com os assets internos.
			trace(
				'[Main] Mods externos indisponíveis; '
				+ 'continuando com arquivos internos: '
				+ Std.string(e)
			);
		}
	}

	/**
	 * O Android envia ACTIVATE quando o app volta das configurações.
	 * Apenas agenda a verificação; não executa JNI diretamente no callback.
	 */
	private function onAndroidActivate(event:Event):Void
	{
		if (!storageBootStarted || storageRecheckPending)
			return;

		storageRecheckPending = true;
		storageRecheckFrames = 0;

		Lib.current.stage.addEventListener(
			Event.ENTER_FRAME,
			recheckStorageAfterActivate
		);
	}

	/**
	 * Dá alguns frames para a Activity voltar completamente antes da consulta.
	 */
	private function recheckStorageAfterActivate(event:Event):Void
	{
		storageRecheckFrames++;

		if (storageRecheckFrames < 20)
			return;

		Lib.current.stage.removeEventListener(
			Event.ENTER_FRAME,
			recheckStorageAfterActivate
		);

		storageRecheckPending = false;
		storageRecheckFrames = 0;

		try
		{
			AndroidStorage.onAppActivate();
		}
		catch (e:Dynamic)
		{
			trace(
				'[Main] Falha ao rever a permissão dos mods; '
				+ 'continuando com arquivos internos: '
				+ Std.string(e)
			);
		}
	}
	#end

	public function toggleFPS(fpsEnabled:Bool):Void
	{
		if (fpsCounter != null)
			fpsCounter.visible = fpsEnabled;
	}

	public function changeFPSColor(color:FlxColor):Void
	{
		if (fpsCounter != null)
			fpsCounter.textColor = color;
	}

	public function setFPSCap(cap:Float):Void
	{
		if (openfl.Lib.current.stage != null)
			openfl.Lib.current.stage.frameRate = cap;
	}

	public function getFPSCap():Float
	{
		if (openfl.Lib.current.stage == null)
			return framerate;

		return openfl.Lib.current.stage.frameRate;
	}

	public function getFPS():Float
	{
		if (fpsCounter == null)
			return 0;

		return fpsCounter.currentFPS;
	}
}
