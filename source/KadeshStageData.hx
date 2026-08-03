package;

import flixel.FlxCamera;
import flixel.FlxG;
import flixel.FlxSprite;
import flixel.graphics.frames.FlxAtlasFrames;
import flixel.util.FlxColor;
import haxe.Json;

#if sys
import sys.FileSystem;
#end

using StringTools;

typedef KadeshStageFile =
{
    @:optional var directory:String;
    @:optional var defaultZoom:Float;
    @:optional var isPixelStage:Bool;
    @:optional var stageUI:String;
    @:optional var boyfriend:Array<Dynamic>;
    @:optional var girlfriend:Array<Dynamic>;
    @:optional var opponent:Array<Dynamic>;
    @:optional var hide_girlfriend:Bool;
    @:optional var camera_boyfriend:Array<Dynamic>;
    @:optional var camera_opponent:Array<Dynamic>;
    @:optional var camera_girlfriend:Array<Dynamic>;
    @:optional var camera_speed:Float;
    @:optional var objects:Array<Dynamic>;
}

/**
 * Stage JSON opcional para o mods folder.
 *
 * Se stages/<stage>.json não existir ou estiver inválido, a PlayState usa o
 * switch antigo da Kade sem nenhuma alteração.
 */
class KadeshStageData
{
    public static var current(default, null):KadeshStageData = null;

    public var stageName(default, null):String;
    public var sourcePath(default, null):String;
    public var data(default, null):KadeshStageFile;
    public var variables:Map<String, FlxSprite> = new Map<String, FlxSprite>();

    var backObjects:Array<FlxSprite> = [];
    var frontObjects:Array<FlxSprite> = [];
    var beatObjects:Array<{sprite:KadeshStageSprite, every:Int, animation:String}> = [];
    var built:Bool = false;

    public function new(stageName:String, sourcePath:String, data:KadeshStageFile)
    {
        this.stageName = stageName;
        this.sourcePath = sourcePath;
        this.data = data;
    }

    public static function load(stageName:String):Null<KadeshStageData>
    {
        current = null;
        if (stageName == null || stageName.trim().length == 0)
            return null;

        var path:Null<String> = KadeshModPaths.find('stages/' + stageName + '.json');
        if (path == null)
            return null;

        try
        {
            var raw:String = KadeshModPaths.readText('stages/' + stageName + '.json');
            if (raw == null || raw.trim().length == 0)
                throw 'O JSON está vazio.';

            var parsed:Dynamic = Json.parse(raw);
            if (parsed == null)
                throw 'O JSON não contém um objeto.';

            var stage:KadeshStageData = new KadeshStageData(stageName, path, cast parsed);
            stage.applyDefaults();
            current = stage;
            trace('[KadeshStageData] Stage externo carregado: ' + path);
            return stage;
        }
        catch (e:Dynamic)
        {
            KadeshScriptDebug.report('STAGE JSON', path, Std.string(e), 'load');
            current = null;
            return null;
        }
    }

    function applyDefaults():Void
    {
        if (data.defaultZoom == null || Math.isNaN(data.defaultZoom)) data.defaultZoom = 0.9;
        if (data.boyfriend == null) data.boyfriend = [770, 450];
        if (data.girlfriend == null) data.girlfriend = [400, 130];
        if (data.opponent == null) data.opponent = [100, 100];
        if (data.camera_boyfriend == null) data.camera_boyfriend = [0, 0];
        if (data.camera_opponent == null) data.camera_opponent = [0, 0];
        if (data.camera_girlfriend == null) data.camera_girlfriend = [0, 0];
        if (data.camera_speed == null || Math.isNaN(data.camera_speed)) data.camera_speed = 1;
        if (data.hide_girlfriend == null) data.hide_girlfriend = false;
        if (data.objects == null) data.objects = [];
    }

    public function defaultZoom():Float
    {
        return data.defaultZoom == null ? 0.9 : data.defaultZoom;
    }

    public function cameraSpeed():Float
    {
        return data.camera_speed == null ? 1 : Math.max(0.01, data.camera_speed);
    }

    public function boyfriendPosition():Array<Float>
    {
        return pair(data.boyfriend, 770, 450);
    }

    public function girlfriendPosition():Array<Float>
    {
        return pair(data.girlfriend, 400, 130);
    }

    public function opponentPosition():Array<Float>
    {
        return pair(data.opponent, 100, 100);
    }

    public function boyfriendCamera():Array<Float>
    {
        return pair(data.camera_boyfriend, 0, 0);
    }

    public function girlfriendCamera():Array<Float>
    {
        return pair(data.camera_girlfriend, 0, 0);
    }

    public function opponentCamera():Array<Float>
    {
        return pair(data.camera_opponent, 0, 0);
    }

