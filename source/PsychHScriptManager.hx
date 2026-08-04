package;

#if HSCRIPT_ALLOWED
import flixel.FlxBasic;
import flixel.FlxCamera;
import flixel.FlxG;
import flixel.FlxObject;
import flixel.FlxSprite;
import flixel.group.FlxGroup;
import flixel.group.FlxGroup.FlxTypedGroup;
import flixel.math.FlxMath;
import flixel.math.FlxPoint;
import flixel.system.FlxSound;
import flixel.text.FlxText;
import flixel.tweens.FlxEase;
import flixel.tweens.FlxTween;
import flixel.ui.FlxBar;
import flixel.util.FlxColor;
import flixel.util.FlxTimer;
import haxe.Json;
import hscript.Interp;
import hscript.Parser;
import sys.FileSystem;
import sys.io.File;

using StringTools;

/**
 * HScript leve e cross-platform para Android/PC.
 *
 * Usa a mesma organização da Psych 0.7.3:
 * mods/scripts, data/<song>, stages, characters, custom_events e
 * custom_notetypes. Os arquivos são scripts de topo (funções onCreate,
 * onUpdate etc.), não classes Haxe compiladas.
 */
class PsychHScriptManager
{
    public static var scripts:Array<PsychHScript> = [];
    static var loadedLogicalPaths:Map<String, Bool> = new Map<String, Bool>();
    static var currentScript:PsychHScript = null;
    static var sharedVariables:Map<String, Dynamic> = new Map<String, Dynamic>();

    public static function initialize():Void
    {
        destroy();
        if (PlayState.SONG == null)
            return;

        try
        {
            loadStructure();
            syncVariables();
            if (scripts.length > 0)
                trace('[PsychHScript] Scripts carregados: ' + scripts.length);
        }
        catch (e:Dynamic)
        {
            KadeshScriptDebug.report('HSCRIPT', '<manager>', Std.string(e), 'initialize');
        }
    }

    static function loadStructure():Void
    {
        var song:String = Paths.formatToSongPath(PlayState.SONG.song);

        loadDirectory('scripts', true);

        if (PlayState.curStage != null && PlayState.curStage.trim().length > 0)
            loadFile('stages/' + PlayState.curStage + '.hx');

        if (PlayState.dad != null)
            loadFile('characters/' + PlayState.dad.curCharacter + '.hx');
        if (PlayState.boyfriend != null)
            loadFile('characters/' + PlayState.boyfriend.curCharacter + '.hx');
        if (PlayState.gf != null)
            loadFile('characters/' + PlayState.gf.curCharacter + '.hx');

        loadDirectory('data/' + song, false);

        for (noteType in usedNoteTypes())
            loadFile('custom_notetypes/' + noteType + '.hx');

        for (eventName in usedEventNames())
            loadFile('custom_events/' + eventName + '.hx');
    }

    static function loadFile(relative:String):Void
    {
        var logical:String = KadeshModPaths.normalize(relative);
        if (loadedLogicalPaths.exists(logical.toLowerCase()))
            return;

        var path:Null<String> = KadeshModPaths.find(relative);
        if (path == null)
            return;

        loadedLogicalPaths.set(logical.toLowerCase(), true);
        createScript(path, logical);
    }

    static function loadDirectory(relative:String, recursive:Bool):Void
    {
        for (entry in KadeshModPaths.list(relative, '.hx', recursive))
        {
            var key:String = KadeshModPaths.normalize(entry.logical).toLowerCase();
            if (loadedLogicalPaths.exists(key))
                continue;
            loadedLogicalPaths.set(key, true);
            createScript(entry.path, entry.logical);
        }
    }

