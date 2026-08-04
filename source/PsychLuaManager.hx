package;

#if LUA_ALLOWED
import flixel.FlxBasic;
import flixel.FlxCamera;
import flixel.FlxG;
import flixel.FlxSprite;
import flixel.graphics.FlxGraphic;
import flixel.graphics.frames.FlxAtlasFrames;
import flixel.system.FlxSound;
import flixel.text.FlxText;
import flixel.text.FlxText.FlxTextBorderStyle;
import flixel.tweens.FlxEase;
import flixel.tweens.FlxTween;
import flixel.util.FlxAxes;
import flixel.util.FlxColor;
import flixel.util.FlxTimer;
import llua.Convert;
import llua.Lua;
import llua.Lua.Lua_helper;
import llua.LuaL;
import llua.State;
import openfl.display.BitmapData;
import openfl.display.BlendMode;
import sys.FileSystem;
import sys.io.File;

using StringTools;

/**
 * Runtime Lua compatível com a organização de mods da Psych Engine.
 *
 * Estrutura preservada:
 *   mods/scripts/*.lua
 *   mods/data/<song>/*.lua
 *   mods/stages/<stage>.lua
 *   mods/characters/<character>.lua
 *   mods/custom_notetypes/<note type>.lua (somente quando usado)
 *   mods/custom_events/<event>.lua (somente quando usado)
 *
 * Estabilidade:
 * - usa UMA State Lua por música;
 * - cada arquivo possui ambiente global isolado;
 * - callbacks Haxe são registrados uma única vez;
 * - toda execução usa pcall;
 * - erro de script desativa somente esse arquivo depois de 3 falhas;
 * - falha de inicialização desativa Lua para a música sem fechar o jogo.
 */
class PsychLuaManager
{
    public static var scripts:Array<PsychLua> = [];
    public static var luaSprites:Map<String, FlxSprite> = new Map<String, FlxSprite>();
    public static var luaTexts:Map<String, FlxText> = new Map<String, FlxText>();
    public static var luaTweens:Map<String, FlxTween> = new Map<String, FlxTween>();
    public static var luaTimers:Map<String, FlxTimer> = new Map<String, FlxTimer>();
    public static var luaSounds:Map<String, FlxSound> = new Map<String, FlxSound>();

    static var lua:State = null;
    static var nextScriptId:Int = 1;
    static var currentCallingScript:Int = -1;
    static var loadedLogicalPaths:Map<String, Bool> = new Map<String, Bool>();
    static var callbackNames:Array<String> = [];
    static var modRoots:Array<String> = [];
    static var initialized:Bool = false;

    static final BOOTSTRAP:String = '\n'
        + '__kadesh_scripts = {}\n'
        + 'function __kadesh_load_script(id, path, displayName)\n'
        + '  local chunk, loadError = loadfile(path)\n'
        + '  if not chunk then return false, tostring(loadError) end\n'
        + '  local env = {scriptName = displayName, scriptPath = path}\n'
        + '  env._G = env\n'
        + '  setmetatable(env, {__index = _G})\n'
        + '  setfenv(chunk, env)\n'
        + '  local ok, result = xpcall(chunk, debug.traceback)\n'
        + '  if not ok then return false, tostring(result) end\n'
        + '  __kadesh_scripts[id] = env\n'
        + '  return true, ""\n'
        + 'end\n'
        + 'function __kadesh_call_script(id, callbackName, ...)\n'
        + '  local env = __kadesh_scripts[id]\n'
        + '  if not env then return false, nil, "ambiente Lua não encontrado" end\n'
        + '  local callback = env[callbackName]\n'
        + '  if type(callback) ~= "function" then return true, nil, "" end\n'
        + '  local args = {...}\n'
        + '  local ok, result = xpcall(function() return callback(unpack(args)) end, debug.traceback)\n'
        + '  if not ok then return false, nil, tostring(result) end\n'
        + '  return true, result, ""\n'
        + 'end\n'
        + 'function __kadesh_set_all(name, value)\n'
        + '  rawset(_G, name, value)\n'
        + '  for _, env in pairs(__kadesh_scripts) do rawset(env, name, value) end\n'
        + '  return true\n'
        + 'end\n'
        + 'function __kadesh_remove_script(id) __kadesh_scripts[id] = nil end\n';

    public static function initialize():Void
    {
        destroy();

        if (PlayState.SONG == null)
            return;

        try
        {
            AndroidStorage.init();
            modRoots = discoverModRoots();

            // Sem scripts no filesystem não há motivo para iniciar LuaJIT.
            if (!hasAnyLuaRoot(modRoots))
            {
                trace('[PsychLua] Nenhuma pasta de mods com Lua encontrada.');
                return;
            }

            createState();
            loadPsychStructure();
            syncVariables();
            initialized = true;

            trace('[PsychLua] Runtime pronto. Scripts carregados: ' + scripts.length);
        }
        catch (e:Dynamic)
        {
            var message:String = 'Lua foi desativado para esta música: ' + errorText(e);
            trace('[PsychLua] ' + message);
            KadeshScriptDebug.report('LUA', '<runtime>', message, 'initialize');
            shutdownState();
        }
    }

