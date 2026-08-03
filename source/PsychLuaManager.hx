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
        + '  local ok, result = pcall(chunk)\n'
        + '  if not ok then return false, tostring(result) end\n'
        + '  __kadesh_scripts[id] = env\n'
        + '  return true, ""\n'
        + 'end\n'
        + 'function __kadesh_call_script(id, callbackName, ...)\n'
        + '  local env = __kadesh_scripts[id]\n'
        + '  if not env then return false, nil, "ambiente Lua não encontrado" end\n'
        + '  local callback = env[callbackName]\n'
        + '  if type(callback) ~= "function" then return true, nil, "" end\n'
        + '  local ok, result = pcall(callback, ...)\n'
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
            trace('[PsychLua] Lua foi desativado para esta música: ' + errorText(e));
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
            return;
        }

        var ok:Bool = Lua.toboolean(lua, -2);
        var message:String = safeLuaString(-1);
        Lua.settop(lua, base);
        currentCallingScript = -1;

        if (!ok)
        {
            trace('[PsychLua] Erro em ' + logicalPath + ': ' + message);
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

        if (script.errorCount >= 3)
        {
            trace('[PsychLua] Script desativado após 3 erros: ' + script.logicalPath);
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

        addSafeCallback('getProperty', function(a) return getPropertyPath(stringArg(a, 0)));
        addSafeCallback('setProperty', function(a) return setPropertyPath(stringArg(a, 0), arg(a, 1)));

        addSafeCallback('getPropertyFromGroup', function(a) {
            var member:Dynamic = getGroupMember(stringArg(a, 0), intArg(a, 1), true);
            return member == null ? null : getNested(member, stringArg(a, 2));
        });
        addSafeCallback('setPropertyFromGroup', function(a) {
            var member:Dynamic = getGroupMember(stringArg(a, 0), intArg(a, 1), true);
            return member == null ? false : setNested(member, stringArg(a, 2), arg(a, 3));
        });
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

        addSafeCallback('getPropertyFromClass', function(a) {
            var cls:Dynamic = Type.resolveClass(stringArg(a, 0));
            return cls == null ? null : getNested(cls, stringArg(a, 1));
        });
        addSafeCallback('setPropertyFromClass', function(a) {
            var cls:Dynamic = Type.resolveClass(stringArg(a, 0));
            return cls == null ? false : setNested(cls, stringArg(a, 1), arg(a, 2));
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
        addSafeCallback('triggerEvent', function(a) {
            if (PlayState.instance != null)
                PlayState.instance.triggerEventNote(stringArg(a, 0), stringArg(a, 1), stringArg(a, 2));
            return true;
        });

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
                trace('[PsychLua callback] ' + name + ': ' + errorText(e));
                return null;
            }
        });

        Lua_helper.add_callback(lua, name, wrapped);
        callbackNames.push(name);
    }

    // ---------------------------------------------------------------------
    // Objetos e propriedades
    // ---------------------------------------------------------------------

    public static function resolveObject(name:String):Dynamic
    {
        if (name == null) return null;
        var id:String = name.trim();
        if (luaSprites.exists(id)) return luaSprites.get(id);
        if (luaTexts.exists(id)) return luaTexts.get(id);

        switch (id)
        {
            case 'boyfriend' | 'bf': return PlayState.boyfriend;
            case 'dad' | 'opponent': return PlayState.dad;
            case 'gf' | 'girlfriend': return PlayState.gf;
            // A Kade não possui os três grupos da Psych; aliases apontam para
            // os personagens correspondentes para scripts simples.
            case 'boyfriendGroup': return PlayState.boyfriend;
            case 'dadGroup': return PlayState.dad;
            case 'gfGroup': return PlayState.gf;
            case 'camGame': return FlxG.camera;
            case 'camHUD': return PlayState.instance == null ? null : PlayState.instance.camHUD;
            case 'notes': return PlayState.instance == null ? null : PlayState.instance.notes;
            case 'unspawnNotes': return PlayState.instance == null ? null : PlayState.instance.unspawnNotes;
            case 'eventNotes': return PlayState.instance == null ? null : PlayState.instance.eventNotes;
            case 'playerStrums': return PlayState.playerStrums;
            case 'opponentStrums' | 'cpuStrums': return PlayState.cpuStrums;
            case 'strumLineNotes': return PlayState.strumLineNotes;
            default:
                if (PlayState.instance != null && Reflect.hasField(PlayState.instance, id))
                    return Reflect.getProperty(PlayState.instance, id);
        }
        return null;
    }

    static function normalizePropertyPath(path:String):String
    {
        if (path == null) return '';
        var result:String = path.trim();
        var bracket:EReg = ~/\[([0-9]+)\]/g;
        result = bracket.replace(result, '.$1');
        while (result.startsWith('.')) result = result.substr(1);
        return result;
    }

    static function getPropertyPath(path:String):Dynamic
    {
        var normalized:String = normalizePropertyPath(path);
        if (normalized.length == 0) return null;
        var parts:Array<String> = normalized.split('.');
        var first:String = parts[0];
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
        if (normalized.length == 0) return false;
        var parts:Array<String> = normalized.split('.');
        var first:String = parts[0];
        var root:Dynamic = resolveObject(first);

        if (root != null)
        {
            parts.shift();
            if (parts.length == 0) return false;
            return setNested(root, parts.join('.'), value);
        }

        return PlayState.instance != null && setNested(PlayState.instance, normalized, value);
    }

    static function getNested(root:Dynamic, path:String):Dynamic
    {
        if (root == null || path == null || path.length == 0) return root;
        var current:Dynamic = root;

        for (field in normalizePropertyPath(path).split('.'))
        {
            if (current == null) return null;
            if (field == 'length' && hasLength(current))
            {
                current = current.length;
                continue;
            }
            var index:Null<Int> = Std.parseInt(field);
            if (index != null && hasLength(current))
            {
                if (index < 0 || index >= current.length) return null;
                current = current[index];
            }
            else if (Reflect.hasField(current, field))
                current = Reflect.getProperty(current, field);
            else
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
        if (index != null && hasLength(parent))
        {
            if (index < 0 || index >= parent.length) return false;
            parent[index] = value;
            return true;
        }

        Reflect.setProperty(parent, field, value);
        return true;
    }

    static function hasLength(value:Dynamic):Bool
    {
        return value != null && Reflect.hasField(value, 'length');
    }

    static function getGroupMember(group:String, index:Int, allowArray:Bool):Dynamic
    {
        var target:Dynamic = resolveObject(group);
        if (target == null) return null;

        var members:Dynamic = Reflect.hasField(target, 'members')
            ? Reflect.getProperty(target, 'members')
            : (allowArray && hasLength(target) ? target : null);

        if (members == null || index < 0 || index >= members.length)
            return null;
        return members[index];
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
                callOnLuas('onTweenCompleted', [tag], true);
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
                callOnLuas('onTweenCompleted', [tag], true);
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
        var totalLoops:Int = loops <= 0 ? 1 : loops;
        var timer:FlxTimer = new FlxTimer().start(Math.max(0.0001, time), function(active:FlxTimer)
        {
            var loopsLeft:Int = active.loopsLeft;
            callOnLuas('onTimerCompleted', [tag, active.elapsedLoops, loopsLeft], true);
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
                callOnLuas('onSoundFinished', [tag == null ? '' : tag], true);
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