    static function createScript(path:String, logical:String):Void
    {
        var parser:Parser = new Parser();
        parser.allowTypes = true;
        parser.allowJSON = true;
        parser.allowMetadata = true;
        parser.preprocesorValues.set('HSCRIPT_ALLOWED', true);
        #if android
        parser.preprocesorValues.set('android', true);
        parser.preprocesorValues.set('mobile', true);
        #end
        #if windows
        parser.preprocesorValues.set('windows', true);
        parser.preprocesorValues.set('desktop', true);
        #end
        #if linux
        parser.preprocesorValues.set('linux', true);
        parser.preprocesorValues.set('desktop', true);
        #end

        var source:String;
        try
        {
            source = File.getContent(path);
        }
        catch (e:Dynamic)
        {
            KadeshScriptDebug.report('HSCRIPT', path, Std.string(e), 'read');
            return;
        }

        source = preprocess(source);
        var expression:Dynamic;
        try
        {
            expression = parser.parseString(source, path);
        }
        catch (e:Dynamic)
        {
            var line:Int = parser.line;
            KadeshScriptDebug.report('HSCRIPT', path, path + ':' + line + ': ' + Std.string(e), 'parse');
            return;
        }

        var interp:Interp = new Interp();
        configureInterp(interp, path, logical);
        var record:PsychHScript = new PsychHScript(path, logical, interp);
        currentScript = record;

        try
        {
            interp.execute(expression);
        }
        catch (e:Dynamic)
        {
            currentScript = null;
            KadeshScriptDebug.report('HSCRIPT', path, Std.string(e), 'execute');
            return;
        }

        currentScript = null;
        scripts.push(record);
        callScript(record, 'onCreate', []);
    }

    /** Remove package/import/using preservando a quantidade de linhas. */
    static function preprocess(source:String):String
    {
        var output:Array<String> = [];
        var lines:Array<String> = source.replace('\r\n', '\n').replace('\r', '\n').split('\n');

        for (line in lines)
        {
            var trim:String = line.trim();
            if (trim.startsWith('package ') || trim == 'package;'
                || trim.startsWith('import ') || trim.startsWith('using '))
            {
                output.push('');
                continue;
            }

            if (trim.startsWith('class ') || trim.startsWith('enum ') || trim.startsWith('typedef '))
            {
                output.push('throw "Softcode usa código de topo como na Psych 0.7.3; deixe var/function fora de class.";');
                continue;
            }

            // Scripts copiados de source code costumam deixar modificadores
            // que só fazem sentido dentro de uma classe compilada. No softcode
            // eles são removidos, preservando a linha para o relatório de erro.
            var indent:String = line.substr(0, line.length - StringTools.ltrim(line).length);
            var code:String = StringTools.ltrim(line);
            for (modifier in ['public ', 'private ', 'protected ', 'override ', 'static '])
            {
                while (code.startsWith(modifier))
                    code = code.substr(modifier.length);
            }
            output.push(indent + code);
        }
        return output.join('\n');
    }

    /**
     * FlxColor é um abstract sobre Int no HaxeFlixel 5.2.2.
     * Abstracts não podem ser passados ao HScript como valor de classe.
     *
     * Este objeto mantém a sintaxe usada em scripts:
     *
     * FlxColor.WHITE
     * FlxColor.fromRGB(255, 0, 0)
     * FlxColor.fromString("#FF0000")
     */
    static function createFlxColorAPI():Dynamic
    {
        return {
            TRANSPARENT: cast FlxColor.TRANSPARENT,
            WHITE: cast FlxColor.WHITE,
            GRAY: cast FlxColor.GRAY,
            BLACK: cast FlxColor.BLACK,
            GREEN: cast FlxColor.GREEN,
            LIME: cast FlxColor.LIME,
            YELLOW: cast FlxColor.YELLOW,
            ORANGE: cast FlxColor.ORANGE,
            RED: cast FlxColor.RED,
            PURPLE: cast FlxColor.PURPLE,
            BLUE: cast FlxColor.BLUE,
            BROWN: cast FlxColor.BROWN,
            PINK: cast FlxColor.PINK,
            MAGENTA: cast FlxColor.MAGENTA,
            CYAN: cast FlxColor.CYAN,

            fromInt: function(value:Int):Int
            {
                return cast FlxColor.fromInt(value);
            },

            fromRGB: function(
                red:Int,
                green:Int,
                blue:Int,
                ?alpha:Int = 255
            ):Int
            {
                return cast FlxColor.fromRGB(
                    red,
                    green,
                    blue,
                    alpha
                );
            },

            fromRGBFloat: function(
                red:Float,
                green:Float,
                blue:Float,
                ?alpha:Float = 1
            ):Int
            {
                return cast FlxColor.fromRGBFloat(
                    red,
                    green,
                    blue,
                    alpha
                );
            },

            fromCMYK: function(
                cyan:Float,
                magenta:Float,
                yellow:Float,
                black:Float,
                ?alpha:Float = 1
            ):Int
            {
                return cast FlxColor.fromCMYK(
                    cyan,
                    magenta,
                    yellow,
                    black,
                    alpha
                );
            },

            fromHSB: function(
                hue:Float,
                saturation:Float,
                brightness:Float,
                ?alpha:Float = 1
            ):Int
            {
                return cast FlxColor.fromHSB(
                    hue,
                    saturation,
                    brightness,
                    alpha
                );
            },

            fromHSL: function(
                hue:Float,
                saturation:Float,
                lightness:Float,
                ?alpha:Float = 1
            ):Int
            {
                return cast FlxColor.fromHSL(
                    hue,
                    saturation,
                    lightness,
                    alpha
                );
            },

            fromString: function(value:String):Int
            {
                return cast PsychLuaManager.colorFromString(value);
            },

            interpolate: function(
                color1:Int,
                color2:Int,
                ?factor:Float = 0.5
            ):Int
            {
                return cast FlxColor.interpolate(
                    color1,
                    color2,
                    factor
                );
            }
        };
    }

