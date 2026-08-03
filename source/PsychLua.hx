package;

#if LUA_ALLOWED
/**
 * Registro leve de um arquivo Lua carregado dentro da VM compartilhada.
 *
 * Todos os arquivos continuam isolados em ambientes Lua próprios, igual ao
 * comportamento esperado da Psych, mas usam uma única State. Isso evita a
 * colisão do registro global de callbacks do linc_luajit em Android/desktop.
 */
class PsychLua
{
    public static inline var Function_Continue:Int = 0;
    public static inline var Function_Stop:Int = 1;
    public static inline var Function_StopLua:Int = 1;
    public static inline var Function_StopHScript:Int = 1;

    public var id(default, null):Int;
    public var scriptName(default, null):String;
    public var logicalPath(default, null):String;
    public var closed:Bool = false;
    public var errorCount:Int = 0;

    public function new(id:Int, scriptName:String, logicalPath:String)
    {
        this.id = id;
        this.scriptName = scriptName;
        this.logicalPath = logicalPath;
    }
}
#else
class PsychLua
{
    public static inline var Function_Continue:Int = 0;
    public static inline var Function_Stop:Int = 1;
    public static inline var Function_StopLua:Int = 1;
    public static inline var Function_StopHScript:Int = 1;
}
#end
