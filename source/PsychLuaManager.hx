package;

#if LUA_ALLOWED
import flixel.FlxBasic;
import flixel.FlxCamera;
import flixel.FlxG;
import flixel.FlxSprite;
import flixel.graphics.FlxGraphic;
import flixel.graphics.frames.FlxAtlasFrames;
import flixel.system.FlxSound;
import flixel.tweens.FlxEase;
import flixel.tweens.FlxTween;
import flixel.util.FlxColor;
import flixel.util.FlxTimer;
import openfl.display.BitmapData;
import sys.FileSystem;
import sys.io.File;

using StringTools;

class PsychLuaManager
{
    public static var scripts:Array<PsychLua> = [];
    public static var luaSprites:Map<String, FlxSprite> = new Map<String, FlxSprite>();
    public static var luaTweens:Map<String, FlxTween> = new Map<String, FlxTween>();
    public static var luaTimers:Map<String, FlxTimer> = new Map<String, FlxTimer>();
    public static var luaSounds:Map<String, FlxSound> = new Map<String, FlxSound>();
    static var loadedPaths:Map<String, Bool> = new Map<String, Bool>();

    public static function initialize():Void
    {
        destroy();
        AndroidStorage.init();
        if (!AndroidStorage.available || PlayState.SONG == null) return;

        var song:String = Paths.formatToSongPath(PlayState.SONG.song);
        loadDirectory(AndroidStorage.modPath('scripts'), true);
        loadDirectory(AndroidStorage.modPath('data/' + song), false);

        if (PlayState.curStage != null && PlayState.curStage.length > 0)
            loadFile(AndroidStorage.modPath('stages/' + PlayState.curStage + '.lua'));

        if (PlayState.dad != null) loadFile(AndroidStorage.modPath('characters/' + PlayState.dad.curCharacter + '.lua'));
        if (PlayState.boyfriend != null) loadFile(AndroidStorage.modPath('characters/' + PlayState.boyfriend.curCharacter + '.lua'));
        if (PlayState.gf != null) loadFile(AndroidStorage.modPath('characters/' + PlayState.gf.curCharacter + '.lua'));

        // Carrega apenas arquivos Lua; scripts não utilizados devem ficar fora destas pastas.
        loadDirectory(AndroidStorage.modPath('custom_notetypes'), false);
        loadDirectory(AndroidStorage.modPath('custom_events'), false);

        syncVariables();
    }

    public static function loadFile(path:String):Void
    {
        if (path == null || path.length == 0 || !FileSystem.exists(path) || FileSystem.isDirectory(path)) return;
        if (!path.toLowerCase().endsWith('.lua')) return;
        var normalized:String = PathNormalize.normalize(path);
        if (loadedPaths.exists(normalized)) return;
        loadedPaths.set(normalized, true);

        var script:PsychLua = new PsychLua(path);
        if (!script.closed) scripts.push(script);
    }

    static function loadDirectory(path:String, recursive:Bool):Void
    {
        if (path == null || !FileSystem.exists(path) || !FileSystem.isDirectory(path)) return;
        var entries:Array<String> = FileSystem.readDirectory(path);
        entries.sort(function(a:String, b:String):Int return Reflect.compare(a.toLowerCase(), b.toLowerCase()));
        for (entry in entries)
        {
            var full:String = PathNormalize.join(path, entry);
            if (FileSystem.isDirectory(full))
            {
                if (recursive) loadDirectory(full, true);
            }
            else loadFile(full);
        }
    }

    public static function callOnLuas(functionName:String, args:Array<Dynamic>, ?ignoreStops:Bool = false):Dynamic
    {
        var returnValue:Dynamic = PsychLua.Function_Continue;
        var snapshot:Array<PsychLua> = scripts.copy();
        for (script in snapshot)
        {
            if (script == null || script.closed) continue;
            var result:Dynamic = script.call(functionName, args);
            if (!ignoreStops && result != null && Std.int(result) == PsychLua.Function_Stop)
                returnValue = PsychLua.Function_Stop;
        }
        return returnValue;
    }

    public static function setOnLuas(name:String, value:Dynamic):Void
    {
        for (script in scripts) if (script != null && !script.closed) script.set(name, value);
    }

