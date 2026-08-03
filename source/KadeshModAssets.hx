package;

import flixel.FlxSprite;
import flixel.graphics.FlxGraphic;
import flixel.graphics.frames.FlxAtlasFrames;
import openfl.display.BitmapData;

#if sys
import sys.FileSystem;
import sys.io.File;
#end

using StringTools;

/** Carregamento físico de PNG/XML/TXT do mods folder com fallback para Paths. */
class KadeshModAssets
{
    public static function stripExtension(value:String):String
    {
        if (value == null)
            return '';

        var result:String = value.replace('\\', '/');
        for (extension in ['.png', '.xml', '.txt', '.json'])
            if (result.toLowerCase().endsWith(extension))
                result = result.substr(0, result.length - extension.length);
        while (result.startsWith('/'))
            result = result.substr(1);
        return result;
    }

    public static function loadImageInto(sprite:FlxSprite, image:String):Bool
    {
        if (sprite == null)
            return false;

        var key:String = stripExtension(image);

        #if sys
        var external:Null<String> = KadeshModPaths.find('images/' + key + '.png');
        if (external != null)
        {
            var bitmap:BitmapData = BitmapData.fromFile(external);
            if (bitmap == null)
                throw 'Não foi possível ler o PNG: ' + external;

            var graphic:FlxGraphic = FlxGraphic.fromBitmapData(bitmap, false, external);
            sprite.loadGraphic(graphic);
            return true;
        }
        #end

        sprite.loadGraphic(Paths.image(key));
        return true;
    }

    public static function loadAtlas(image:String, ?atlasType:String = 'sparrow'):FlxAtlasFrames
    {
        var key:String = stripExtension(image);
        var type:String = atlasType == null ? 'sparrow' : atlasType.toLowerCase().trim();

        #if sys
        var pngPath:Null<String> = KadeshModPaths.find('images/' + key + '.png');
        if (pngPath != null)
        {
            var bitmap:BitmapData = BitmapData.fromFile(pngPath);
            if (bitmap == null)
                throw 'Não foi possível ler o PNG: ' + pngPath;

            var graphic:FlxGraphic = FlxGraphic.fromBitmapData(bitmap, false, pngPath);

            if (type == 'packer' || type == 'txt')
            {
                var txtPath:Null<String> = KadeshModPaths.find('images/' + key + '.txt');
                if (txtPath == null)
                    throw 'Atlas Packer sem TXT: images/' + key + '.txt';

                return FlxAtlasFrames.fromSpriteSheetPacker(graphic, File.getContent(txtPath));
            }

            var xmlPath:Null<String> = KadeshModPaths.find('images/' + key + '.xml');
            if (xmlPath == null)
                throw 'Atlas Sparrow sem XML: images/' + key + '.xml';

            return FlxAtlasFrames.fromSparrow(graphic, File.getContent(xmlPath));
        }
        #end

        return (type == 'packer' || type == 'txt')
            ? Paths.getPackerAtlas(key)
            : Paths.getSparrowAtlas(key);
    }
}