    static function configureInterp(interp:Interp, path:String, logical:String):Void
    {
        var variables = interp.variables;

        // Classes e valores comuns.
        variables.set('Math', Math);
        variables.set('Std', Std);
        variables.set('Reflect', Reflect);
        variables.set('Type', Type);
        variables.set('StringTools', StringTools);
        variables.set('Json', Json);
        variables.set('FlxG', FlxG);
        variables.set('FlxBasic', FlxBasic);
        variables.set('FlxCamera', FlxCamera);
        variables.set('FlxObject', FlxObject);
        variables.set('FlxSprite', FlxSprite);
        variables.set('FlxText', FlxText);
        variables.set('FlxGroup', FlxGroup);
        variables.set('FlxTypedGroup', FlxTypedGroup);
        variables.set('FlxPoint', FlxPoint);
        variables.set('FlxMath', FlxMath);
        variables.set('FlxSound', FlxSound);
        variables.set('FlxBar', FlxBar);
        variables.set('FlxTimer', FlxTimer);
        variables.set('FlxTween', FlxTween);
        variables.set('FlxEase', FlxEase);
        variables.set('FlxColor', createFlxColorAPI());
        variables.set('Conductor', Conductor);
        variables.set('Paths', Paths);
        variables.set('PlayState', PlayState);
        variables.set('Character', Character);
        variables.set('Boyfriend', Boyfriend);
        variables.set('Note', Note);
        variables.set('HealthIcon', HealthIcon);
        variables.set('AndroidStorage', AndroidStorage);
        variables.set('KadeshModAssets', KadeshModAssets);
        variables.set('KadeshModPaths', KadeshModPaths);
        variables.set('KadeshStageData', KadeshStageData);
        variables.set('KadeshBGSprite', KadeshBGSprite);
        variables.set('BGSprite', KadeshBGSprite);

        variables.set('game', PlayState.instance);
        variables.set('boyfriend', PlayState.boyfriend);
        variables.set('dad', PlayState.dad);
        variables.set('gf', PlayState.gf);
        variables.set('camGame', FlxG.camera);
        variables.set('camHUD', PlayState.instance == null ? null : PlayState.instance.camHUD);
        variables.set('stage', KadeshStageData.current);
        variables.set('members', PlayState.instance == null ? null : PlayState.instance.members);

        // API de softcode no estilo da Psych 0.7.3: o script pode instanciar
        // FlxSprite/FlxText/FlxTimer e adicionar objetos diretamente ao state.
        variables.set('add', function(object:Dynamic):Dynamic
        {
            if (PlayState.instance == null || object == null) return object;
            PlayState.instance.add(cast object);
            return object;
        });
        variables.set('insert', function(position:Int, object:Dynamic):Dynamic
        {
            if (PlayState.instance == null || object == null) return object;
            var index:Int = Std.int(Math.max(0, Math.min(position, PlayState.instance.members.length)));
            PlayState.instance.insert(index, cast object);
            return object;
        });
        variables.set('remove', function(object:Dynamic, ?splice:Bool = false):Dynamic
        {
            if (PlayState.instance == null || object == null) return object;
            PlayState.instance.remove(cast object, splice);
            return object;
        });
        variables.set('addBehindGF', function(object:Dynamic):Dynamic
            return insertBehindCharacter(object, PlayState.gf));
        variables.set('addBehindDad', function(object:Dynamic):Dynamic
            return insertBehindCharacter(object, PlayState.dad));
        variables.set('addBehindBF', function(object:Dynamic):Dynamic
            return insertBehindCharacter(object, PlayState.boyfriend));
        variables.set('getObject', function(name:String):Dynamic
            return PsychLuaManager.resolveObject(name));
        variables.set('getVar', function(name:String):Dynamic
            return sharedVariables.get(name));
        variables.set('setVar', function(name:String, value:Dynamic):Dynamic
        {
            sharedVariables.set(name, value);
            return value;
        });
        variables.set('removeVar', function(name:String):Bool
            return sharedVariables.remove(name));
        variables.set('addHaxeLibrary', function(className:String, ?packageName:String = ''):Bool
        {
            var fullName:String = packageName == null || packageName.length == 0
                ? className
                : packageName + '.' + className;
            var resolved:Dynamic = Type.resolveClass(fullName);
            if (resolved == null) resolved = Type.resolveEnum(fullName);
            if (resolved == null || currentScript == null || currentScript.interp == null)
                return false;
            currentScript.interp.variables.set(className, resolved);
            return true;
        });

        // Em characters/<nome>.hx, "character" aponta para a instância que
        // usa aquele nome. Os aliases dad/boyfriend/gf continuam disponíveis.
        var scriptCharacter:Character = resolveScriptCharacter(logical);
        variables.set('character', scriptCharacter);
        variables.set('characterName', scriptCharacter == null ? '' : scriptCharacter.curCharacter);

        variables.set('scriptName', fileName(path));
        variables.set('scriptPath', path);
        variables.set('Function_Continue', PsychHScript.Function_Continue);
        variables.set('Function_Stop', PsychHScript.Function_Stop);
        variables.set('Function_StopHScript', PsychHScript.Function_StopHScript);

        variables.set('debugPrint', function(value:Dynamic, ?color:String = 'WHITE'):Void
        {
            KadeshScriptDebug.info('[HScript][' + fileName(path) + '] ' + Std.string(value), PsychLuaManager.colorFromString(color));
        });

        variables.set('getProperty', function(name:String):Dynamic
            return PsychLuaManager.scriptGetProperty(name));
        variables.set('setProperty', function(name:String, value:Dynamic):Dynamic
            return PsychLuaManager.scriptSetProperty(name, value));
        variables.set('getPropertyFromGroup', function(group:String, index:Int, field:String):Dynamic
            return PsychLuaManager.scriptGetPropertyFromGroup(group, index, field));
        variables.set('setPropertyFromGroup', function(group:String, index:Int, field:String, value:Dynamic):Dynamic
            return PsychLuaManager.scriptSetPropertyFromGroup(group, index, field, value));
        variables.set('getPropertyFromClass', function(className:String, field:String):Dynamic
            return PsychLuaManager.scriptGetPropertyFromClass(className, field));
        variables.set('setPropertyFromClass', function(className:String, field:String, value:Dynamic):Dynamic
            return PsychLuaManager.scriptSetPropertyFromClass(className, field, value));
        variables.set('getPropertyFromMap', function(mapName:String, key:Dynamic):Dynamic
            return PsychLuaManager.scriptGetPropertyFromMap(mapName, key));
        variables.set('setPropertyFromMap', function(mapName:String, key:Dynamic, value:Dynamic):Dynamic
            return PsychLuaManager.scriptSetPropertyFromMap(mapName, key, value));
        variables.set('removeFromGroup', function(group:String, index:Int, ?dontDestroy:Bool = false):Bool
            return PsychLuaManager.scriptRemoveFromGroup(group, index, dontDestroy));

        variables.set('makeLuaSprite', function(tag:String, image:String, ?x:Float = 0, ?y:Float = 0):Bool
            return PsychLuaManager.makeSprite(tag, image, x, y, false));
        variables.set('makeAnimatedLuaSprite', function(tag:String, image:String, ?x:Float = 0, ?y:Float = 0, ?atlas:String = 'sparrow'):Bool
            return PsychLuaManager.makeSprite(tag, image, x, y, true, atlas));
        variables.set('addLuaSprite', function(tag:String, ?front:Bool = false):Bool
            return PsychLuaManager.addSprite(tag, front));
        variables.set('removeLuaSprite', function(tag:String, ?destroy:Bool = true):Bool
            return PsychLuaManager.removeSprite(tag, destroy));
        variables.set('luaSpriteExists', function(tag:String):Bool
            return PsychLuaManager.scriptLuaSpriteExists(tag));
        variables.set('makeGraphic', function(tag:String, width:Int, height:Int, color:String):Bool
            return PsychLuaManager.scriptMakeGraphic(tag, width, height, color));
        variables.set('loadGraphic', function(tag:String, image:String, ?gridX:Int = 0, ?gridY:Int = 0):Bool
            return PsychLuaManager.loadGraphic(tag, image, gridX, gridY));
        variables.set('addAnimationByPrefix', function(tag:String, name:String, prefix:String, ?fps:Int = 24, ?loop:Bool = false):Bool
            return PsychLuaManager.scriptAddAnimationByPrefix(tag, name, prefix, fps, loop));
        variables.set('addAnimationByIndices', function(tag:String, name:String, prefix:String, indices:Dynamic, ?fps:Int = 24, ?loop:Bool = false):Bool
            return PsychLuaManager.scriptAddAnimationByIndices(tag, name, prefix, indices, fps, loop));
        variables.set('objectPlayAnimation', function(tag:String, name:String, ?force:Bool = false, ?reverse:Bool = false, ?frame:Int = 0):Bool
            return PsychLuaManager.scriptPlayAnimation(tag, name, force, reverse, frame));
        variables.set('characterPlayAnim', function(tag:String, name:String, ?force:Bool = false):Bool
            return PsychLuaManager.scriptPlayAnimation(tag, name, force, false, 0));
        variables.set('setObjectCamera', function(tag:String, camera:String):Bool
            return PsychLuaManager.scriptSetObjectCamera(tag, camera));
        variables.set('setScrollFactor', function(tag:String, x:Float, y:Float):Bool
            return PsychLuaManager.scriptSetScrollFactor(tag, x, y));
        variables.set('setLuaSpriteScrollFactor', function(tag:String, x:Float, y:Float):Bool
            return PsychLuaManager.scriptSetScrollFactor(tag, x, y));
        variables.set('scaleObject', function(tag:String, x:Float, y:Float, ?updateHitbox:Bool = true):Bool
            return PsychLuaManager.scriptScaleObject(tag, x, y, updateHitbox));
        variables.set('setGraphicSize', function(tag:String, width:Int, ?height:Int = 0, ?updateHitbox:Bool = true):Bool
            return PsychLuaManager.scriptSetGraphicSize(tag, width, height, updateHitbox));
        variables.set('updateHitbox', function(tag:String):Bool
            return PsychLuaManager.scriptUpdateHitbox(tag));
        variables.set('screenCenter', function(tag:String, ?axes:String = 'xy'):Bool
            return PsychLuaManager.scriptScreenCenter(tag, axes));
        variables.set('setBlendMode', function(tag:String, blend:String):Bool
            return PsychLuaManager.scriptSetBlendMode(tag, blend));
        variables.set('setObjectOrder', function(tag:String, order:Int):Bool
            return PsychLuaManager.setObjectOrder(tag, order));
        variables.set('getObjectOrder', function(tag:String):Int
            return PsychLuaManager.getObjectOrder(tag));

        variables.set('makeLuaText', function(tag:String, text:String, ?width:Float = 0, ?x:Float = 0, ?y:Float = 0):Bool
            return PsychLuaManager.scriptMakeText(tag, text, width, x, y));
        variables.set('addLuaText', function(tag:String, ?front:Bool = false):Bool
            return PsychLuaManager.scriptAddText(tag, front));
        variables.set('removeLuaText', function(tag:String, ?destroy:Bool = true):Bool
            return PsychLuaManager.scriptRemoveText(tag, destroy));
        variables.set('luaTextExists', function(tag:String):Bool
            return PsychLuaManager.scriptLuaTextExists(tag));
        variables.set('setTextString', function(tag:String, text:String):Bool
            return PsychLuaManager.scriptSetTextString(tag, text));
        variables.set('setTextSize', function(tag:String, size:Int):Bool
            return PsychLuaManager.scriptSetTextSize(tag, size));
        variables.set('setTextColor', function(tag:String, color:String):Bool
            return PsychLuaManager.scriptSetTextColor(tag, color));

        variables.set('doTweenX', function(tag:String, object:String, value:Float, duration:Float, ?ease:String = 'linear'):Bool
            return PsychLuaManager.tweenProperty(tag, object, 'x', value, duration, ease));
        variables.set('doTweenY', function(tag:String, object:String, value:Float, duration:Float, ?ease:String = 'linear'):Bool
            return PsychLuaManager.tweenProperty(tag, object, 'y', value, duration, ease));
        variables.set('doTweenAlpha', function(tag:String, object:String, value:Float, duration:Float, ?ease:String = 'linear'):Bool
            return PsychLuaManager.tweenProperty(tag, object, 'alpha', value, duration, ease));
        variables.set('doTweenAngle', function(tag:String, object:String, value:Float, duration:Float, ?ease:String = 'linear'):Bool
            return PsychLuaManager.tweenProperty(tag, object, 'angle', value, duration, ease));
        variables.set('doTweenColor', function(tag:String, object:String, color:String, duration:Float, ?ease:String = 'linear'):Bool
            return PsychLuaManager.tweenColor(tag, object, color, duration, ease));
        variables.set('doTweenZoom', function(tag:String, camera:String, value:Float, duration:Float, ?ease:String = 'linear'):Bool
            return PsychLuaManager.tweenCameraZoom(tag, camera, value, duration, ease));
        variables.set('cancelTween', function(tag:String):Bool return PsychLuaManager.cancelTween(tag));
        variables.set('runTimer', function(tag:String, time:Float, ?loops:Int = 1):Bool return PsychLuaManager.runTimer(tag, time, loops));
        variables.set('cancelTimer', function(tag:String):Bool return PsychLuaManager.cancelTimer(tag));
        variables.set('playSound', function(sound:String, ?volume:Float = 1, ?tag:String = null):Bool return PsychLuaManager.playSound(sound, volume, tag));
        variables.set('stopSound', function(tag:String):Bool return PsychLuaManager.stopSound(tag));
        variables.set('cameraFlash', function(camera:String, color:String, duration:Float, ?forced:Bool = false):Bool
            return PsychLuaManager.scriptCameraFlash(camera, color, duration, forced));
        variables.set('cameraShake', function(camera:String, intensity:Float, duration:Float):Bool
            return PsychLuaManager.scriptCameraShake(camera, intensity, duration));
        variables.set('triggerEvent', function(name:String, ?value1:String = '', ?value2:String = ''):Bool
            return PsychLuaManager.scriptTriggerEvent(name, value1, value2));
        variables.set('triggerEventNote', function(name:String, ?value1:String = '', ?value2:String = ''):Bool
            return PsychLuaManager.scriptTriggerEvent(name, value1, value2));
        variables.set('getSongPosition', function():Float return Conductor.songPosition);
        variables.set('getColorFromHex', function(value:String):FlxColor return PsychLuaManager.colorFromString(value));

        // Criação/ajuste de personagens em characters/<nome>.hx.
        variables.set('loadCharacterAtlas', function(target:String, image:String, ?atlas:String = 'sparrow'):Bool
            return loadCharacterAtlas(target, image, atlas));
        variables.set('addCharacterAnimation', function(target:String, name:String, prefix:String, ?fps:Int = 24, ?loop:Bool = false, ?offsetX:Float = 0, ?offsetY:Float = 0):Bool
            return addCharacterAnimation(target, name, prefix, fps, loop, offsetX, offsetY));
        variables.set('setCharacterIcon', function(target:String, icon:String):Bool
            return setCharacterIcon(target, icon));
        variables.set('setCharacterIdle', function(target:String, animation:String):Bool
            return setCharacterIdle(target, animation));
        variables.set('close', function():Void
        {
            if (currentScript != null) currentScript.close();
        });
    }