    public function hideGirlfriend():Bool
    {
        return data.hide_girlfriend == true;
    }

    public function build():Void
    {
        if (built)
            return;
        built = true;

        for (entry in data.objects)
        {
            try
            {
                var sprite:KadeshStageSprite = createObject(entry);
                if (sprite == null)
                    continue;

                var tag:String = stringField(entry, 'tag', 'stageObject' + (backObjects.length + frontObjects.length));
                if (tag.length == 0)
                    tag = 'stageObject' + (backObjects.length + frontObjects.length);

                variables.set(tag, sprite);
                sprite.kadeshTag = tag;

                var front:Bool = boolField(entry, 'front', false);
                if (front) frontObjects.push(sprite); else backObjects.push(sprite);

                var every:Int = intField(entry, 'danceEveryBeats', 0);
                var danceAnimation:String = stringField(entry, 'danceAnimation', '');
                if (every > 0 && danceAnimation.length > 0)
                    beatObjects.push({sprite: sprite, every: every, animation: danceAnimation});
            }
            catch (e:Dynamic)
            {
                KadeshScriptDebug.report('STAGE OBJECT', sourcePath, Std.string(e), 'objects');
            }
        }
    }

    public function addBack(state:PlayState):Void
    {
        build();
        for (sprite in backObjects)
            if (sprite != null && state.members.indexOf(sprite) < 0)
                state.add(sprite);
    }

    public function addFront(state:PlayState):Void
    {
        build();
        for (sprite in frontObjects)
            if (sprite != null && state.members.indexOf(sprite) < 0)
                state.add(sprite);
    }

    public function beatHit(beat:Int):Void
    {
        for (entry in beatObjects)
        {
            if (entry.sprite != null && entry.every > 0 && beat % entry.every == 0)
                entry.sprite.playStageAnimation(entry.animation, true);
        }
    }

    public function getObject(tag:String):Dynamic
    {
        return tag != null && variables.exists(tag) ? variables.get(tag) : null;
    }

    public function destroy():Void
    {
        // Os sprites pertencem à PlayState e são destruídos por super.destroy().
        // Aqui limpamos somente as referências para evitar double-destroy.
        backObjects = [];
        frontObjects = [];
        beatObjects = [];
        variables = new Map<String, FlxSprite>();
        if (current == this)
            current = null;
    }

    function createObject(entry:Dynamic):KadeshStageSprite
    {
        if (entry == null)
            return null;

        var x:Float = floatField(entry, 'x', 0);
        var y:Float = floatField(entry, 'y', 0);
        var sprite:KadeshStageSprite = new KadeshStageSprite(x, y);
        var objectType:String = stringField(entry, 'type', 'sprite').toLowerCase();
        var image:String = stringField(entry, 'image', '');
        var atlas:String = stringField(entry, 'atlas', 'sparrow').toLowerCase();
        var animations:Dynamic = Reflect.field(entry, 'animations');
        var animated:Bool = boolField(entry, 'animated', false)
            || (animations != null && Std.isOfType(animations, Array));

        if (objectType == 'solid' || objectType == 'graphic' || image.length == 0)
        {
            var width:Int = Std.int(Math.max(1, intField(entry, 'width', 1)));
            var height:Int = Std.int(Math.max(1, intField(entry, 'height', 1)));
            sprite.makeGraphic(width, height, colorField(entry, 'color', FlxColor.WHITE));
        }
        else if (animated)
        {
            sprite.frames = KadeshModAssets.loadAtlas(image, atlas);
            addAnimations(sprite, animations);
        }
        else
        {
            KadeshModAssets.loadImageInto(sprite, image);
        }

        var scroll:Array<Float> = pair(Reflect.field(entry, 'scrollFactor'), 1, 1);
        sprite.scrollFactor.set(scroll[0], scroll[1]);

        var scale:Array<Float> = pair(Reflect.field(entry, 'scale'), 1, 1);
        sprite.scale.set(scale[0], scale[1]);
        if (boolField(entry, 'updateHitbox', true))
            sprite.updateHitbox();

        sprite.alpha = floatField(entry, 'alpha', 1);
        sprite.angle = floatField(entry, 'angle', 0);
        sprite.flipX = boolField(entry, 'flipX', false);
        sprite.flipY = boolField(entry, 'flipY', false);
        sprite.visible = boolField(entry, 'visible', true);
        sprite.active = boolField(entry, 'active', true);
        sprite.antialiasing = boolField(entry, 'antialiasing', true);

        var camera:String = stringField(entry, 'camera', 'game').toLowerCase();
        if (camera == 'hud' || camera == 'camhud')
        {
            var hud:FlxCamera = PlayState.instance == null ? null : PlayState.instance.camHUD;
            if (hud != null) sprite.cameras = [hud];
        }

        var initial:String = stringField(entry, 'initialAnimation', '');
        if (initial.length > 0)
            sprite.playStageAnimation(initial, true);

        return sprite;
    }

