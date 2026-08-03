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
	public static var watermarks = true;

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
		// O jogo nasce primeiro. Storage/permissoes nunca devem bloquear o boot.
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
		addChild(fpsCounter);
		toggleFPS(FlxG.save.data.fps);

		#if android
		// Refaz a verificacao quando o usuario volta das configuracoes.
		Lib.current.stage.addEventListener(Event.ACTIVATE, onAndroidActivate);

		// A tela do jogo ja esta viva quando o pedido de permissao aparece.
		haxe.Timer.delay(function():Void
		{
			try
			{
				AndroidStorage.startPermissionFlow();
			}
			catch (e:Dynamic)
			{
				trace('[Main] Storage externo falhou, continuando sem mods: ' + Std.string(e));
			}
		}, 1000);
		#else
		// Em desktop a tentativa tambem e opcional e silenciosa.
		try
		{
			AndroidStorage.init();
		}
		catch (e:Dynamic)
		{
			trace('[Main] Storage opcional indisponivel: ' + Std.string(e));
		}
		#end
	}

	#if android
	private function onAndroidActivate(event:Event):Void
	{
		haxe.Timer.delay(function():Void
		{
			try
			{
				AndroidStorage.onAppActivate();
			}
			catch (e:Dynamic)
			{
				trace('[Main] Falha ao rever permissao; o jogo continuara sem mods externos: ' + Std.string(e));
			}
		}, 300);
	}
	#end

	var game:FlxGame;
	var fpsCounter:FPS;

	public function toggleFPS(fpsEnabled:Bool):Void
	{
		fpsCounter.visible = fpsEnabled;
	}

	public function changeFPSColor(color:FlxColor):Void
	{
		fpsCounter.textColor = color;
	}

	public function setFPSCap(cap:Float):Void
	{
		openfl.Lib.current.stage.frameRate = cap;
	}

	public function getFPSCap():Float
	{
		return openfl.Lib.current.stage.frameRate;
	}

	public function getFPS():Float
	{
		return fpsCounter.currentFPS;
	}
}