    static function insertBehindCharacter(object:Dynamic, character:Character):Dynamic
    {
        if (PlayState.instance == null || object == null)
            return object;

        var index:Int = character == null
            ? PlayState.instance.members.length
            : PlayState.instance.members.indexOf(character);
        if (index < 0) index = PlayState.instance.members.length;
        PlayState.instance.insert(index, cast object);
        return object;
    }

    static function resolveScriptCharacter(logical:String):Character
    {
        if (logical == null)
            return null;

        var fixed:String = KadeshModPaths.normalize(logical).toLowerCase();
        if (!fixed.startsWith('characters/') || !fixed.endsWith('.hx'))
            return null;

        var file:String = fixed.substr('characters/'.length);
        file = file.substr(0, file.length - 3);

        if (PlayState.dad != null && PlayState.dad.curCharacter.toLowerCase() == file)
            return PlayState.dad;
        if (PlayState.boyfriend != null && PlayState.boyfriend.curCharacter.toLowerCase() == file)
            return PlayState.boyfriend;
        if (PlayState.gf != null && PlayState.gf.curCharacter.toLowerCase() == file)
            return PlayState.gf;
        return null;
    }

    static function loadCharacterAtlas(target:String, image:String, atlas:String):Bool
    {
        var character:Dynamic = PsychLuaManager.resolveObject(target);
        if (character == null || !Std.isOfType(character, Character))
            return false;

        try
        {
            (cast character:Character).frames = KadeshModAssets.loadAtlas(image, atlas);
            return true;
        }
        catch (e:Dynamic)
        {
            KadeshScriptDebug.report('HSCRIPT CHARACTER', currentScript == null ? '' : currentScript.scriptName, Std.string(e), 'loadCharacterAtlas');
            return false;
        }
    }