    public static function syncVariables():Void
    {
        if (PlayState.instance == null) return;
        setOnLuas('curBeat', PlayState.instance.curBeat);
        setOnLuas('curStep', PlayState.instance.curStep);
        setOnLuas('songPosition', Conductor.songPosition);
        setOnLuas('bpm', Conductor.bpm);
        setOnLuas('crochet', Conductor.crochet);
        setOnLuas('stepCrochet', Conductor.stepCrochet);
        setOnLuas('health', PlayState.instance.health);
        setOnLuas('score', PlayState.instance.songScore);
        setOnLuas('misses', PlayState.misses);
        setOnLuas('rating', PlayState.instance.accuracy / 100);
        setOnLuas('songName', PlayState.SONG.song);
        setOnLuas('difficulty', PlayState.storyDifficulty);
        setOnLuas('boyfriendName', PlayState.boyfriend == null ? '' : PlayState.boyfriend.curCharacter);
        setOnLuas('dadName', PlayState.dad == null ? '' : PlayState.dad.curCharacter);
        setOnLuas('gfName', PlayState.gf == null ? '' : PlayState.gf.curCharacter);
        setOnLuas('downscroll', PlayStateChangeables.useDownscroll);
        setOnLuas('middlescroll', false);
        setOnLuas('screenWidth', FlxG.width);
        setOnLuas('screenHeight', FlxG.height);
        setOnLuas('cameraX', FlxG.camera.x);
        setOnLuas('cameraY', FlxG.camera.y);
    }

    public static function resolveObject(name:String):Dynamic
    {
        if (name == null) return null;
        var id:String = name.trim();
        if (luaSprites.exists(id)) return luaSprites.get(id);
        switch (id)
        {
            case 'boyfriend' | 'boyfriendGroup' | 'bf': return PlayState.boyfriend;
            case 'dad' | 'dadGroup' | 'opponent': return PlayState.dad;
            case 'gf' | 'girlfriend' | 'gfGroup': return PlayState.gf;
            case 'camGame': return FlxG.camera;
            case 'camHUD': return PlayState.instance == null ? null : PlayState.instance.camHUD;
            case 'notes': return PlayState.instance == null ? null : PlayState.instance.notes;
            case 'unspawnNotes': return PlayState.instance == null ? null : PlayState.instance.unspawnNotes;
            case 'playerStrums': return PlayState.playerStrums;
            case 'opponentStrums' | 'cpuStrums': return PlayState.cpuStrums;
            case 'strumLineNotes': return PlayState.strumLineNotes;
            default:
                if (PlayState.instance != null)
                {
                    var value:Dynamic = Reflect.getProperty(PlayState.instance, id);
                    if (value != null) return value;
                }
        }
        return null;
    }

    public static function makeSprite(tag:String, image:String, x:Float, y:Float, animated:Bool, ?spriteType:String = 'sparrow'):Bool
    {
        removeSprite(tag, true);
        var sprite:FlxSprite = new FlxSprite(x, y);
        try
        {
            if (image != null && image.trim().length > 0)
            {
                if (animated) sprite.frames = loadAtlas(image, spriteType);
                else loadImageInto(sprite, image);
            }
            luaSprites.set(tag, sprite);
            return true;
        }
        catch (e:Dynamic)
        {
            trace('[PsychLua] makeLuaSprite falhou (' + tag + '): ' + Std.string(e));
            sprite.destroy();
            return false;
        }
    }

    public static function addSprite(tag:String, front:Bool):Bool
    {
        var sprite:FlxSprite = luaSprites.get(tag);
        if (sprite == null || PlayState.instance == null) return false;
        if (front) PlayState.instance.addObject(sprite);
        else
        {
            var index:Int = PlayState.instance.members.indexOf(PlayState.gf);
            if (index < 0) index = 0;
            PlayState.instance.insert(index, sprite);
        }
        return true;
    }

    public static function removeSprite(tag:String, destroy:Bool):Bool
    {
        var sprite:FlxSprite = luaSprites.get(tag);
        if (sprite == null) return false;
        if (PlayState.instance != null) PlayState.instance.removeObject(sprite);
        luaSprites.remove(tag);
        if (destroy) sprite.destroy();
        return true;
    }

    public static function loadGraphic(tag:String, image:String, gridX:Int, gridY:Int):Bool
    {
        var sprite:FlxSprite = luaSprites.get(tag);
        if (sprite == null) return false;
        try
        {
            var external:String = externalImage(image);
            if (FileSystem.exists(external))
            {
                var bitmap:BitmapData = BitmapData.fromFile(external);
                sprite.loadGraphic(FlxGraphic.fromBitmapData(bitmap, false, external), gridX > 0 && gridY > 0, gridX, gridY);
            }
            else sprite.loadGraphic(Paths.image(stripExtension(image)), gridX > 0 && gridY > 0, gridX, gridY);
            return true;
        }
        catch (e:Dynamic)
        {
            trace('[PsychLua] loadGraphic falhou: ' + Std.string(e));
            return false;
        }
    }

