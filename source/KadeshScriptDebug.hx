package;

import flixel.FlxCamera;
import flixel.FlxG;
import flixel.text.FlxText;
import flixel.text.FlxText.FlxTextAlign;
import flixel.text.FlxText.FlxTextBorderStyle;
import flixel.util.FlxColor;
import flixel.util.FlxTimer;

#if sys
import sys.FileSystem;
import sys.io.File;
#end

using StringTools;

/**
 * Caixa de erros de softcode inspirada no DebugLuaText da Psych.
 * Mostra o tipo, arquivo, linha, callback e a linha de código em vermelho.
 */
class KadeshScriptDebug
{
    static var owner:PlayState = null;
    static var output:FlxText = null;
    static var hideTimer:FlxTimer = null;
    static var messages:Array<String> = [];

    public static function attach(state:PlayState, camera:FlxCamera):Void
    {
        destroy();
        owner = state;

        if (state == null)
            return;

        output = new FlxText(8, 8, FlxG.width - 16, '', 16);
        output.setFormat(
            Paths.font('vcr.ttf'),
            16,
            FlxColor.RED,
            FlxTextAlign.LEFT,
            FlxTextBorderStyle.OUTLINE,
            FlxColor.BLACK
        );
        output.borderSize = 2;
        output.scrollFactor.set();
        output.visible = false;
        if (camera != null)
            output.cameras = [camera];
        state.add(output);
    }

    public static function report(kind:String, path:String, message:String, ?callback:String = ''):Void
    {
        var cleanMessage:String = message == null ? 'Erro desconhecido.' : message.trim();
        var line:Int = extractLine(cleanMessage);
        var file:String = fileName(path);
        var heading:String = '[' + (kind == null ? 'SCRIPT' : kind.toUpperCase()) + '] ' + file;

        if (line > 0)
            heading += ':' + line;
        if (callback != null && callback.length > 0)
            heading += '  (' + callback + ')';

        var code:String = line > 0 ? readLine(path, line) : '';
        var formatted:String = heading + '\n' + limit(cleanMessage, 700);
        if (code.length > 0)
            formatted += '\n> ' + code.trim();

        trace(formatted);
        push(formatted, FlxColor.RED);
    }

    public static function warning(kind:String, path:String, message:String):Void
    {
        var formatted:String = '[' + kind.toUpperCase() + '] ' + fileName(path) + '\n' + limit(message, 500);
        trace(formatted);
        push(formatted, FlxColor.YELLOW);
    }

    public static function info(message:String, ?color:FlxColor = FlxColor.WHITE):Void
    {
        trace('[Softcode] ' + message);
        push(message, color);
    }

    static function push(message:String, color:FlxColor):Void
    {
        if (message == null || message.length == 0)
            return;

        messages.push(message);
        while (messages.length > 4)
            messages.shift();

        if (output == null)
            return;

        output.color = color;
        output.text = messages.join('\n\n');
        output.visible = true;

        if (owner != null)
        {
            owner.remove(output, false);
            owner.add(output);
        }

        if (hideTimer != null)
            hideTimer.cancel();

        hideTimer = new FlxTimer().start(12, function(timer:FlxTimer):Void
        {
            if (output != null)
                output.visible = false;
            messages = [];
            hideTimer = null;
        });
    }

    static function extractLine(message:String):Int
    {
        if (message == null)
            return -1;

        var patterns:Array<EReg> = [
            ~/:([0-9]+):/,
            ~/line[ ]+([0-9]+)/i,
            ~/linha[ ]+([0-9]+)/i,
            ~/\[string[^\]]*\]:([0-9]+)/
        ];

        for (pattern in patterns)
        {
            if (pattern.match(message))
            {
                var value:Null<Int> = Std.parseInt(pattern.matched(1));
                if (value != null)
                    return value;
            }
        }
        return -1;
    }

    static function readLine(path:String, line:Int):String
    {
        #if sys
        try
        {
            if (path == null || line <= 0 || !FileSystem.exists(path) || FileSystem.isDirectory(path))
                return '';

            var lines:Array<String> = File.getContent(path).replace('\r\n', '\n').replace('\r', '\n').split('\n');
            return line <= lines.length ? lines[line - 1] : '';
        }
        catch (e:Dynamic) {}
        #end
        return '';
    }

    static function fileName(path:String):String
    {
        if (path == null || path.length == 0)
            return '<script>';
        var parts:Array<String> = path.replace('\\', '/').split('/');
        return parts.length == 0 ? path : parts[parts.length - 1];
    }

    static function limit(value:String, length:Int):String
    {
        if (value == null)
            return '';
        return value.length > length ? value.substr(0, length) + '...' : value;
    }

    public static function destroy():Void
    {
        if (hideTimer != null)
        {
            hideTimer.cancel();
            hideTimer = null;
        }

        if (owner != null && output != null)
            owner.remove(output, true);
        else if (output != null)
            output.destroy();

        output = null;
        owner = null;
        messages = [];
    }
}