    static function createState():Void
    {
        lua = LuaL.newstate();
        if (lua == null)
            throw 'LuaL.newstate() retornou null.';

        LuaL.openlibs(lua);
        Lua.init_callbacks(lua);
        registerCallbacks();

        var base:Int = Lua.gettop(lua);
        var status:Int = LuaL.dostring(lua, BOOTSTRAP);
        if (status != 0)
        {
            var message:String = safeLuaString(-1);
            Lua.settop(lua, base);
            throw 'Falha no bootstrap Lua: ' + message;
        }
        Lua.settop(lua, base);

        setSharedGlobal('Function_Continue', PsychLua.Function_Continue);
        setSharedGlobal('Function_Stop', PsychLua.Function_Stop);
        setSharedGlobal('Function_StopLua', PsychLua.Function_StopLua);
        setSharedGlobal('Function_StopHScript', PsychLua.Function_StopHScript);
        setSharedGlobal('version', 'Kadesh PsychLua Stable 2.0');
        setSharedGlobal('psychEngineVersion', '0.6.3-compat');
        setSharedGlobal('buildTarget', #if android 'android' #elseif windows 'windows' #elseif linux 'linux' #elseif mac 'mac' #else 'cpp' #end);
    }

    static function loadPsychStructure():Void
    {
        var song:String = Paths.formatToSongPath(PlayState.SONG.song);

        // Scripts globais: recursivos como na Psych.
        loadDirectoryFromRoots('scripts', true);

        if (PlayState.curStage != null && PlayState.curStage.trim().length > 0)
            loadFileFromRoots('stages/' + PlayState.curStage + '.lua');

        if (PlayState.dad != null)
            loadFileFromRoots('characters/' + PlayState.dad.curCharacter + '.lua');
        if (PlayState.boyfriend != null)
            loadFileFromRoots('characters/' + PlayState.boyfriend.curCharacter + '.lua');
        if (PlayState.gf != null)
            loadFileFromRoots('characters/' + PlayState.gf.curCharacter + '.lua');

        // Scripts da música continuam em data/<song>, sem mudar a estrutura.
        loadDirectoryFromRoots('data/' + song, false);

        // Psych só carrega custom note/event quando o chart realmente usa.
        for (noteType in usedNoteTypes())
            loadFileFromRoots('custom_notetypes/' + noteType + '.lua');

        for (eventName in usedEventNames())
            loadFileFromRoots('custom_events/' + eventName + '.lua');
    }

    static function discoverModRoots():Array<String>
    {
        var roots:Array<String> = [];

        // No Android, esta é a pasta editável do usuário.
        if (AndroidStorage.available && AndroidStorage.mods != null && AndroidStorage.mods.length > 0)
            addUniqueRoot(roots, AndroidStorage.mods);

        #if sys
        var cwd:String = Sys.getCwd();

        // PC usa exatamente a estrutura normal da Psych: ./mods/...
        addExistingRoot(roots, PathNormalize.join(cwd, 'mods'));

        // Compatibilidade com o storage da Kadesh no PC.
        addExistingRoot(roots, PathNormalize.join(cwd, 'KadeshEngine/mods'));

        // Exemplos exportados pelo Project.xml (fallback, menor prioridade).
        addExistingRoot(roots, PathNormalize.join(cwd, 'example_mods'));
        #end

        return roots;
    }

    static function addExistingRoot(roots:Array<String>, path:String):Void
    {
        if (path != null && FileSystem.exists(path) && FileSystem.isDirectory(path))
            addUniqueRoot(roots, path);
    }

    static function addUniqueRoot(roots:Array<String>, path:String):Void
    {
        var normalized:String = PathNormalize.normalize(path);
        for (existing in roots)
            if (PathNormalize.normalize(existing) == normalized)
                return;
        roots.push(path);
    }

    static function hasAnyLuaRoot(roots:Array<String>):Bool
    {
        for (root in roots)
            if (containsLua(root))
                return true;
        return false;
    }

    static function containsLua(path:String):Bool
    {
        if (path == null || !FileSystem.exists(path) || !FileSystem.isDirectory(path))
            return false;

        try
        {
            for (entry in FileSystem.readDirectory(path))
            {
                var full:String = PathNormalize.join(path, entry);
                if (FileSystem.isDirectory(full))
                {
                    if (containsLua(full)) return true;
                }
                else if (entry.toLowerCase().endsWith('.lua'))
                    return true;
            }
        }
        catch (e:Dynamic) {}
        return false;
    }

    static function usedNoteTypes():Array<String>
    {
        var result:Array<String> = [];
        var seen:Map<String, Bool> = new Map<String, Bool>();
        if (PlayState.instance == null || PlayState.instance.unspawnNotes == null)
            return result;

        for (note in PlayState.instance.unspawnNotes)
        {
            if (note == null || note.noteType == null) continue;
            var value:String = note.noteType.trim();
            if (value.length == 0 || value.toLowerCase() == 'normal') continue;
            var key:String = value.toLowerCase();
            if (!seen.exists(key))
            {
                seen.set(key, true);
                result.push(value);
            }
        }
        return result;
    }

    static function usedEventNames():Array<String>
    {
        var result:Array<String> = [];
        var seen:Map<String, Bool> = new Map<String, Bool>();
        if (PlayState.instance == null || PlayState.instance.eventNotes == null)
            return result;

        for (event in PlayState.instance.eventNotes)
        {
            if (event == null || event.event == null) continue;
            var value:String = event.event.trim();
            if (value.length == 0) continue;
            var key:String = value.toLowerCase();
            if (!seen.exists(key))
            {
                seen.set(key, true);
                result.push(value);
            }
        }
        return result;
    }

    static function loadFileFromRoots(relative:String):Void
    {
        var logical:String = PathNormalize.normalize(relative);
        if (loadedLogicalPaths.exists(logical))
            return;

        for (root in modRoots)
        {
            var full:String = PathNormalize.join(root, relative);
            if (FileSystem.exists(full) && !FileSystem.isDirectory(full))
            {
                loadedLogicalPaths.set(logical, true);
                loadFile(full, relative);
                return;
            }
        }
    }

    static function loadDirectoryFromRoots(relativeDirectory:String, recursive:Bool):Void
    {
        // Roots estão em ordem de prioridade. O mesmo caminho lógico é carregado
        // apenas da primeira root em que aparecer.
        for (root in modRoots)
        {
            var directory:String = PathNormalize.join(root, relativeDirectory);
            loadDirectory(root, directory, relativeDirectory, recursive);
        }
    }

    static function loadDirectory(root:String, directory:String, logicalDirectory:String, recursive:Bool):Void
    {
        if (!FileSystem.exists(directory) || !FileSystem.isDirectory(directory))
            return;

        var entries:Array<String>;
        try
        {
            entries = FileSystem.readDirectory(directory);
        }
        catch (e:Dynamic)
        {
            trace('[PsychLua] Não foi possível ler ' + directory + ': ' + errorText(e));
            return;
        }

        entries.sort(function(a:String, b:String):Int
            return Reflect.compare(a.toLowerCase(), b.toLowerCase()));

        for (entry in entries)
        {
            var full:String = PathNormalize.join(directory, entry);
            var logical:String = PathNormalize.join(logicalDirectory, entry);

            if (FileSystem.isDirectory(full))
            {
                if (recursive)
                    loadDirectory(root, full, logical, true);
            }
            else if (entry.toLowerCase().endsWith('.lua'))
            {
                var normalized:String = PathNormalize.normalize(logical);
                if (!loadedLogicalPaths.exists(normalized))
                {
                    loadedLogicalPaths.set(normalized, true);
                    loadFile(full, logical);
                }
            }
        }
    }

    static function loadFile(path:String, logicalPath:String):Void
    {
        if (lua == null) return;

        var id:Int = nextScriptId++;
        var record:PsychLua = new PsychLua(id, path, logicalPath);
        var base:Int = Lua.gettop(lua);
        currentCallingScript = id;

        Lua.getglobal(lua, '__kadesh_load_script');
        Lua.pushinteger(lua, id);
        Lua.pushstring(lua, path);
        Lua.pushstring(lua, fileName(logicalPath));

        var callStatus:Int = Lua.pcall(lua, 3, 2, 0);
        if (callStatus != 0)
        {
            var nativeError:String = safeLuaString(-1);
            Lua.settop(lua, base);
            currentCallingScript = -1;
            trace('[PsychLua] Falha nativa ao carregar ' + logicalPath + ': ' + nativeError);
            KadeshScriptDebug.report('LUA', path, nativeError, 'load');
            return;
        }

        var ok:Bool = Lua.toboolean(lua, -2);
        var message:String = safeLuaString(-1);
        Lua.settop(lua, base);
        currentCallingScript = -1;

        if (!ok)
        {
            trace('[PsychLua] Erro em ' + logicalPath + ': ' + message);
            KadeshScriptDebug.report('LUA', path, message, 'load');
            return;
        }

        scripts.push(record);
        callScript(record, 'onCreate', []);
    }

    public static function callOnLuas(functionName:String, args:Array<Dynamic>, ?ignoreStops:Bool = false):Dynamic
    {
        if (lua == null || scripts.length == 0)
            return PsychLua.Function_Continue;

        var returnValue:Dynamic = PsychLua.Function_Continue;
        var snapshot:Array<PsychLua> = scripts.copy();

        for (script in snapshot)
        {
            if (script == null || script.closed) continue;
            var result:Dynamic = callScript(script, functionName, args == null ? [] : args);

            if (!ignoreStops && isStopResult(result))
                returnValue = PsychLua.Function_Stop;
        }
        return returnValue;
    }

    static function callScript(script:PsychLua, functionName:String, args:Array<Dynamic>):Dynamic
    {
        if (lua == null || script == null || script.closed)
            return null;

        var base:Int = Lua.gettop(lua);
        currentCallingScript = script.id;

        Lua.getglobal(lua, '__kadesh_call_script');
        Lua.pushinteger(lua, script.id);
        Lua.pushstring(lua, functionName);
        for (argument in args) Convert.toLua(lua, argument);

        var status:Int = Lua.pcall(lua, args.length + 2, 3, 0);
        if (status != 0)
        {
            var nativeError:String = safeLuaString(-1);
            Lua.settop(lua, base);
            currentCallingScript = -1;
            registerScriptError(script, functionName, nativeError);
            return null;
        }

        var ok:Bool = Lua.toboolean(lua, -3);
        var value:Dynamic = Lua.type(lua, -2) == Lua.LUA_TNIL
            ? null
            : Convert.fromLua(lua, -2);
        var message:String = safeLuaString(-1);

        Lua.settop(lua, base);
        currentCallingScript = -1;

        if (!ok)
        {
            registerScriptError(script, functionName, message);
            return null;
        }

        return value;
    }

    static function registerScriptError(script:PsychLua, callback:String, message:String):Void
    {
        script.errorCount++;
        trace('[PsychLua] ' + script.logicalPath + ' -> ' + callback + ': ' + message);
        KadeshScriptDebug.report('LUA', script.scriptName, message, callback);

        if (script.errorCount >= 3)
        {
            var disabled:String = 'Script desativado após 3 erros: ' + script.logicalPath;
            trace('[PsychLua] ' + disabled);
            KadeshScriptDebug.warning('LUA', script.scriptName, disabled);
            closeScript(script);
        }
    }

    static function isStopResult(value:Dynamic):Bool
    {
        if (value == null) return false;
        if (Std.isOfType(value, Bool)) return false;
        var parsed:Null<Int> = Std.parseInt(Std.string(value));
        return parsed != null && parsed == PsychLua.Function_Stop;
    }

    public static function setOnLuas(name:String, value:Dynamic):Void
    {
        if (lua == null) return;
        var base:Int = Lua.gettop(lua);
        Lua.getglobal(lua, '__kadesh_set_all');
        Lua.pushstring(lua, name);
        Convert.toLua(lua, value);
        var status:Int = Lua.pcall(lua, 2, 1, 0);
        if (status != 0)
            trace('[PsychLua] setOnLuas(' + name + ') falhou: ' + safeLuaString(-1));
        Lua.settop(lua, base);
    }

    static function setSharedGlobal(name:String, value:Dynamic):Void
    {
        if (lua == null) return;
        Convert.toLua(lua, value);
        Lua.setglobal(lua, name);
    }

    public static function syncVariables():Void
    {
        if (PlayState.instance == null || lua == null) return;

        setOnLuas('curBeat', PlayState.instance.curBeat);
        setOnLuas('curStep', PlayState.instance.curStep);
        setOnLuas('songPosition', Conductor.songPosition);
        setOnLuas('curBpm', Conductor.bpm);
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
        setOnLuas('scrollSpeed', PlayState.instance.songSpeed);
        setOnLuas('screenWidth', FlxG.width);
        setOnLuas('screenHeight', FlxG.height);
        setOnLuas('cameraX', FlxG.camera.x);
        setOnLuas('cameraY', FlxG.camera.y);

        if (PlayState.playerStrums != null && PlayState.cpuStrums != null)
        {
            for (i in 0...4)
            {
                if (i < PlayState.playerStrums.members.length && PlayState.playerStrums.members[i] != null)
                {
                    setOnLuas('defaultPlayerStrumX' + i, PlayState.playerStrums.members[i].x);
                    setOnLuas('defaultPlayerStrumY' + i, PlayState.playerStrums.members[i].y);
                }
                if (i < PlayState.cpuStrums.members.length && PlayState.cpuStrums.members[i] != null)
                {
                    setOnLuas('defaultOpponentStrumX' + i, PlayState.cpuStrums.members[i].x);
                    setOnLuas('defaultOpponentStrumY' + i, PlayState.cpuStrums.members[i].y);
                }
            }
        }
    }

    // ---------------------------------------------------------------------
    // Callbacks Lua -> Haxe (registrados uma única vez por State)
    // ---------------------------------------------------------------------

    static function registerCallbacks():Void
    {
        callbackNames = [];
        Lua_helper.sendErrorsToLua = true;

        addSafeCallback('debugPrint', function(a) {
            var values:Array<String> = [];
            for (item in a) values.push(Std.string(item));
            trace('[Lua][' + currentScriptLabel() + '] ' + values.join(' '));
            return null;
        });

        addSafeCallback('getProperty', function(a) return scriptGetProperty(stringArg(a, 0)));
        addSafeCallback('setProperty', function(a) return scriptSetProperty(stringArg(a, 0), arg(a, 1)));

        addSafeCallback('getPropertyFromGroup', function(a)
            return scriptGetPropertyFromGroup(stringArg(a, 0), intArg(a, 1), stringArg(a, 2)));
        addSafeCallback('setPropertyFromGroup', function(a)
            return scriptSetPropertyFromGroup(stringArg(a, 0), intArg(a, 1), stringArg(a, 2), arg(a, 3)));
        addSafeCallback('removeFromGroup', function(a) {
            var target:Dynamic = resolveObject(stringArg(a, 0));
            var index:Int = intArg(a, 1);
            var dontDestroy:Bool = boolArg(a, 2, false);
            if (target == null || !Reflect.hasField(target, 'members')) return false;
            var members:Dynamic = Reflect.getProperty(target, 'members');
            if (members == null || index < 0 || index >= members.length) return false;
            var object:Dynamic = members[index];
            if (Reflect.hasField(target, 'remove'))
                Reflect.callMethod(target, Reflect.getProperty(target, 'remove'), [object, true]);
            if (!dontDestroy && object != null && Reflect.hasField(object, 'destroy'))
                Reflect.callMethod(object, Reflect.getProperty(object, 'destroy'), []);
            return true;
        });

        addSafeCallback('getPropertyFromClass', function(a)
            return scriptGetPropertyFromClass(stringArg(a, 0), stringArg(a, 1)));
        addSafeCallback('setPropertyFromClass', function(a)
            return scriptSetPropertyFromClass(stringArg(a, 0), stringArg(a, 1), arg(a, 2)));

        addSafeCallback('getPropertyFromMap', function(a) {
            var target:Dynamic = resolveObject(stringArg(a, 0));
            var result = tryMapGet(target, arg(a, 1));
            return result.found ? result.value : null;
        });
        addSafeCallback('setPropertyFromMap', function(a) {
            var target:Dynamic = resolveObject(stringArg(a, 0));
            if (!tryMapSet(target, arg(a, 1), arg(a, 2)))
                throw 'setPropertyFromMap: mapa não encontrado: ' + stringArg(a, 0);
            return arg(a, 2);
        });

        addSafeCallback('makeLuaSprite', function(a)
            return makeSprite(stringArg(a, 0), stringArg(a, 1), floatArg(a, 2), floatArg(a, 3), false));
        addSafeCallback('makeAnimatedLuaSprite', function(a)
            return makeSprite(stringArg(a, 0), stringArg(a, 1), floatArg(a, 2), floatArg(a, 3), true, stringArg(a, 4, 'sparrow')));
        addSafeCallback('addLuaSprite', function(a) return addSprite(stringArg(a, 0), boolArg(a, 1, false)));
        addSafeCallback('removeLuaSprite', function(a) return removeSprite(stringArg(a, 0), boolArg(a, 1, true)));
        addSafeCallback('luaSpriteExists', function(a) return luaSprites.exists(stringArg(a, 0)));

        addSafeCallback('makeLuaText', function(a)
            return makeText(stringArg(a, 0), stringArg(a, 1), floatArg(a, 2), floatArg(a, 3), floatArg(a, 4)));
        addSafeCallback('addLuaText', function(a) return addText(stringArg(a, 0), boolArg(a, 1, false)));
        addSafeCallback('removeLuaText', function(a) return removeText(stringArg(a, 0), boolArg(a, 1, true)));
        addSafeCallback('luaTextExists', function(a) return luaTexts.exists(stringArg(a, 0)));
        addSafeCallback('setTextString', function(a) {
            var text:FlxText = luaTexts.get(stringArg(a, 0));
            if (text == null) return false;
            text.text = stringArg(a, 1);
            return true;
        });
        addSafeCallback('setTextSize', function(a) {
            var text:FlxText = luaTexts.get(stringArg(a, 0));
            if (text == null) return false;
            text.size = intArg(a, 1, 16);
            return true;
        });
        addSafeCallback('setTextColor', function(a) {
            var text:FlxText = luaTexts.get(stringArg(a, 0));
            if (text == null) return false;
            text.color = colorFromString(stringArg(a, 1, 'FFFFFF'));
            return true;
        });
        addSafeCallback('setTextAlignment', function(a) {
            var text:FlxText = luaTexts.get(stringArg(a, 0));
            if (text == null) return false;
            switch (stringArg(a, 1, 'left').toLowerCase())
            {
                case 'center': text.alignment = cast 'center';
                case 'right': text.alignment = cast 'right';
                case 'justify': text.alignment = cast 'justify';
                default: text.alignment = cast 'left';
            }
            return true;
        });
        addSafeCallback('setTextBorder', function(a) {
            var text:FlxText = luaTexts.get(stringArg(a, 0));
            if (text == null) return false;
            text.setBorderStyle(FlxTextBorderStyle.OUTLINE, colorFromString(stringArg(a, 2, '000000')), floatArg(a, 1, 1));
            return true;
        });

        addSafeCallback('makeGraphic', function(a) {
            var sprite:FlxSprite = cast resolveObject(stringArg(a, 0));
            if (sprite == null) return false;
            sprite.makeGraphic(intArg(a, 1, 1), intArg(a, 2, 1), colorFromString(stringArg(a, 3, 'FFFFFF')));
            return true;
        });
        addSafeCallback('loadGraphic', function(a)
            return loadGraphic(stringArg(a, 0), stringArg(a, 1), intArg(a, 2), intArg(a, 3)));

        addSafeCallback('addAnimationByPrefix', function(a) {
            var sprite:FlxSprite = cast resolveObject(stringArg(a, 0));
            if (sprite == null) return false;
            sprite.animation.addByPrefix(stringArg(a, 1), stringArg(a, 2), intArg(a, 3, 24), boolArg(a, 4, false));
            return true;
        });
        addSafeCallback('addAnimationByIndices', function(a) {
            var sprite:FlxSprite = cast resolveObject(stringArg(a, 0));
            if (sprite == null) return false;
            var parsed:Array<Int> = parseIndices(arg(a, 3));
            sprite.animation.addByIndices(stringArg(a, 1), stringArg(a, 2), parsed, '', intArg(a, 4, 24), boolArg(a, 5, false));
            return true;
        });
        addSafeCallback('objectPlayAnimation', function(a)
            return playAnimation(stringArg(a, 0), stringArg(a, 1), boolArg(a, 2, false), boolArg(a, 3, false), intArg(a, 4, 0)));
        addSafeCallback('playAnim', function(a)
            return playAnimation(stringArg(a, 0), stringArg(a, 1), boolArg(a, 2, false), boolArg(a, 3, false), intArg(a, 4, 0)));
        addSafeCallback('characterPlayAnim', function(a) {
            var target:Dynamic = resolveObject(stringArg(a, 0));
            if (target == null || !Std.isOfType(target, Character)) return false;
            (cast target:Character).playAnim(stringArg(a, 1), boolArg(a, 2, false));
            return true;
        });

        addSafeCallback('setObjectCamera', function(a) {
            var object:Dynamic = resolveObject(stringArg(a, 0));
            var camera:FlxCamera = getCamera(stringArg(a, 1));
            if (object == null || camera == null || !Reflect.hasField(object, 'cameras')) return false;
            Reflect.setProperty(object, 'cameras', [camera]);
            return true;
        });
        addSafeCallback('setScrollFactor', function(a) {
            var sprite:FlxSprite = cast resolveObject(stringArg(a, 0));
            if (sprite == null) return false;
            sprite.scrollFactor.set(floatArg(a, 1), floatArg(a, 2));
            return true;
        });
        addSafeCallback('scaleObject', function(a) {
            var sprite:FlxSprite = cast resolveObject(stringArg(a, 0));
            if (sprite == null) return false;
            sprite.scale.set(floatArg(a, 1, 1), floatArg(a, 2, 1));
            if (boolArg(a, 3, true)) sprite.updateHitbox();
            return true;
        });
        addSafeCallback('setGraphicSize', function(a) {
            var sprite:FlxSprite = cast resolveObject(stringArg(a, 0));
            if (sprite == null) return false;
            sprite.setGraphicSize(intArg(a, 1), intArg(a, 2));
            if (boolArg(a, 3, true)) sprite.updateHitbox();
            return true;
        });
        addSafeCallback('updateHitbox', function(a) {
            var sprite:FlxSprite = cast resolveObject(stringArg(a, 0));
            if (sprite == null) return false;
            sprite.updateHitbox();
            return true;
        });
        addSafeCallback('screenCenter', function(a) {
            var sprite:FlxSprite = cast resolveObject(stringArg(a, 0));
            if (sprite == null) return false;
            var axes:String = stringArg(a, 1, 'xy').toLowerCase();
            sprite.screenCenter(axes == 'x' ? FlxAxes.X : axes == 'y' ? FlxAxes.Y : FlxAxes.XY);
            return true;
        });
        addSafeCallback('setObjectOrder', function(a) return setObjectOrder(stringArg(a, 0), intArg(a, 1)));
        addSafeCallback('getObjectOrder', function(a) return getObjectOrder(stringArg(a, 0)));
        addSafeCallback('setBlendMode', function(a) return setBlendMode(stringArg(a, 0), stringArg(a, 1)));

        addSafeCallback('doTweenX', function(a) return tweenProperty(stringArg(a, 0), stringArg(a, 1), 'x', floatArg(a, 2), floatArg(a, 3), stringArg(a, 4, 'linear')));
        addSafeCallback('doTweenY', function(a) return tweenProperty(stringArg(a, 0), stringArg(a, 1), 'y', floatArg(a, 2), floatArg(a, 3), stringArg(a, 4, 'linear')));
        addSafeCallback('doTweenAlpha', function(a) return tweenProperty(stringArg(a, 0), stringArg(a, 1), 'alpha', floatArg(a, 2), floatArg(a, 3), stringArg(a, 4, 'linear')));
        addSafeCallback('doTweenAngle', function(a) return tweenProperty(stringArg(a, 0), stringArg(a, 1), 'angle', floatArg(a, 2), floatArg(a, 3), stringArg(a, 4, 'linear')));
        addSafeCallback('doTweenZoom', function(a) return tweenCameraZoom(stringArg(a, 0), stringArg(a, 1), floatArg(a, 2), floatArg(a, 3), stringArg(a, 4, 'linear')));
        addSafeCallback('cancelTween', function(a) return cancelTween(stringArg(a, 0)));

        addSafeCallback('noteTweenX', function(a) return tweenStrum(stringArg(a, 0), intArg(a, 1), 'x', floatArg(a, 2), floatArg(a, 3), stringArg(a, 4, 'linear')));
        addSafeCallback('noteTweenY', function(a) return tweenStrum(stringArg(a, 0), intArg(a, 1), 'y', floatArg(a, 2), floatArg(a, 3), stringArg(a, 4, 'linear')));
        addSafeCallback('noteTweenAlpha', function(a) return tweenStrum(stringArg(a, 0), intArg(a, 1), 'alpha', floatArg(a, 2), floatArg(a, 3), stringArg(a, 4, 'linear')));
        addSafeCallback('noteTweenAngle', function(a) return tweenStrum(stringArg(a, 0), intArg(a, 1), 'angle', floatArg(a, 2), floatArg(a, 3), stringArg(a, 4, 'linear')));

        addSafeCallback('runTimer', function(a) return runTimer(stringArg(a, 0), floatArg(a, 1), intArg(a, 2, 1)));
        addSafeCallback('cancelTimer', function(a) return cancelTimer(stringArg(a, 0)));
        addSafeCallback('playSound', function(a) return playSound(stringArg(a, 0), floatArg(a, 1, 1), nullableStringArg(a, 2)));
        addSafeCallback('stopSound', function(a) return stopSound(stringArg(a, 0)));
        addSafeCallback('luaSoundExists', function(a) return luaSounds.exists(stringArg(a, 0)));

        addSafeCallback('cameraFlash', function(a) {
            var camera:FlxCamera = getCamera(stringArg(a, 0));
            if (camera == null) return false;
            camera.flash(colorFromString(stringArg(a, 1, 'FFFFFF')), floatArg(a, 2), null, boolArg(a, 3, false));
            return true;
        });
        addSafeCallback('cameraShake', function(a) {
            var camera:FlxCamera = getCamera(stringArg(a, 0));
            if (camera == null) return false;
            camera.shake(floatArg(a, 1), floatArg(a, 2));
            return true;
        });
        addSafeCallback('triggerEvent', function(a)
            return scriptTriggerEvent(stringArg(a, 0), stringArg(a, 1), stringArg(a, 2)));
        addSafeCallback('triggerEventNote', function(a)
            return scriptTriggerEvent(stringArg(a, 0), stringArg(a, 1), stringArg(a, 2)));

        addSafeCallback('getSongPosition', function(a) return Conductor.songPosition);
        addSafeCallback('getColorFromHex', function(a) return colorFromString(stringArg(a, 0)));
        addSafeCallback('getHealth', function(a) return PlayState.instance == null ? 0 : PlayState.instance.health);
        addSafeCallback('setHealth', function(a) {
            if (PlayState.instance == null) return false;
            PlayState.instance.health = floatArg(a, 0);
            return true;
        });
        addSafeCallback('addHealth', function(a) {
            if (PlayState.instance == null) return false;
            PlayState.instance.health += floatArg(a, 0);
            return true;
        });

        addSafeCallback('getRandomInt', function(a) {
            var min:Int = intArg(a, 0);
            var max:Int = intArg(a, 1, min);
            return FlxG.random.int(min, max, parseExcludeInts(stringArg(a, 2)));
        });
        addSafeCallback('getRandomFloat', function(a) return FlxG.random.float(floatArg(a, 0), floatArg(a, 1, 1)));
        addSafeCallback('getRandomBool', function(a) return FlxG.random.bool(floatArg(a, 0, 50)));
        addSafeCallback('stringStartsWith', function(a) return stringArg(a, 0).startsWith(stringArg(a, 1)));
        addSafeCallback('stringEndsWith', function(a) return stringArg(a, 0).endsWith(stringArg(a, 1)));
        addSafeCallback('stringTrim', function(a) return stringArg(a, 0).trim());
        addSafeCallback('stringSplit', function(a) return stringArg(a, 0).split(stringArg(a, 1)));

        addSafeCallback('precacheImage', function(a) {
            try
            {
                Paths.image(stripExtension(stringArg(a, 0)));
                return true;
            }
            catch (e:Dynamic)
            {
                return false;
            }
        });
        addSafeCallback('precacheSound', function(a) {
            try
            {
                Paths.sound(stringArg(a, 0));
                return true;
            }
            catch (e:Dynamic)
            {
                return false;
            }
        });
        addSafeCallback('close', function(a) {
            closeCurrentScript();
            return true;
        });
    }

    static function addSafeCallback(name:String, handler:Array<Dynamic>->Dynamic):Void
    {
        var wrapped:Dynamic = Reflect.makeVarArgs(function(args:Array<Dynamic>):Dynamic
        {
            try
            {
                return handler(args);
            }
            catch (e:Dynamic)
            {
                // sendErrorsToLua converte a exceção em LuaL.error. O xpcall
                // do bootstrap acrescenta o traceback com arquivo e linha.
                throw name + ': ' + errorText(e);
            }
        });

        Lua_helper.add_callback(lua, name, wrapped);
        callbackNames.push(name);
    }

    static function findScriptById(id:Int):PsychLua
    {
        for (script in scripts)
            if (script != null && script.id == id)
                return script;
        return null;
    }

    // ---------------------------------------------------------------------
    // Objetos e propriedades
    // ---------------------------------------------------------------------

    public static function resolveObject(name:String):Dynamic
    {
        if (name == null) return null;
        var id:String = name.trim();
        if (id.length == 0) return null;
        if (luaSprites.exists(id)) return luaSprites.get(id);
        if (luaTexts.exists(id)) return luaTexts.get(id);
        if (KadeshStageData.current != null)
        {
            var stageObject:Dynamic = KadeshStageData.current.getObject(id);
            if (stageObject != null) return stageObject;
        }

        switch (id)
        {
            case 'boyfriend' | 'bf': return PlayState.boyfriend;
            case 'dad' | 'opponent': return PlayState.dad;
            case 'gf' | 'girlfriend': return PlayState.gf;
            // A Kade não possui os grupos da Psych; aliases apontam para os
            // próprios personagens e preservam x/y/alpha/visible.
            case 'boyfriendGroup': return PlayState.boyfriend;
            case 'dadGroup': return PlayState.dad;
            case 'gfGroup': return PlayState.gf;
            case 'camGame' | 'gameCam': return FlxG.camera;
            case 'camHUD' | 'camOther' | 'hudCam': return PlayState.instance == null ? null : PlayState.instance.camHUD;
            case 'notes': return PlayState.instance == null ? null : PlayState.instance.notes;
            case 'unspawnNotes': return PlayState.instance == null ? null : PlayState.instance.unspawnNotes;
            case 'eventNotes': return PlayState.instance == null ? null : PlayState.instance.eventNotes;
            case 'playerStrums': return PlayState.playerStrums;
            case 'opponentStrums' | 'cpuStrums': return PlayState.cpuStrums;
            case 'strumLineNotes': return PlayState.strumLineNotes;
            case 'healthBar': return PlayState.instance == null ? null : PlayState.instance.healthBar;
            case 'healthBarBG': return PlayState.instance == null ? null : PlayState.instance.healthBarBG;
            case 'iconP1': return PlayState.instance == null ? null : PlayState.instance.iconP1;
            case 'iconP2': return PlayState.instance == null ? null : PlayState.instance.iconP2;
            case 'scoreTxt': return PlayState.instance == null ? null : PlayState.instance.scoreTxt;
            case 'vocals': return PlayState.instance == null ? null : PlayState.instance.vocals;
            default:
                if (PlayState.instance != null)
                {
                    var result = safeGetProperty(PlayState.instance, id);
                    if (result.found) return result.value;
                }
        }
        return null;
    }

    static function normalizePropertyPath(path:String):String
    {
        if (path == null) return '';
        var result:String = path.trim();
        var bracket:EReg = ~/\[([0-9]+)\]/g;
        result = bracket.replace(result, '.$1');
        var quotedBracket:EReg = ~/\[['"]([^'"]+)['"]\]/g;
        result = quotedBracket.replace(result, '.$1');
        while (result.startsWith('.')) result = result.substr(1);
        while (result.indexOf('..') != -1) result = result.replace('..', '.');
        return result;
    }

    public static function scriptGetProperty(path:String):Dynamic
    {
        return getPropertyPath(path);
    }

    public static function scriptSetProperty(path:String, value:Dynamic):Dynamic
    {
        if (!setPropertyPath(path, value))
            throw 'setProperty: propriedade não encontrada ou não gravável: "' + path + '"';
        return value;
    }

    public static function scriptGetPropertyFromGroup(group:String, index:Int, field:String):Dynamic
    {
        var member:Dynamic = getGroupMember(group, index, true);
        return member == null ? null : getNested(member, field);
    }

    public static function scriptSetPropertyFromGroup(group:String, index:Int, field:String, value:Dynamic):Dynamic
    {
        var member:Dynamic = getGroupMember(group, index, true);
        if (member == null || !setNested(member, field, value))
            throw 'setPropertyFromGroup: ' + group + '[' + index + '].' + field + ' não existe.';
        return value;
    }

    public static function scriptGetPropertyFromClass(className:String, field:String):Dynamic
    {
        var cls:Dynamic = resolveClass(className);
        return cls == null ? null : getNested(cls, field);
    }

    public static function scriptSetPropertyFromClass(className:String, field:String, value:Dynamic):Dynamic
    {
        var cls:Dynamic = resolveClass(className);
        if (cls == null || !setNested(cls, field, value))
            throw 'setPropertyFromClass: ' + className + '.' + field + ' não existe.';
        return value;
    }

    static function resolveClass(name:String):Dynamic
    {
        if (name == null) return null;
        switch (name.trim())
        {
            case 'FlxG' | 'flixel.FlxG': return Type.resolveClass('flixel.FlxG');
            case 'PlayState': return PlayState;
            case 'Conductor': return Conductor;
            case 'Main': return Main;
            case 'Paths': return Paths;
            default: return Type.resolveClass(name);
        }
    }

    static function getPropertyPath(path:String):Dynamic
    {
        var normalized:String = normalizePropertyPath(path);
        if (normalized.length == 0) return null;
        var parts:Array<String> = normalized.split('.');
        var first:String = parts[0];

        // Uma propriedade simples como "health" pertence à PlayState.
        if (parts.length == 1 && PlayState.instance != null)
        {
            var direct = safeGetProperty(PlayState.instance, first);
            if (direct.found) return direct.value;
        }

        var root:Dynamic = resolveObject(first);
        if (root != null)
        {
            parts.shift();
            return getNested(root, parts.join('.'));
        }

        return PlayState.instance == null ? null : getNested(PlayState.instance, normalized);
    }

    static function setPropertyPath(path:String, value:Dynamic):Bool
    {
        var normalized:String = normalizePropertyPath(path);
        if (normalized.length == 0 || PlayState.instance == null) return false;
        var parts:Array<String> = normalized.split('.');
        var first:String = parts[0];

        // Corrige o caso mais comum da Psych: setProperty('health', 2).
        if (parts.length == 1 && propertyExists(PlayState.instance, first))
            return safeSetProperty(PlayState.instance, first, value);

        var root:Dynamic = resolveObject(first);
        if (root != null)
        {
            parts.shift();
            if (parts.length == 0) return false;
            return setNested(root, parts.join('.'), value);
        }

        return setNested(PlayState.instance, normalized, value);
    }

    static function getNested(root:Dynamic, path:String):Dynamic
    {
        if (root == null || path == null || path.length == 0) return root;
        var current:Dynamic = root;

        for (field in normalizePropertyPath(path).split('.'))
        {
            if (current == null) return null;
            if (field == 'length')
            {
                var length:Null<Int> = dynamicLength(current);
                if (length == null) return null;
                current = length;
                continue;
            }

            var index:Null<Int> = Std.parseInt(field);
            if (index != null)
            {
                current = getIndexed(current, index);
                continue;
            }

            var found = safeGetProperty(current, field);
            if (found.found)
            {
                current = found.value;
                continue;
            }

            var mapValue = tryMapGet(current, field);
            if (mapValue.found)
            {
                current = mapValue.value;
                continue;
            }
            return null;
        }
        return current;
    }

    static function setNested(root:Dynamic, path:String, value:Dynamic):Bool
    {
        if (root == null || path == null || path.length == 0) return false;
        var parts:Array<String> = normalizePropertyPath(path).split('.');
        var field:String = parts.pop();
        var parent:Dynamic = parts.length == 0 ? root : getNested(root, parts.join('.'));
        if (parent == null) return false;

        var index:Null<Int> = Std.parseInt(field);
        if (index != null)
            return setIndexed(parent, index, value);

        if (propertyExists(parent, field))
            return safeSetProperty(parent, field, value);

        if (tryMapSet(parent, field, value))
            return true;

        return safeSetProperty(parent, field, value);
    }

    static function safeGetProperty(object:Dynamic, field:String):{found:Bool, value:Dynamic}
    {
        if (object == null || field == null) return {found: false, value: null};
        try
        {
            if (Reflect.hasField(object, field))
                return {found: true, value: Reflect.getProperty(object, field)};
            var value:Dynamic = Reflect.getProperty(object, field);
            if (value != null)
                return {found: true, value: value};
        }
        catch (e:Dynamic) {}
        return {found: false, value: null};
    }

    static function propertyExists(object:Dynamic, field:String):Bool
    {
        if (object == null || field == null || field.length == 0) return false;
        try
        {
            if (Reflect.hasField(object, field)) return true;

            var objectClass:Class<Dynamic> = Type.getClass(object);
            if (objectClass != null && Type.getInstanceFields(objectClass).indexOf(field) >= 0)
                return true;

            try
            {
                var staticFields:Array<String> = Type.getClassFields(cast object);
                if (staticFields != null && staticFields.indexOf(field) >= 0)
                    return true;
            }
            catch (ignored:Dynamic) {}
        }
        catch (e:Dynamic) {}
        return false;
    }

    static function safeSetProperty(object:Dynamic, field:String, value:Dynamic):Bool
    {
        if (object == null || field == null || field.length == 0) return false;
        try
        {
            Reflect.setProperty(object, field, value);
            return true;
        }
        catch (e:Dynamic) {}
        return false;
    }

    static function dynamicLength(value:Dynamic):Null<Int>
    {
        if (value == null) return null;
        try
        {
            var length:Dynamic = Reflect.getProperty(value, 'length');
            if (length != null) return Std.int(length);
        }
        catch (e:Dynamic) {}
        return null;
    }

    static function getIndexed(value:Dynamic, index:Int):Dynamic
    {
        var length:Null<Int> = dynamicLength(value);
        if (length == null || index < 0 || index >= length) return null;
        try
        {
            return untyped value[index];
        }
        catch (e:Dynamic)
        {
            return null;
        }
    }

    static function setIndexed(value:Dynamic, index:Int, newValue:Dynamic):Bool
    {
        var length:Null<Int> = dynamicLength(value);
        if (length == null || index < 0 || index >= length) return false;
        try
        {
            untyped value[index] = newValue;
            return true;
        }
        catch (e:Dynamic)
        {
            return false;
        }
    }

    static function tryMapGet(object:Dynamic, key:Dynamic):{found:Bool, value:Dynamic}
    {
        if (object == null) return {found: false, value: null};
        try
        {
            var exists:Dynamic = Reflect.getProperty(object, 'exists');
            var get:Dynamic = Reflect.getProperty(object, 'get');
            if (Reflect.isFunction(get))
            {
                if (Reflect.isFunction(exists) && !Reflect.callMethod(object, exists, [key]))
                    return {found: false, value: null};
                return {found: true, value: Reflect.callMethod(object, get, [key])};
            }
        }
        catch (e:Dynamic) {}
        return {found: false, value: null};
    }

    static function tryMapSet(object:Dynamic, key:Dynamic, value:Dynamic):Bool
    {
        if (object == null) return false;
        try
        {
            var set:Dynamic = Reflect.getProperty(object, 'set');
            if (Reflect.isFunction(set))
            {
                Reflect.callMethod(object, set, [key, value]);
                return true;
            }
        }
        catch (e:Dynamic) {}
        return false;
    }

    static function getGroupMember(group:String, index:Int, allowArray:Bool):Dynamic
    {
        var target:Dynamic = resolveObject(group);
        if (target == null) return null;

        var membersResult = safeGetProperty(target, 'members');
        var members:Dynamic = membersResult.found
            ? membersResult.value
            : (allowArray && dynamicLength(target) != null ? target : null);

        return members == null ? null : getIndexed(members, index);
    }

    // ---------------------------------------------------------------------
    // Sprites, textos, tweens, timers e áudio
    // ---------------------------------------------------------------------

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
            trace('[PsychLua] makeLuaSprite(' + tag + ') falhou: ' + errorText(e));
            sprite.destroy();
            return false;
        }
    }

    public static function addSprite(tag:String, front:Bool):Bool
    {
        var sprite:FlxSprite = luaSprites.get(tag);
        if (sprite == null || PlayState.instance == null) return false;
        if (PlayState.instance.members.indexOf(sprite) >= 0) return true;

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

    static function makeText(tag:String, text:String, width:Float, x:Float, y:Float):Bool
    {
        removeText(tag, true);
        var object:FlxText = new FlxText(x, y, width, text, 16);
        object.setFormat(Paths.font('vcr.ttf'), 16, FlxColor.WHITE, cast 'left', FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
        luaTexts.set(tag, object);
        return true;
    }

    static function addText(tag:String, front:Bool):Bool
    {
        var text:FlxText = luaTexts.get(tag);
        if (text == null || PlayState.instance == null) return false;
        if (PlayState.instance.members.indexOf(text) >= 0) return true;
        if (front) PlayState.instance.addObject(text);
        else PlayState.instance.add(text);
        return true;
    }

    static function removeText(tag:String, destroy:Bool):Bool
    {
        var text:FlxText = luaTexts.get(tag);
        if (text == null) return false;
        if (PlayState.instance != null) PlayState.instance.removeObject(text);
        luaTexts.remove(tag);
        if (destroy) text.destroy();
        return true;
    }

    public static function loadGraphic(tag:String, image:String, gridX:Int, gridY:Int):Bool
    {
        var sprite:FlxSprite = luaSprites.get(tag);
        if (sprite == null) return false;
        try
        {
            var external:String = externalImage(image);
            var animated:Bool = gridX > 0 && gridY > 0;
            if (FileSystem.exists(external))
            {
                var bitmap:BitmapData = BitmapData.fromFile(external);
                if (bitmap == null) return false;
                sprite.loadGraphic(FlxGraphic.fromBitmapData(bitmap, false, external), animated, gridX, gridY);
            }
            else sprite.loadGraphic(Paths.image(stripExtension(image)), animated, gridX, gridY);
            return true;
        }
        catch (e:Dynamic)
        {
            trace('[PsychLua] loadGraphic falhou: ' + errorText(e));
            return false;
        }
    }

    static function loadImageInto(sprite:FlxSprite, image:String):Void
    {
        var external:String = externalImage(image);
        if (FileSystem.exists(external))
        {
            var bitmap:BitmapData = BitmapData.fromFile(external);
            if (bitmap == null) throw 'BitmapData.fromFile retornou null: ' + external;
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
            if (bitmap == null) throw 'Falha ao ler PNG: ' + png;
            var graphic:FlxGraphic = FlxGraphic.fromBitmapData(bitmap, false, png);

            if (spriteType != null && spriteType.toLowerCase() == 'packer')
            {
                var txt:String = findExternalModFile('images/' + key + '.txt');
                if (txt == null) throw 'TXT Packer não encontrado para ' + key;
                return FlxAtlasFrames.fromSpriteSheetPacker(graphic, File.getContent(txt));
            }

            var xml:String = findExternalModFile('images/' + key + '.xml');
            if (xml == null) throw 'XML Sparrow não encontrado para ' + key;
            return FlxAtlasFrames.fromSparrow(graphic, File.getContent(xml));
        }

        return spriteType != null && spriteType.toLowerCase() == 'packer'
            ? Paths.getPackerAtlas(key)
            : Paths.getSparrowAtlas(key);
    }

    static function externalImage(image:String):String
    {
        var found:String = findExternalModFile('images/' + stripExtension(image) + '.png');
        return found == null ? '' : found;
    }

    static function findExternalModFile(relative:String):Null<String>
    {
        for (root in modRoots)
        {
            var full:String = PathNormalize.join(root, relative);
            if (FileSystem.exists(full) && !FileSystem.isDirectory(full)) return full;
        }
        return null;
    }

    static function stripExtension(image:String):String
    {
        if (image == null) return '';
        var value:String = image.replace('\\', '/');
        if (value.toLowerCase().endsWith('.png')) value = value.substr(0, value.length - 4);
        while (value.startsWith('/')) value = value.substr(1);
        return value;
    }

    static function playAnimation(tag:String, name:String, force:Bool, reverse:Bool, startFrame:Int):Bool
    {
        var object:Dynamic = resolveObject(tag);
        if (object == null) return false;

        if (Std.isOfType(object, Character))
        {
            (cast object:Character).playAnim(name, force, reverse, startFrame);
            return true;
        }

        if (!Reflect.hasField(object, 'animation')) return false;
        var animation:Dynamic = Reflect.getProperty(object, 'animation');
        if (animation == null || !Reflect.hasField(animation, 'play')) return false;
        Reflect.callMethod(animation, Reflect.getProperty(animation, 'play'), [name, force, reverse, startFrame]);
        return true;
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

    static function setBlendMode(tag:String, blend:String):Bool
    {
        var sprite:FlxSprite = cast resolveObject(tag);
        if (sprite == null) return false;
        switch (blend == null ? '' : blend.toLowerCase())
        {
            case 'add': sprite.blend = BlendMode.ADD;
            case 'multiply': sprite.blend = BlendMode.MULTIPLY;
            case 'screen': sprite.blend = BlendMode.SCREEN;
            case 'subtract': sprite.blend = BlendMode.SUBTRACT;
            default: sprite.blend = BlendMode.NORMAL;
        }
        return true;
    }

    public static function tweenProperty(tag:String, objectName:String, property:String, value:Float, duration:Float, ease:String):Bool
    {
        var object:Dynamic = resolveObject(objectName);
        if (object == null) return false;
        cancelTween(tag);

        var values:Dynamic = {};
        Reflect.setField(values, property, value);
        var tween:FlxTween = FlxTween.tween(object, values, Math.max(0.0001, duration), {
            ease: easeFromString(ease),
            onComplete: function(_:FlxTween)
            {
                luaTweens.remove(tag);
                dispatchSharedCallback('onTweenCompleted', [tag]);
            }
        });
        luaTweens.set(tag, tween);
        return true;
    }

    static function tweenStrum(tag:String, note:Int, property:String, value:Float, duration:Float, ease:String):Bool
    {
        if (PlayState.strumLineNotes == null || note < 0 || note >= PlayState.strumLineNotes.members.length)
            return false;
        var strum:Dynamic = PlayState.strumLineNotes.members[note];
        if (strum == null) return false;
        cancelTween(tag);

        var values:Dynamic = {};
        Reflect.setField(values, property, value);
        var tween:FlxTween = FlxTween.tween(strum, values, Math.max(0.0001, duration), {
            ease: easeFromString(ease),
            onComplete: function(_:FlxTween)
            {
                luaTweens.remove(tag);
                dispatchSharedCallback('onTweenCompleted', [tag]);
            }
        });
        luaTweens.set(tag, tween);
        return true;
    }

    public static function tweenCameraZoom(tag:String, camera:String, value:Float, duration:Float, ease:String):Bool
    {
        var target:FlxCamera = getCamera(camera);
        if (target == null) return false;
        cancelTween(tag);
        var tween:FlxTween = FlxTween.tween(target, {zoom: value}, Math.max(0.0001, duration), {
            ease: easeFromString(ease),
            onComplete: function(_:FlxTween)
            {
                luaTweens.remove(tag);
                dispatchSharedCallback('onTweenCompleted', [tag]);
            }
        });
        luaTweens.set(tag, tween);
        return true;
    }

    static function dispatchSharedCallback(functionName:String, args:Array<Dynamic>):Void
    {
        callOnLuas(functionName, args, true);
        #if HSCRIPT_ALLOWED
        PsychHScriptManager.callOnHScripts(functionName, args, true);
        #end
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
        var totalLoops:Int = loops <= 0 ? 1 : loops;
        var timer:FlxTimer = new FlxTimer().start(Math.max(0.0001, time), function(active:FlxTimer)
        {
            var loopsLeft:Int = active.loopsLeft;
            dispatchSharedCallback('onTimerCompleted', [tag, active.elapsedLoops, loopsLeft]);
            if (active.finished) luaTimers.remove(tag);
        }, totalLoops);
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
            if (tag != null && tag.length > 0) stopSound(tag);
            var path:String = findExternalModFile('sounds/' + sound + '.ogg');
            var audio:Dynamic = path != null ? openfl.media.Sound.fromFile(path) : Paths.sound(sound);
            var flxSound:FlxSound = FlxG.sound.play(audio, volume, false, null, true, function()
            {
                if (tag != null && tag.length > 0) luaSounds.remove(tag);
                dispatchSharedCallback('onSoundFinished', [tag == null ? '' : tag]);
            });
            if (tag != null && tag.length > 0) luaSounds.set(tag, flxSound);
            return true;
        }
        catch (e:Dynamic)
        {
            trace('[PsychLua] playSound falhou: ' + errorText(e));
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
        switch (name == null ? '' : name.toLowerCase())
        {
            case 'hud' | 'camhud': return PlayState.instance == null ? null : PlayState.instance.camHUD;
            case 'game' | 'camgame' | 'other' | 'camother': return FlxG.camera;
            default: return FlxG.camera;
        }
    }

    public static function colorFromString(value:String):FlxColor
    {
        if (value == null || value.trim().length == 0) return FlxColor.WHITE;
        var named:Null<FlxColor> = FlxColor.fromString(value);
        if (named != null) return named;
        var text:String = value.trim().replace('#', '').replace('0x', '').replace('0X', '');
        if (text.length == 6) text = 'FF' + text;
        var parsed:Null<Int> = Std.parseInt('0x' + text);
        return parsed == null ? FlxColor.WHITE : FlxColor.fromInt(parsed);
    }

    static function easeFromString(name:String):Dynamic
    {
        switch (name == null ? '' : name.toLowerCase().trim())
        {
            case 'quadin': return FlxEase.quadIn;
            case 'quadout': return FlxEase.quadOut;
            case 'quadinout': return FlxEase.quadInOut;
            case 'cubein': return FlxEase.cubeIn;
            case 'cubeout': return FlxEase.cubeOut;
            case 'cubeinout': return FlxEase.cubeInOut;
            case 'quartin': return FlxEase.quartIn;
            case 'quartout': return FlxEase.quartOut;
            case 'quartinout': return FlxEase.quartInOut;
            case 'quintin': return FlxEase.quintIn;
            case 'quintout': return FlxEase.quintOut;
            case 'quintinout': return FlxEase.quintInOut;
            case 'sinein': return FlxEase.sineIn;
            case 'sineout': return FlxEase.sineOut;
            case 'sineinout': return FlxEase.sineInOut;
            case 'circin': return FlxEase.circIn;
            case 'circout': return FlxEase.circOut;
            case 'circinout': return FlxEase.circInOut;
            case 'expoin': return FlxEase.expoIn;
            case 'expoout': return FlxEase.expoOut;
            case 'expoinout': return FlxEase.expoInOut;
            case 'backin': return FlxEase.backIn;
            case 'backout': return FlxEase.backOut;
            case 'backinout': return FlxEase.backInOut;
            case 'bouncein': return FlxEase.bounceIn;
            case 'bounceout': return FlxEase.bounceOut;
            case 'bounceinout': return FlxEase.bounceInOut;
            case 'elasticin': return FlxEase.elasticIn;
            case 'elasticout': return FlxEase.elasticOut;
            case 'elasticinout': return FlxEase.elasticInOut;
            case 'smoothstepin': return FlxEase.smoothStepIn;
            case 'smoothstepout': return FlxEase.smoothStepOut;
            case 'smoothstepinout': return FlxEase.smoothStepInOut;
            default: return FlxEase.linear;
        }
    }

    // ---------------------------------------------------------------------
    // Encerramento seguro
    // ---------------------------------------------------------------------

    // ---------------------------------------------------------------------
    // API pública compartilhada com HScript
    // ---------------------------------------------------------------------

    public static function scriptLuaSpriteExists(tag:String):Bool
    {
        return tag != null && luaSprites.exists(tag);
    }

    public static function scriptLuaTextExists(tag:String):Bool
    {
        return tag != null && luaTexts.exists(tag);
    }

    public static function scriptGetPropertyFromMap(mapName:String, key:Dynamic):Dynamic
    {
        var result = tryMapGet(resolveObject(mapName), key);
        return result.found ? result.value : null;
    }

    public static function scriptSetPropertyFromMap(mapName:String, key:Dynamic, value:Dynamic):Dynamic
    {
        if (!tryMapSet(resolveObject(mapName), key, value))
            throw 'setPropertyFromMap: mapa não encontrado: ' + mapName;
        return value;
    }

    public static function scriptRemoveFromGroup(group:String, index:Int, dontDestroy:Bool):Bool
    {
        var target:Dynamic = resolveObject(group);
        if (target == null) return false;
        var member:Dynamic = getGroupMember(group, index, true);
        if (member == null) return false;
        try
        {
            var remove:Dynamic = Reflect.getProperty(target, 'remove');
            if (Reflect.isFunction(remove))
                Reflect.callMethod(target, remove, [member, true]);
            if (!dontDestroy)
            {
                var destroy:Dynamic = Reflect.getProperty(member, 'destroy');
                if (Reflect.isFunction(destroy)) Reflect.callMethod(member, destroy, []);
            }
            return true;
        }
        catch (e:Dynamic) { return false; }
    }

    public static function scriptSetGraphicSize(tag:String, width:Int, height:Int, update:Bool):Bool
    {
        var sprite:FlxSprite = cast resolveObject(tag);
        if (sprite == null) return false;
        sprite.setGraphicSize(width, height);
        if (update) sprite.updateHitbox();
        return true;
    }

    public static function scriptUpdateHitbox(tag:String):Bool
    {
        var sprite:FlxSprite = cast resolveObject(tag);
        if (sprite == null) return false;
        sprite.updateHitbox();
        return true;
    }

    public static function scriptScreenCenter(tag:String, axes:String):Bool
    {
        var sprite:FlxSprite = cast resolveObject(tag);
        if (sprite == null) return false;
        var parsed:String = axes == null ? 'xy' : axes.toLowerCase();
        sprite.screenCenter(parsed == 'x' ? FlxAxes.X : parsed == 'y' ? FlxAxes.Y : FlxAxes.XY);
        return true;
    }

    public static function scriptSetBlendMode(tag:String, blend:String):Bool
    {
        return setBlendMode(tag, blend);
    }

    public static function scriptMakeGraphic(tag:String, width:Int, height:Int, color:String):Bool
    {
        var sprite:FlxSprite = cast resolveObject(tag);
        if (sprite == null) return false;
        sprite.makeGraphic(Std.int(Math.max(1, width)), Std.int(Math.max(1, height)), colorFromString(color));
        return true;
    }

    public static function scriptAddAnimationByPrefix(tag:String, name:String, prefix:String, fps:Int, loop:Bool):Bool
    {
        var sprite:FlxSprite = cast resolveObject(tag);
        if (sprite == null) return false;
        sprite.animation.addByPrefix(name, prefix, fps, loop);
        return true;
    }

    public static function scriptAddAnimationByIndices(tag:String, name:String, prefix:String, indices:Dynamic, fps:Int, loop:Bool):Bool
    {
        var sprite:FlxSprite = cast resolveObject(tag);
        if (sprite == null) return false;
        sprite.animation.addByIndices(name, prefix, parseIndices(indices), '', fps, loop);
        return true;
    }

    public static function scriptPlayAnimation(tag:String, name:String, force:Bool, reverse:Bool, frame:Int):Bool
    {
        return playAnimation(tag, name, force, reverse, frame);
    }

    public static function scriptSetObjectCamera(tag:String, cameraName:String):Bool
    {
        var object:Dynamic = resolveObject(tag);
        var camera:FlxCamera = getCamera(cameraName);
        if (object == null || camera == null) return false;
        try
        {
            Reflect.setProperty(object, 'cameras', [camera]);
            return true;
        }
        catch (e:Dynamic)
        {
            return false;
        }
    }

    public static function scriptSetScrollFactor(tag:String, x:Float, y:Float):Bool
    {
        var sprite:FlxSprite = cast resolveObject(tag);
        if (sprite == null) return false;
        sprite.scrollFactor.set(x, y);
        return true;
    }

    public static function scriptScaleObject(tag:String, x:Float, y:Float, updateHitbox:Bool):Bool
    {
        var sprite:FlxSprite = cast resolveObject(tag);
        if (sprite == null) return false;
        sprite.scale.set(x, y);
        if (updateHitbox) sprite.updateHitbox();
        return true;
    }

    public static function scriptMakeText(tag:String, text:String, width:Float, x:Float, y:Float):Bool
    {
        return makeText(tag, text, width, x, y);
    }

    public static function scriptAddText(tag:String, front:Bool):Bool
    {
        return addText(tag, front);
    }

    public static function scriptRemoveText(tag:String, destroy:Bool):Bool
    {
        return removeText(tag, destroy);
    }

    public static function scriptSetTextString(tag:String, value:String):Bool
    {
        var text:FlxText = luaTexts.get(tag);
        if (text == null) return false;
        text.text = value;
        return true;
    }

    public static function scriptSetTextSize(tag:String, value:Int):Bool
    {
        var text:FlxText = luaTexts.get(tag);
        if (text == null) return false;
        text.size = value;
        return true;
    }

    public static function scriptSetTextColor(tag:String, value:String):Bool
    {
        var text:FlxText = luaTexts.get(tag);
        if (text == null) return false;
        text.color = colorFromString(value);
        return true;
    }

    public static function scriptCameraFlash(cameraName:String, color:String, duration:Float, forced:Bool):Bool
    {
        var camera:FlxCamera = getCamera(cameraName);
        if (camera == null) return false;
        camera.flash(colorFromString(color), duration, null, forced);
        return true;
    }

    public static function scriptCameraShake(cameraName:String, intensity:Float, duration:Float):Bool
    {
        var camera:FlxCamera = getCamera(cameraName);
        if (camera == null) return false;
        camera.shake(intensity, duration);
        return true;
    }

    public static function scriptTriggerEvent(name:String, value1:String, value2:String):Bool
    {
        if (PlayState.instance == null) return false;
        PlayState.instance.triggerEventNote(
            name == null ? '' : name,
            value1 == null ? '' : value1,
            value2 == null ? '' : value2
        );
        return true;
    }

    static function closeCurrentScript():Void
    {
        if (currentCallingScript < 0) return;
        for (script in scripts)
            if (script != null && script.id == currentCallingScript)
            {
                closeScript(script);
                return;
            }
    }

    static function closeScript(script:PsychLua):Void
    {
        if (script == null || script.closed) return;
        script.closed = true;
        if (lua == null) return;

        var base:Int = Lua.gettop(lua);
        Lua.getglobal(lua, '__kadesh_remove_script');
        Lua.pushinteger(lua, script.id);
        Lua.pcall(lua, 1, 0, 0);
        Lua.settop(lua, base);
    }

    public static function destroy():Void
    {
        if (lua != null && scripts.length > 0)
            callOnLuas('onDestroy', [], true);

        for (tag in copyKeys(luaTweens)) cancelTween(tag);
        for (tag in copyKeys(luaTimers)) cancelTimer(tag);
        for (tag in copyKeys(luaSounds)) stopSound(tag);
        for (tag in copyKeys(luaTexts)) removeText(tag, true);
        for (tag in copyKeys(luaSprites)) removeSprite(tag, true);

        shutdownState();
    }

    static function shutdownState():Void
    {
        if (lua != null)
        {
            for (name in callbackNames)
            {
                try
                {
                    Lua_helper.remove_callback(lua, name);
                }
                catch (e:Dynamic) {}
            }
            try
            {
                Lua.close(lua);
            }
            catch (e:Dynamic) {}
        }

        lua = null;
        scripts = [];
        callbackNames = [];
        loadedLogicalPaths = new Map<String, Bool>();
        modRoots = [];
        nextScriptId = 1;
        currentCallingScript = -1;
        initialized = false;
    }

    static function copyKeys<T>(map:Map<String, T>):Array<String>
    {
        var result:Array<String> = [];
        for (key in map.keys()) result.push(key);
        return result;
    }

    // ---------------------------------------------------------------------
    // Conversões seguras de argumentos
    // ---------------------------------------------------------------------

    static function arg(args:Array<Dynamic>, index:Int, ?fallback:Dynamic = null):Dynamic
        return args != null && index >= 0 && index < args.length && args[index] != null ? args[index] : fallback;

    static function stringArg(args:Array<Dynamic>, index:Int, ?fallback:String = ''):String
    {
        var value:Dynamic = arg(args, index, fallback);
        return value == null ? fallback : Std.string(value);
    }

    static function nullableStringArg(args:Array<Dynamic>, index:Int):Null<String>
    {
        var value:Dynamic = arg(args, index, null);
        if (value == null) return null;
        var text:String = Std.string(value);
        return text.length == 0 ? null : text;
    }

    static function floatArg(args:Array<Dynamic>, index:Int, ?fallback:Float = 0):Float
    {
        var parsed:Float = Std.parseFloat(Std.string(arg(args, index, fallback)));
        return Math.isNaN(parsed) ? fallback : parsed;
    }

    static function intArg(args:Array<Dynamic>, index:Int, ?fallback:Int = 0):Int
    {
        var value:Dynamic = arg(args, index, fallback);
        var parsed:Null<Int> = Std.parseInt(Std.string(value));
        if (parsed != null) return parsed;
        var number:Float = Std.parseFloat(Std.string(value));
        return Math.isNaN(number) ? fallback : Std.int(number);
    }

    static function boolArg(args:Array<Dynamic>, index:Int, ?fallback:Bool = false):Bool
    {
        var value:Dynamic = arg(args, index, fallback);
        if (Std.isOfType(value, Bool)) return value;
        var text:String = Std.string(value).toLowerCase().trim();
        if (text == 'true' || text == '1') return true;
        if (text == 'false' || text == '0' || text.length == 0) return false;
        return fallback;
    }

    static function parseIndices(value:Dynamic):Array<Int>
    {
        var result:Array<Int> = [];
        if (value == null) return result;

        if (Std.isOfType(value, Array))
        {
            for (item in (cast value:Array<Dynamic>))
            {
                var number:Null<Int> = Std.parseInt(Std.string(item));
                if (number != null) result.push(number);
            }
            return result;
        }

        for (part in Std.string(value).split(','))
        {
            var number:Null<Int> = Std.parseInt(part.trim());
            if (number != null) result.push(number);
        }
        return result;
    }

    static function parseExcludeInts(value:String):Array<Int>
    {
        return parseIndices(value);
    }

    static function safeLuaString(index:Int):String
    {
        if (lua == null || Lua.type(lua, index) == Lua.LUA_TNIL) return '';
        var value:String = Lua.tostring(lua, index);
        return value == null ? '' : value;
    }

    static function errorText(error:Dynamic):String
    {
        if (error == null) return 'erro desconhecido';
        if (Reflect.hasField(error, 'message'))
        {
            var message:Dynamic = Reflect.field(error, 'message');
            if (message != null) return Std.string(message);
        }
        return Std.string(error);
    }

    static function currentScriptLabel():String
    {
        for (script in scripts)
            if (script != null && script.id == currentCallingScript)
                return script.logicalPath;
        return 'runtime';
    }

    static function fileName(path:String):String
    {
        if (path == null) return '';
        var fixed:String = path.replace('\\', '/');
        var parts:Array<String> = fixed.split('/');
        return parts.length > 0 ? parts[parts.length - 1] : fixed;
    }
}

class PathNormalize
{
    public static function normalize(path:String):String
        return path == null ? '' : path.replace('\\', '/').toLowerCase();

    public static function join(a:String, b:String):String
    {
        var left:String = a == null ? '' : a.replace('\\', '/');
        var right:String = b == null ? '' : b.replace('\\', '/');
        while (left.endsWith('/')) left = left.substr(0, left.length - 1);
        while (right.startsWith('/')) right = right.substr(1);
        return left.length == 0 ? right : left + '/' + right;
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