    static function loadImageInto(sprite:FlxSprite, image:String):Void
    {
        var external:String = externalImage(image);
        if (FileSystem.exists(external))
        {
            var bitmap:BitmapData = BitmapData.fromFile(external);
            sprite.loadGraphic(FlxGraphic.fromBitmapData(bitmap, false, external));
        }
        else sprite.loadGraphic(Paths.image(stripExtension(image)));
    }

    static function loadAtlas(image:String, spriteType:String):FlxAtlasFrames
    {
        var key:String = stripExtension(image);
        var png:String = externalImage(key);
        if (FileSystem.exists(png))
        {
            var bitmap:BitmapData = BitmapData.fromFile(png);
            var graphic:FlxGraphic = FlxGraphic.fromBitmapData(bitmap, false, png);
            if (spriteType != null && spriteType.toLowerCase() == 'packer')
            {
                var txt:String = AndroidStorage.modPath('images/' + key + '.txt');
                if (!FileSystem.exists(txt)) throw 'TXT Packer não encontrado: ' + txt;
                return FlxAtlasFrames.fromSpriteSheetPacker(graphic, File.getContent(txt));
            }
            var xml:String = AndroidStorage.modPath('images/' + key + '.xml');
            if (!FileSystem.exists(xml)) throw 'XML Sparrow não encontrado: ' + xml;
            return FlxAtlasFrames.fromSparrow(graphic, File.getContent(xml));
        }
        return spriteType != null && spriteType.toLowerCase() == 'packer'
            ? Paths.getPackerAtlas(key)
            : Paths.getSparrowAtlas(key);
    }

    static function externalImage(image:String):String
    {
        return AndroidStorage.modPath('images/' + stripExtension(image) + '.png');
    }

    static function stripExtension(image:String):String
    {
        if (image == null) return '';
        var value:String = image.replace('\\', '/');
        if (value.toLowerCase().endsWith('.png')) value = value.substr(0, value.length - 4);
        while (value.startsWith('/')) value = value.substr(1);
        return value;
    }

    public static function setObjectOrder(tag:String, order:Int):Bool
    {
        var object:FlxBasic = cast resolveObject(tag);
        if (object == null || PlayState.instance == null) return false;
        PlayState.instance.remove(object, false);
        var clamped:Int = Std.int(Math.max(0, Math.min(order, PlayState.instance.members.length)));
        PlayState.instance.insert(clamped, object);
        return true;
    }

    public static function getObjectOrder(tag:String):Int
    {
        var object:FlxBasic = cast resolveObject(tag);
        return object == null || PlayState.instance == null ? -1 : PlayState.instance.members.indexOf(object);
    }

    public static function tweenProperty(tag:String, objectName:String, property:String, value:Float, duration:Float, ease:String):Bool
    {
        var object:Dynamic = resolveObject(objectName);
        if (object == null) return false;
        cancelTween(tag);
        var tween:FlxTween = null;
        var options:Dynamic = {
            ease: easeFromString(ease),
            onComplete: function(_:FlxTween)
            {
                luaTweens.remove(tag);
                callOnLuas('onTweenCompleted', [tag], true);
            }
        };
        switch (property)
        {
            case 'x': tween = FlxTween.tween(object, {x: value}, duration, options);
            case 'y': tween = FlxTween.tween(object, {y: value}, duration, options);
            case 'alpha': tween = FlxTween.tween(object, {alpha: value}, duration, options);
            case 'angle': tween = FlxTween.tween(object, {angle: value}, duration, options);
        }
        if (tween == null) return false;
        luaTweens.set(tag, tween);
        return true;
    }

    public static function tweenCameraZoom(tag:String, camera:String, value:Float, duration:Float, ease:String):Bool
    {
        var target:FlxCamera = getCamera(camera);
        if (target == null) return false;
        cancelTween(tag);
        var tween:FlxTween = FlxTween.tween(target, {zoom: value}, duration, {
            ease: easeFromString(ease),
            onComplete: function(_:FlxTween)
            {
                luaTweens.remove(tag);
                callOnLuas('onTweenCompleted', [tag], true);
            }
        });
        luaTweens.set(tag, tween);
        return true;
    }

    public static function cancelTween(tag:String):Bool
    {
        var tween:FlxTween = luaTweens.get(tag);
        if (tween == null) return false;
        tween.cancel();
        luaTweens.remove(tag);
        return true;
    }