    function addAnimations(sprite:KadeshStageSprite, value:Dynamic):Void
    {
        if (value == null || !Std.isOfType(value, Array))
            return;

        for (animationData in (cast value:Array<Dynamic>))
        {
            if (animationData == null) continue;
            var name:String = stringField(animationData, 'name', '');
            var prefix:String = stringField(animationData, 'prefix', '');
            if (name.length == 0 || prefix.length == 0) continue;

            var fps:Int = intField(animationData, 'fps', 24);
            var loop:Bool = boolField(animationData, 'loop', false);
            var indices:Dynamic = Reflect.field(animationData, 'indices');

            if (indices != null && Std.isOfType(indices, Array))
            {
                var parsed:Array<Int> = [];
                for (item in (cast indices:Array<Dynamic>)) parsed.push(Std.int(item));
                sprite.animation.addByIndices(name, prefix, parsed, '', fps, loop);
            }
            else
            {
                sprite.animation.addByPrefix(name, prefix, fps, loop);
            }

            var offset:Array<Float> = pair(Reflect.field(animationData, 'offset'), 0, 0);
            sprite.animationOffsets.set(name, offset);
        }
    }

    static function pair(value:Dynamic, fallbackX:Float, fallbackY:Float):Array<Float>
    {
        if (value != null && Std.isOfType(value, Array))
        {
            var array:Array<Dynamic> = cast value;
            return [
                array.length > 0 ? parseFloat(array[0], fallbackX) : fallbackX,
                array.length > 1 ? parseFloat(array[1], fallbackY) : fallbackY
            ];
        }
        return [fallbackX, fallbackY];
    }

    static function parseFloat(value:Dynamic, fallback:Float):Float
    {
        if (value == null) return fallback;
        var parsed:Float = Std.parseFloat(Std.string(value));
        return Math.isNaN(parsed) ? fallback : parsed;
    }

    static function stringField(object:Dynamic, field:String, fallback:String):String
    {
        var value:Dynamic = Reflect.field(object, field);
        return value == null ? fallback : Std.string(value);
    }

    static function floatField(object:Dynamic, field:String, fallback:Float):Float
    {
        return parseFloat(Reflect.field(object, field), fallback);
    }

    static function intField(object:Dynamic, field:String, fallback:Int):Int
    {
        var value:Dynamic = Reflect.field(object, field);
        if (value == null) return fallback;
        var parsed:Null<Int> = Std.parseInt(Std.string(value));
        return parsed == null ? fallback : parsed;
    }

    static function boolField(object:Dynamic, field:String, fallback:Bool):Bool
    {
        var value:Dynamic = Reflect.field(object, field);
        if (value == null) return fallback;
        if (Std.isOfType(value, Bool)) return value;
        var text:String = Std.string(value).toLowerCase().trim();
        if (text == 'true' || text == '1' || text == 'yes' || text == 'sim') return true;
        if (text == 'false' || text == '0' || text == 'no' || text == 'nao' || text == 'não') return false;
        return fallback;
    }

    static function colorField(object:Dynamic, field:String, fallback:FlxColor):FlxColor
    {
        var value:Dynamic = Reflect.field(object, field);
        if (value == null) return fallback;
        var text:String = Std.string(value).trim();
        var parsed:Null<FlxColor> = FlxColor.fromString(text.startsWith('#') || text.toLowerCase().startsWith('0x') ? text : '#' + text);
        return parsed == null ? fallback : parsed;
    }
}

class KadeshStageSprite extends FlxSprite
{
    public var kadeshTag:String = '';
    public var animationOffsets:Map<String, Array<Float>> = new Map<String, Array<Float>>();

    public function new(x:Float = 0, y:Float = 0)
    {
        super(x, y);
    }

    public function playStageAnimation(name:String, ?force:Bool = false):Bool
    {
        if (animation.getByName(name) == null)
            return false;
        animation.play(name, force);
        applyAnimationOffset(name);
        return true;
    }

    override public function update(elapsed:Float):Void
    {
        super.update(elapsed);
        if (animation.curAnim != null)
            applyAnimationOffset(animation.curAnim.name);
    }

    function applyAnimationOffset(name:String):Void
    {
        if (!animationOffsets.exists(name))
        {
            offset.set();
            return;
        }

        var value:Array<Float> = animationOffsets.get(name);
        offset.set(value.length > 0 ? value[0] : 0, value.length > 1 ? value[1] : 0);
    }
}