    static function addCharacterAnimation(target:String, name:String, prefix:String, fps:Int, loop:Bool, offsetX:Float, offsetY:Float):Bool
    {
        var character:Dynamic = PsychLuaManager.resolveObject(target);
        if (character == null || !Std.isOfType(character, Character))
            return false;
        var casted:Character = cast character;
        casted.animation.addByPrefix(name, prefix, fps, loop);
        casted.addOffset(name, offsetX, offsetY);
        return true;
    }

    static function setCharacterIcon(target:String, icon:String):Bool
    {
        var character:Dynamic = PsychLuaManager.resolveObject(target);
        if (character == null || !Std.isOfType(character, Character))
            return false;
        (cast character:Character).healthIcon = icon;
        return true;
    }

    static function setCharacterIdle(target:String, animation:String):Bool
    {
        var character:Dynamic = PsychLuaManager.resolveObject(target);
        if (character == null || !Std.isOfType(character, Character))
            return false;
        (cast character:Character).jsonIdleAnimation = animation;
        return true;
    }

    public static function callOnHScripts(functionName:String, args:Array<Dynamic>, ?ignoreStops:Bool = false):Dynamic
    {
        var result:Dynamic = PsychHScript.Function_Continue;
        for (script in scripts.copy())
        {
            if (script == null || script.closed) continue;
            var value:Dynamic = callScript(script, functionName, args);
            if (!ignoreStops && isStop(value))
                result = PsychHScript.Function_Stop;
        }
        return result;
    }