    public static function runTimer(tag:String, time:Float, loops:Int):Bool
    {
        cancelTimer(tag);
        if (loops < 1) loops = 1;
        var timer:FlxTimer = new FlxTimer().start(Math.max(0.001, time), function(current:FlxTimer)
        {
            callOnLuas('onTimerCompleted', [tag, current.elapsedLoops, current.loopsLeft], true);
            if (current.loopsLeft == 0) luaTimers.remove(tag);
        }, loops);
        luaTimers.set(tag, timer);
        return true;
    }

    public static function cancelTimer(tag:String):Bool
    {
        var timer:FlxTimer = luaTimers.get(tag);
        if (timer == null) return false;
        timer.cancel();
        luaTimers.remove(tag);
        return true;
    }

    public static function playSound(sound:String, volume:Float, tag:String):Bool
    {
        try
        {
            var audio:FlxSound = new FlxSound().loadEmbedded(Paths.sound(sound), false, false);
            audio.volume = volume;
            FlxG.sound.list.add(audio);
            audio.play();
            if (tag != null && tag.length > 0)
            {
                stopSound(tag);
                luaSounds.set(tag, audio);
                audio.onComplete = function()
                {
                    luaSounds.remove(tag);
                    callOnLuas('onSoundFinished', [tag], true);
                };
            }
            return true;
        }
        catch (e:Dynamic)
        {
            trace('[PsychLua] playSound falhou: ' + Std.string(e));
            return false;
        }
    }

    public static function stopSound(tag:String):Bool
    {
        var sound:FlxSound = luaSounds.get(tag);
        if (sound == null) return false;
        sound.stop();
        sound.destroy();
        luaSounds.remove(tag);
        return true;
    }

    public static function getCamera(name:String):FlxCamera
    {
        switch (name == null ? '' : name.toLowerCase().trim())
        {
            case 'hud' | 'camhud': return PlayState.instance == null ? null : PlayState.instance.camHUD;
            default: return FlxG.camera;
        }
    }

    public static function colorFromString(value:String):FlxColor
    {
        if (value == null || value.trim().length == 0) return FlxColor.WHITE;
        var text:String = value.trim().replace('#', '').replace('0x', '');
        var named:FlxColor = FlxColor.fromString(value);
        if (named != null) return named;
        if (text.length == 6) text = 'FF' + text;
        var parsed:Null<Int> = Std.parseInt('0x' + text);
        return parsed == null ? FlxColor.WHITE : parsed;
    }

    static function easeFromString(name:String):Dynamic
    {
        switch (name == null ? 'linear' : name.toLowerCase().trim())
        {
            case 'quadin': return FlxEase.quadIn;
            case 'quadout': return FlxEase.quadOut;
            case 'quadinout': return FlxEase.quadInOut;
            case 'cubein': return FlxEase.cubeIn;
            case 'cubeout': return FlxEase.cubeOut;
            case 'cubeinout': return FlxEase.cubeInOut;
            case 'sinein': return FlxEase.sineIn;
            case 'sineout': return FlxEase.sineOut;
            case 'sineinout': return FlxEase.sineInOut;
            case 'circin': return FlxEase.circIn;
            case 'circout': return FlxEase.circOut;
            case 'circinout': return FlxEase.circInOut;
            case 'backin': return FlxEase.backIn;
            case 'backout': return FlxEase.backOut;
            default: return FlxEase.linear;
        }
    }

    public static function destroy():Void
    {
        if (scripts.length > 0) callOnLuas('onDestroy', [], true);
        for (script in scripts) if (script != null) script.close();
        scripts = [];
        loadedPaths = new Map<String, Bool>();

        for (tag in luaTweens.keys()) cancelTween(tag);
        for (tag in luaTimers.keys()) cancelTimer(tag);
        for (tag in luaSounds.keys()) stopSound(tag);
        for (tag in luaSprites.keys()) removeSprite(tag, true);
    }
}

class PathNormalize
{
    public static function normalize(path:String):String return path.replace('\\', '/').toLowerCase();
    public static function join(a:String, b:String):String
    {
        var left:String = a.replace('\\', '/');
        var right:String = b.replace('\\', '/');
        while (left.endsWith('/')) left = left.substr(0, left.length - 1);
        while (right.startsWith('/')) right = right.substr(1);
        return left + '/' + right;
    }
}
#else
class PsychLuaManager
{
    public static function initialize():Void {}
    public static function callOnLuas(functionName:String, args:Array<Dynamic>, ?ignoreStops:Bool = false):Dynamic return 0;
    public static function setOnLuas(name:String, value:Dynamic):Void {}
    public static function syncVariables():Void {}
    public static function destroy():Void {}
}
#end
