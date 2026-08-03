package;

#if HSCRIPT_ALLOWED
import hscript.Interp;

/** Um arquivo .hx interpretado no mods folder. */
class PsychHScript
{
    public static inline var Function_Continue:Int = 0;
    public static inline var Function_Stop:Int = 1;
    public static inline var Function_StopHScript:Int = 1;

    public var scriptName(default, null):String;
    public var logicalPath(default, null):String;
    public var interp(default, null):Interp;
    public var closed:Bool = false;
    public var errorCount:Int = 0;

    public function new(scriptName:String, logicalPath:String, interp:Interp)
    {
        this.scriptName = scriptName;
        this.logicalPath = logicalPath;
        this.interp = interp;
    }

    public function call(functionName:String, args:Array<Dynamic>):Dynamic
    {
        if (closed || interp == null || !interp.variables.exists(functionName))
            return null;

        var callback:Dynamic = interp.variables.get(functionName);
        if (!Reflect.isFunction(callback))
            return null;

        try
        {
            return Reflect.callMethod(null, callback, args == null ? [] : args);
        }
        catch (e:Dynamic)
        {
            errorCount++;
            KadeshScriptDebug.report('HSCRIPT', scriptName, Std.string(e), functionName);
            if (errorCount >= 3)
                close();
            return null;
        }
    }

    public function set(name:String, value:Dynamic):Void
    {
        if (!closed && interp != null)
            interp.variables.set(name, value);
    }

    public function close():Void
    {
        closed = true;
        interp = null;
    }
}
#else
class PsychHScript
{
    public static inline var Function_Continue:Int = 0;
    public static inline var Function_Stop:Int = 1;
    public static inline var Function_StopHScript:Int = 1;
}
#end