    static function callScript(script:PsychHScript, functionName:String, args:Array<Dynamic>):Dynamic
    {
        currentScript = script;
        var result:Dynamic = script.call(functionName, args);
        currentScript = null;
        return result;
    }

    static function isStop(value:Dynamic):Bool
    {
        if (value == null || Std.isOfType(value, Bool)) return false;
        var parsed:Null<Int> = Std.parseInt(Std.string(value));
        return parsed != null && parsed == PsychHScript.Function_Stop;
    }

    public static function setOnHScripts(name:String, value:Dynamic):Void
    {
        for (script in scripts)
            if (script != null && !script.closed)
                script.set(name, value);
    }

    public static function syncVariables():Void
    {
        if (PlayState.instance == null)
            return;

        setOnHScripts('curBeat', PlayState.instance.curBeat);
        setOnHScripts('curStep', PlayState.instance.curStep);
        setOnHScripts('songPosition', Conductor.songPosition);
        setOnHScripts('curBpm', Conductor.bpm);
        setOnHScripts('bpm', Conductor.bpm);
        setOnHScripts('crochet', Conductor.crochet);
        setOnHScripts('stepCrochet', Conductor.stepCrochet);
        setOnHScripts('health', PlayState.instance.health);
        setOnHScripts('score', PlayState.instance.songScore);
        setOnHScripts('misses', PlayState.misses);
        setOnHScripts('rating', PlayState.instance.accuracy / 100);
        setOnHScripts('songName', PlayState.SONG.song);
        setOnHScripts('difficulty', PlayState.storyDifficulty);
        setOnHScripts('boyfriendName', PlayState.boyfriend == null ? '' : PlayState.boyfriend.curCharacter);
        setOnHScripts('dadName', PlayState.dad == null ? '' : PlayState.dad.curCharacter);
        setOnHScripts('gfName', PlayState.gf == null ? '' : PlayState.gf.curCharacter);
        setOnHScripts('scrollSpeed', PlayState.instance.songSpeed);
        setOnHScripts('screenWidth', FlxG.width);
        setOnHScripts('screenHeight', FlxG.height);

        var sectionIndex:Int = 0;
        var accumulatedSteps:Int = 0;
        if (PlayState.SONG.notes != null)
        {
            for (i in 0...PlayState.SONG.notes.length)
            {
                var sectionData:Dynamic = PlayState.SONG.notes[i];
                var rawLength:Dynamic = sectionData == null ? null : Reflect.field(sectionData, 'lengthInSteps');
                var parsedLength:Null<Int> = rawLength == null ? null : Std.parseInt(Std.string(rawLength));
                var length:Int = 16;
                if (parsedLength != null && parsedLength > 0) length = parsedLength;
                sectionIndex = i;
                if (PlayState.instance.curStep < accumulatedSteps + length) break;
                accumulatedSteps += length;
            }
        }
        var mustHitSection:Bool = false;
        var gfSection:Bool = false;
        var altAnim:Bool = false;
        if (PlayState.SONG.notes != null
            && sectionIndex >= 0
            && sectionIndex < PlayState.SONG.notes.length
            && PlayState.SONG.notes[sectionIndex] != null)
        {
            var section:Dynamic = PlayState.SONG.notes[sectionIndex];
            mustHitSection = Reflect.field(section, 'mustHitSection') == true;
            gfSection = Reflect.field(section, 'gfSection') == true;
            altAnim = Reflect.field(section, 'altAnim') == true;
        }
        setOnHScripts('curSection', sectionIndex);
        setOnHScripts('mustHitSection', mustHitSection);
        setOnHScripts('mustHit', mustHitSection);
        setOnHScripts('gfSection', gfSection);
        setOnHScripts('altAnim', altAnim);
    }

