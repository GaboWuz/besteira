package;

import haxe.Json;

using StringTools;

typedef KadeshEventNote =
{
	var strumTime:Float;
	var event:String;
	var value1:String;
	var value2:String;
}

/**
 * Leitor simples dos eventos da Psych Engine.
 *
 * Aceita:
 * - events dentro do chart principal;
 * - data/musica/events.json;
 * - formato {"song":{"events":[...]}};
 * - formato {"events":[...]};
 * - notas de evento antigas com lane negativa.
 */
class KadeshEvent
{
	public static function load(
		songName:String,
		embeddedEvents:Dynamic,
		offset:Float = 0
	):Array<KadeshEventNote>
	{
		var result:Array<KadeshEventNote> = [];

		appendBlocks(result, embeddedEvents, offset);

		var folder:String = Paths.formatToSongPath(songName);
		var eventPath:String = Paths.json(folder + '/events');
		var raw:Null<String> = Paths.getText(eventPath);

		if (raw != null && raw.trim().length > 0)
		{
			try
			{
				var parsed:Dynamic = Json.parse(raw);

				if (Std.isOfType(parsed, Array))
				{
					appendBlocks(result, parsed, offset);
				}
				else
				{
					var container:Dynamic = parsed;

					if (Reflect.field(parsed, 'song') != null)
						container = Reflect.field(parsed, 'song');

					appendBlocks(result, Reflect.field(container, 'events'), offset);
				}
			}
			catch (e:Dynamic)
			{
				trace('[KadeshEvent] events.json inválido: ' + Std.string(e));
			}
		}

		result.sort(sortByTime);
		return result;
	}

	public static function fromLegacyNote(noteData:Array<Dynamic>, offset:Float = 0):Null<KadeshEventNote>
	{
		if (noteData == null || noteData.length < 3)
			return null;

		var lane:Float = toFloat(noteData[1], 0);
		if (lane >= 0)
			return null;

		return {
			strumTime: toFloat(noteData[0], 0) + offset,
			event: toString(noteData[2]),
			value1: noteData.length > 3 ? toString(noteData[3]) : '',
			value2: noteData.length > 4 ? toString(noteData[4]) : ''
		};
	}

	static function appendBlocks(
		target:Array<KadeshEventNote>,
		rawBlocks:Dynamic,
		offset:Float
	):Void
	{
		if (rawBlocks == null || !Std.isOfType(rawBlocks, Array))
			return;

		var blocks:Array<Dynamic> = cast rawBlocks;

		for (rawBlock in blocks)
		{
			if (!Std.isOfType(rawBlock, Array))
				continue;

			var block:Array<Dynamic> = cast rawBlock;
			if (block.length < 2 || !Std.isOfType(block[1], Array))
				continue;

			var time:Float = toFloat(block[0], 0) + offset;
			var entries:Array<Dynamic> = cast block[1];

			for (rawEntry in entries)
			{
				if (!Std.isOfType(rawEntry, Array))
					continue;

				var entry:Array<Dynamic> = cast rawEntry;
				if (entry.length < 1)
					continue;

				var eventName:String = toString(entry[0]).trim();
				if (eventName.length == 0)
					continue;

				target.push({
					strumTime: time,
					event: eventName,
					value1: entry.length > 1 ? toString(entry[1]) : '',
					value2: entry.length > 2 ? toString(entry[2]) : ''
				});
			}
		}
	}

	static function sortByTime(a:KadeshEventNote, b:KadeshEventNote):Int
	{
		if (a.strumTime < b.strumTime)
			return -1;
		if (a.strumTime > b.strumTime)
			return 1;
		return 0;
	}

	static function toFloat(value:Dynamic, fallback:Float):Float
	{
		var parsed:Float = Std.parseFloat(Std.string(value));
		return Math.isNaN(parsed) ? fallback : parsed;
	}

	static function toString(value:Dynamic):String
	{
		return value == null ? '' : Std.string(value);
	}
}
