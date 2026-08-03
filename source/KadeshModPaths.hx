package;

#if sys
import sys.FileSystem;
import sys.io.File;
#end

using StringTools;

/**
 * Centraliza a procura por arquivos do mods folder no Android e no PC.
 *
 * Ordem de prioridade:
 * 1. Storage externo configurado pelo AndroidStorage.
 * 2. ./mods no PC.
 * 3. ./KadeshEngine/mods no PC.
 * 4. ./example_mods como fallback de desenvolvimento.
 */
class KadeshModPaths
{
    static var cachedRoots:Array<String> = null;

    public static function refresh():Void
    {
        cachedRoots = null;
    }

    public static function roots():Array<String>
    {
        if (cachedRoots != null)
            return cachedRoots.copy();

        cachedRoots = [];

        #if sys
        try
        {
            AndroidStorage.init();
            if (AndroidStorage.available && AndroidStorage.mods != null && AndroidStorage.mods.length > 0)
                addRoot(AndroidStorage.mods);
        }
        catch (e:Dynamic)
        {
            trace('[KadeshModPaths] Storage externo indisponível: ' + Std.string(e));
        }

        var cwd:String = Sys.getCwd();
        addRoot(join(cwd, 'mods'));
        addRoot(join(cwd, 'KadeshEngine/mods'));
        addRoot(join(cwd, 'example_mods'));
        #end

        return cachedRoots.copy();
    }

    static function addRoot(path:String):Void
    {
        #if sys
        if (path == null || path.length == 0)
            return;

        var normalized:String = normalize(path);
        if (!FileSystem.exists(normalized) || !FileSystem.isDirectory(normalized))
            return;

        for (existing in cachedRoots)
            if (normalize(existing) == normalized)
                return;

        cachedRoots.push(normalized);
        #end
    }

    public static function find(relative:String):Null<String>
    {
        #if sys
        var clean:String = cleanRelative(relative);
        for (root in roots())
        {
            var path:String = join(root, clean);
            try
            {
                if (FileSystem.exists(path) && !FileSystem.isDirectory(path))
                    return path;
            }
            catch (e:Dynamic) {}
        }
        #end
        return null;
    }

    public static function exists(relative:String):Bool
    {
        return find(relative) != null;
    }

    public static function readText(relative:String, ?fallback:String = null):String
    {
        #if sys
        var path:Null<String> = find(relative);
        if (path != null)
        {
            try
            {
                return File.getContent(path);
            }
            catch (e:Dynamic)
            {
                trace('[KadeshModPaths] Falha ao ler ' + path + ': ' + Std.string(e));
            }
        }
        #end
        return fallback;
    }

    /**
     * Lista arquivos de um diretório lógico sem repetir o mesmo caminho entre roots.
     */
    public static function list(relativeDirectory:String, extension:String, recursive:Bool):Array<{path:String, logical:String}>
    {
        var result:Array<{path:String, logical:String}> = [];
        var seen:Map<String, Bool> = new Map<String, Bool>();

        #if sys
        for (root in roots())
        {
            var directory:String = join(root, relativeDirectory);
            listDirectory(root, directory, cleanRelative(relativeDirectory), extension, recursive, seen, result);
        }
        #end

        result.sort(function(a, b):Int
            return Reflect.compare(a.logical.toLowerCase(), b.logical.toLowerCase()));
        return result;
    }

    #if sys
    static function listDirectory(
        root:String,
        directory:String,
        logicalDirectory:String,
        extension:String,
        recursive:Bool,
        seen:Map<String, Bool>,
        output:Array<{path:String, logical:String}>
    ):Void
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
            trace('[KadeshModPaths] Não foi possível listar ' + directory + ': ' + Std.string(e));
            return;
        }

        entries.sort(function(a:String, b:String):Int
            return Reflect.compare(a.toLowerCase(), b.toLowerCase()));

        for (entry in entries)
        {
            var full:String = join(directory, entry);
            var logical:String = join(logicalDirectory, entry);

            if (FileSystem.isDirectory(full))
            {
                if (recursive)
                    listDirectory(root, full, logical, extension, true, seen, output);
                continue;
            }

            if (extension != null && extension.length > 0 && !entry.toLowerCase().endsWith(extension.toLowerCase()))
                continue;

            var key:String = normalize(logical).toLowerCase();
            if (seen.exists(key))
                continue;

            seen.set(key, true);
            output.push({path: full, logical: logical});
        }
    }
    #end

    public static function cleanRelative(path:String):String
    {
        if (path == null)
            return '';

        var result:String = path.replace('\\', '/').trim();
        while (result.startsWith('/'))
            result = result.substr(1);
        while (result.indexOf('../') != -1)
            result = result.replace('../', '');
        while (result.indexOf('./') == 0)
            result = result.substr(2);
        return result;
    }

    public static function normalize(path:String):String
    {
        if (path == null)
            return '';

        var result:String = path.replace('\\', '/');
        while (result.indexOf('//') != -1)
            result = result.replace('//', '/');
        return result;
    }

    public static function join(left:String, right:String):String
    {
        if (left == null || left.length == 0)
            return cleanRelative(right);
        if (right == null || right.length == 0)
            return normalize(left);

        var cleanLeft:String = normalize(left);
        while (cleanLeft.endsWith('/'))
            cleanLeft = cleanLeft.substr(0, cleanLeft.length - 1);
        return cleanLeft + '/' + cleanRelative(right);
    }
}