    static function usedNoteTypes():Array<String>
    {
        var result:Array<String> = [];
        var seen:Map<String, Bool> = new Map<String, Bool>();
        if (PlayState.instance == null || PlayState.instance.unspawnNotes == null) return result;
        for (note in PlayState.instance.unspawnNotes)
        {
            if (note == null || note.noteType == null) continue;
            var value:String = note.noteType.trim();
            if (value.length == 0 || value.toLowerCase() == 'normal') continue;
            var key:String = value.toLowerCase();
            if (!seen.exists(key)) { seen.set(key, true); result.push(value); }
        }
        return result;
    }

    static function usedEventNames():Array<String>
    {
        var result:Array<String> = [];
        var seen:Map<String, Bool> = new Map<String, Bool>();
        if (PlayState.instance == null || PlayState.instance.eventNotes == null) return result;
        for (event in PlayState.instance.eventNotes)
        {
            if (event == null || event.event == null) continue;
            var value:String = event.event.trim();
            if (value.length == 0) continue;
            var key:String = value.toLowerCase();
            if (!seen.exists(key)) { seen.set(key, true); result.push(value); }
        }
        return result;
    }

    public static function destroy():Void
    {
        // onDestroy segue o mesmo ciclo de vida dos scripts Lua/Psych.
        for (script in scripts.copy())
        {
            if (script == null || script.closed) continue;
            callScript(script, 'onDestroy', []);
            script.close();
        }
        scripts = [];
        loadedLogicalPaths = new Map<String, Bool>();
        sharedVariables = new Map<String, Dynamic>();
        currentScript = null;
    }

    static function fileName(path:String):String
    {
        if (path == null) return '';
        var parts:Array<String> = path.replace('\\', '/').split('/');
        return parts.length > 0 ? parts[parts.length - 1] : path;
    }
}
#else
class PsychHScriptManager
{
    public static function initialize():Void {}
    public static function callOnHScripts(functionName:String, args:Array<Dynamic>, ?ignoreStops:Bool = false):Dynamic return 0;
    public static function setOnHScripts(name:String, value:Dynamic):Void {}
    public static function syncVariables():Void {}
    public static function destroy():Void {}
}
#end
