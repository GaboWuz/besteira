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
import llua.Convert;
import llua.Lua;
import llua.LuaL;
import llua.State;
import openfl.display.BitmapData;
import sys.FileSystem;
import sys.io.File;

using StringTools;

/**
 * Camada de compatibilidade com a API Lua da Psych Engine 0.6.3.
 *
 * Ela foi desenhada para ser segura: erro em um script fecha apenas o script,
 * nunca o jogo inteiro. Objetos internos e o mods folder continuam opcionais.
 */
class PsychLua
{
    public static inline var Function_Continue:Int = 0;
    public static inline var Function_Stop:Int = 1;

    public var lua:State;
    public var scriptName:String;
    public var closed:Bool = false;

    public function new(path:String)
    {
        scriptName = path;
        lua = LuaL.newstate();
        LuaL.openlibs(lua);
        Lua.init_callbacks(lua);

        registerGlobals();
        registerCallbacks();

        var result:Int = LuaL.dofile(lua, path);
        if (result != 0)
        {
            var message:String = Lua.tostring(lua, -1);
            Lua.pop(lua, 1);
            trace('[PsychLua] Erro ao carregar "' + path + '": ' + message);
            close();
            return;
        }

        call('onCreate', []);
    }

    function registerGlobals():Void
    {
        set('Function_Continue', Function_Continue);
        set('Function_Stop', Function_Stop);
        set('Function_StopLua', Function_Stop);
        set('Function_StopHScript', Function_Stop);
        set('version', 'Kadesh PsychLua Core 1.0');
        set('buildTarget', #if android 'android' #else 'cpp' #end);
    }

    function registerCallbacks():Void
    {
        Lua_helper.add_callback(lua, 'debugPrint', function(text:Dynamic = '', ?color:String = 'WHITE')
        {
            trace('[Lua][' + PathTools.fileName(scriptName) + '] ' + Std.string(text));
        });

        Lua_helper.add_callback(lua, 'getProperty', function(path:String)
        {
            return getPropertyPath(path);
        });

        Lua_helper.add_callback(lua, 'setProperty', function(path:String, value:Dynamic)
        {
            return setPropertyPath(path, value);
        });

        Lua_helper.add_callback(lua, 'getPropertyFromGroup', function(group:String, index:Int, field:String)
        {
            var member:Dynamic = getGroupMember(group, index);
            return member == null ? null : getNested(member, field);
        });

        Lua_helper.add_callback(lua, 'setPropertyFromGroup', function(group:String, index:Int, field:String, value:Dynamic)
        {
            var member:Dynamic = getGroupMember(group, index);
            return member == null ? false : setNested(member, field, value);
        });

        Lua_helper.add_callback(lua, 'removeFromGroup', function(group:String, index:Int, ?dontDestroy:Bool = false)
        {
            var target:Dynamic = resolveObject(group);
            if (target == null || !Reflect.hasField(target, 'members')) return false;
            var members:Array<Dynamic> = cast Reflect.getProperty(target, 'members');
            if (index < 0 || index >= members.length) return false;
            var object:Dynamic = members[index];
            Reflect.callMethod(target, Reflect.getProperty(target, 'remove'), [object, true]);
            if (!dontDestroy && object != null && Reflect.hasField(object, 'destroy'))
                Reflect.callMethod(object, Reflect.getProperty(object, 'destroy'), []);
            return true;
        });

        Lua_helper.add_callback(lua, 'getPropertyFromClass', function(className:String, path:String)
        {
            var cls:Dynamic = Type.resolveClass(className);
            if (cls == null) return null;
            return getNested(cls, path);
        });

        Lua_helper.add_callback(lua, 'setPropertyFromClass', function(className:String, path:String, value:Dynamic)
        {
            var cls:Dynamic = Type.resolveClass(className);
            if (cls == null) return false;
            return setNested(cls, path, value);
        });

        Lua_helper.add_callback(lua, 'makeLuaSprite', function(tag:String, image:String, ?x:Float = 0, ?y:Float = 0)
        {
            return PsychLuaManager.makeSprite(tag, image, x, y, false);
        });

        Lua_helper.add_callback(lua, 'makeAnimatedLuaSprite', function(tag:String, image:String, ?x:Float = 0, ?y:Float = 0, ?spriteType:String = 'sparrow')
        {
            return PsychLuaManager.makeSprite(tag, image, x, y, true, spriteType);
        });

        Lua_helper.add_callback(lua, 'addLuaSprite', function(tag:String, ?front:Bool = false)
        {
            return PsychLuaManager.addSprite(tag, front);
        });

        Lua_helper.add_callback(lua, 'removeLuaSprite', function(tag:String, ?destroy:Bool = true)
        {
            return PsychLuaManager.removeSprite(tag, destroy);
        });

        Lua_helper.add_callback(lua, 'makeGraphic', function(tag:String, width:Int, height:Int, color:String)
        {
            var sprite:FlxSprite = PsychLuaManager.luaSprites.get(tag);
            if (sprite == null) return false;
            sprite.makeGraphic(width, height, PsychLuaManager.colorFromString(color));
            return true;
        });

        Lua_helper.add_callback(lua, 'loadGraphic', function(tag:String, image:String, ?gridX:Int = 0, ?gridY:Int = 0)
        {
            return PsychLuaManager.loadGraphic(tag, image, gridX, gridY);
        });

        Lua_helper.add_callback(lua, 'addAnimationByPrefix', function(tag:String, name:String, prefix:String, ?fps:Int = 24, ?loop:Bool = false)
        {
            var sprite:FlxSprite = cast resolveObject(tag);
            if (sprite == null) return false;
            sprite.animation.addByPrefix(name, prefix, fps, loop);
            return true;
        });

        Lua_helper.add_callback(lua, 'addAnimationByIndices', function(tag:String, name:String, prefix:String, indices:String, ?fps:Int = 24, ?loop:Bool = false)
        {
            var sprite:FlxSprite = cast resolveObject(tag);
            if (sprite == null) return false;
            var parsed:Array<Int> = [];
            for (part in indices.split(','))
            {
                var number:Null<Int> = Std.parseInt(part.trim());
                if (number != null) parsed.push(number);
            }
            sprite.animation.addByIndices(name, prefix, parsed, '', fps, loop);
            return true;
        });

        Lua_helper.add_callback(lua, 'objectPlayAnimation', function(tag:String, name:String, ?force:Bool = false, ?reverse:Bool = false, ?startFrame:Int = 0)
        {
            var object:Dynamic = resolveObject(tag);
            if (object == null) return false;
            if (Std.isOfType(object, Character))
                (cast object:Character).playAnim(name, force, reverse, startFrame);
            else if (Reflect.hasField(object, 'animation'))
                Reflect.callMethod(Reflect.getProperty(object, 'animation'), Reflect.getProperty(Reflect.getProperty(object, 'animation'), 'play'), [name, force, reverse, startFrame]);
            return true;
        });

        Lua_helper.add_callback(lua, 'characterPlayAnim', function(character:String, animation:String, ?forced:Bool = false)
        {
            var target:Dynamic = resolveObject(character);
            if (target == null || !Std.isOfType(target, Character)) return false;
            (cast target:Character).playAnim(animation, forced);
            return true;
        });

        Lua_helper.add_callback(lua, 'setObjectCamera', function(tag:String, camera:String)
        {
            var sprite:FlxSprite = cast resolveObject(tag);
            var target:FlxCamera = PsychLuaManager.getCamera(camera);
            if (sprite == null || target == null) return false;
            sprite.cameras = [target];
            return true;
        });

        Lua_helper.add_callback(lua, 'setScrollFactor', function(tag:String, x:Float, y:Float)
        {
            var sprite:FlxSprite = cast resolveObject(tag);
            if (sprite == null) return false;
            sprite.scrollFactor.set(x, y);
            return true;
        });

        Lua_helper.add_callback(lua, 'scaleObject', function(tag:String, x:Float, y:Float, ?updateHitbox:Bool = true)
        {
            var sprite:FlxSprite = cast resolveObject(tag);
            if (sprite == null) return false;
            sprite.scale.set(x, y);
            if (updateHitbox) sprite.updateHitbox();
            return true;
        });

        Lua_helper.add_callback(lua, 'setObjectOrder', function(tag:String, order:Int)
        {
            return PsychLuaManager.setObjectOrder(tag, order);
        });

        Lua_helper.add_callback(lua, 'getObjectOrder', function(tag:String)
        {
            return PsychLuaManager.getObjectOrder(tag);
        });

        Lua_helper.add_callback(lua, 'doTweenX', function(tag:String, object:String, value:Float, duration:Float, ?ease:String = 'linear')
        {
            return PsychLuaManager.tweenProperty(tag, object, 'x', value, duration, ease);
        });
        Lua_helper.add_callback(lua, 'doTweenY', function(tag:String, object:String, value:Float, duration:Float, ?ease:String = 'linear')
        {
            return PsychLuaManager.tweenProperty(tag, object, 'y', value, duration, ease);
        });
        Lua_helper.add_callback(lua, 'doTweenAlpha', function(tag:String, object:String, value:Float, duration:Float, ?ease:String = 'linear')
        {
            return PsychLuaManager.tweenProperty(tag, object, 'alpha', value, duration, ease);
        });
        Lua_helper.add_callback(lua, 'doTweenAngle', function(tag:String, object:String, value:Float, duration:Float, ?ease:String = 'linear')
        {
            return PsychLuaManager.tweenProperty(tag, object, 'angle', value, duration, ease);
        });
        Lua_helper.add_callback(lua, 'doTweenZoom', function(tag:String, camera:String, value:Float, duration:Float, ?ease:String = 'linear')
        {
            return PsychLuaManager.tweenCameraZoom(tag, camera, value, duration, ease);
        });
        Lua_helper.add_callback(lua, 'cancelTween', function(tag:String)
        {
            return PsychLuaManager.cancelTween(tag);
        });

        Lua_helper.add_callback(lua, 'runTimer', function(tag:String, time:Float, ?loops:Int = 1)
        {
            return PsychLuaManager.runTimer(tag, time, loops);
        });
        Lua_helper.add_callback(lua, 'cancelTimer', function(tag:String)
        {
            return PsychLuaManager.cancelTimer(tag);
        });

        Lua_helper.add_callback(lua, 'playSound', function(sound:String, ?volume:Float = 1, ?tag:String = null)
        {
            return PsychLuaManager.playSound(sound, volume, tag);
        });
        Lua_helper.add_callback(lua, 'stopSound', function(tag:String)
        {
            return PsychLuaManager.stopSound(tag);
        });

        Lua_helper.add_callback(lua, 'cameraFlash', function(camera:String, color:String, duration:Float, ?forced:Bool = false)
        {
            var target:FlxCamera = PsychLuaManager.getCamera(camera);
            if (target == null) return false;
            target.flash(PsychLuaManager.colorFromString(color), duration, null, forced);
            return true;
        });

        Lua_helper.add_callback(lua, 'cameraShake', function(camera:String, intensity:Float, duration:Float)
        {
            var target:FlxCamera = PsychLuaManager.getCamera(camera);
            if (target == null) return false;
            target.shake(intensity, duration);
            return true;
        });

        Lua_helper.add_callback(lua, 'triggerEvent', function(name:String, ?value1:String = '', ?value2:String = '')
        {
            if (PlayState.instance != null)
                PlayState.instance.triggerEventNote(name, value1, value2);
        });

        Lua_helper.add_callback(lua, 'getSongPosition', function()
        {
            return Conductor.songPosition;
        });

        Lua_helper.add_callback(lua, 'getColorFromHex', function(value:String)
        {
            return PsychLuaManager.colorFromString(value);
        });

        Lua_helper.add_callback(lua, 'precacheImage', function(image:String) return true);
        Lua_helper.add_callback(lua, 'precacheSound', function(sound:String) return true);
        Lua_helper.add_callback(lua, 'close', function(?printMessage:Bool = true) close());
    }

    public function call(functionName:String, args:Array<Dynamic>):Dynamic
    {
        if (closed || lua == null) return null;

        Lua.getglobal(lua, functionName);
        if (Lua.type(lua, -1) != Lua.LUA_TFUNCTION)
        {
            Lua.pop(lua, 1);
            return null;
        }

        for (argument in args) Convert.toLua(lua, argument);
        var result:Int = Lua.pcall(lua, args.length, 1, 0);
        if (result != 0)
        {
            var message:String = Lua.tostring(lua, -1);
            Lua.pop(lua, 1);
            trace('[PsychLua] ' + PathTools.fileName(scriptName) + ' -> ' + functionName + ': ' + message);
            return null;
        }

        var value:Dynamic = Convert.fromLua(lua, -1);
        Lua.pop(lua, 1);
        return value;
    }

    public function set(name:String, value:Dynamic):Void
    {
        if (closed || lua == null) return;
        Convert.toLua(lua, value);
        Lua.setglobal(lua, name);
    }

    public function close():Void
    {
        if (closed) return;
        closed = true;
        if (lua != null)
        {
            Lua.close(lua);
            lua = null;
        }
    }

    function resolveObject(name:String):Dynamic
    {
        return PsychLuaManager.resolveObject(name);
    }

    function getGroupMember(group:String, index:Int):Dynamic
    {
        var target:Dynamic = resolveObject(group);
        if (target == null) return null;
        var members:Dynamic = Reflect.getProperty(target, 'members');
        if (members == null || !Std.isOfType(members, Array)) return null;
        var array:Array<Dynamic> = cast members;
        return index >= 0 && index < array.length ? array[index] : null;
    }

    function getPropertyPath(path:String):Dynamic
    {
        if (path == null || path.trim().length == 0) return null;
        var parts:Array<String> = path.split('.');
        var root:Dynamic = resolveObject(parts.shift());
        if (root == null) return null;
        return getNested(root, parts.join('.'));
    }

    function setPropertyPath(path:String, value:Dynamic):Bool
    {
        if (path == null || path.trim().length == 0) return false;
        var parts:Array<String> = path.split('.');
        var root:Dynamic = resolveObject(parts.shift());
        if (root == null) return false;
        return setNested(root, parts.join('.'), value);
    }

    static function getNested(root:Dynamic, path:String):Dynamic
    {
        if (root == null || path == null || path.length == 0) return root;
        var current:Dynamic = root;
        for (field in path.split('.'))
        {
            if (current == null) return null;
            var index:Null<Int> = Std.parseInt(field);
            if (index != null && Std.isOfType(current, Array))
            {
                var array:Array<Dynamic> = cast current;
                current = index >= 0 && index < array.length ? array[index] : null;
            }
            else current = Reflect.getProperty(current, field);
        }
        return current;
    }

    static function setNested(root:Dynamic, path:String, value:Dynamic):Bool
    {
        if (root == null || path == null || path.length == 0) return false;
        var parts:Array<String> = path.split('.');
        var field:String = parts.pop();
        var parent:Dynamic = getNested(root, parts.join('.'));
        if (parent == null) return false;

        var index:Null<Int> = Std.parseInt(field);
        if (index != null && Std.isOfType(parent, Array))
        {
            var array:Array<Dynamic> = cast parent;
            if (index < 0 || index >= array.length) return false;
            array[index] = value;
        }
        else Reflect.setProperty(parent, field, value);
        return true;
    }
}

class PathTools
{
    public static function fileName(path:String):String
    {
        if (path == null) return '';
        var fixed:String = path.replace('\\', '/');
        var parts:Array<String> = fixed.split('/');
        return parts.length > 0 ? parts[parts.length - 1] : fixed;
    }
}
#else
class PsychLua
{
    public static inline var Function_Continue:Int = 0;
    public static inline var Function_Stop:Int = 1;
}
#end
