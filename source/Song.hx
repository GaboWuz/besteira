package;

import Section.SwagSection;
import haxe.Json;

using StringTools;

typedef SwagSong =
{
	var song:String;
	var notes:Array<SwagSection>;
	@:optional var events:Array<Dynamic>;
	var bpm:Float;
	var needsVoices:Bool;
	var speed:Float;
	var player1:String;
	var player2:String;
	@:optional var gfVersion:String;
	@:optional var noteStyle:String;
	@:optional var stage:String;
	var validScore:Bool;
}

class Song
{
	public var song:String;
	public var notes:Array<SwagSection>;
	public var events:Array<Dynamic> = [];
	public var bpm:Float;
	public var needsVoices:Bool = true;
	public var speed:Float = 1;
	public var player1:String = 'bf';
	public var player2:String = 'dad';
	public var gfVersion:String = '';
	public var noteStyle:String = '';
	public var stage:String = '';

	public function new(song:String, notes:Array<SwagSection>, bpm:Float)
	{
		this.song = song;
		this.notes = notes;
		this.bpm = bpm;
	}

	public static function loadFromJson(jsonInput:String, ?folder:String):SwagSong
	{
		if (jsonInput == null || jsonInput.trim().length == 0)
			throw '[Song] Nome do chart vazio.';

		if (folder == null || folder.trim().length == 0)
			folder = jsonInput;

		var folderName:String = Paths.formatToSongPath(folder);
		var chartName:String = Paths.formatToSongPath(jsonInput);
		var chartPath:String = Paths.json(folderName + '/' + chartName);
		var rawJson:Null<String> = Paths.getText(chartPath);

		if (rawJson == null)
			throw '[Song] Chart não encontrado: ' + chartPath;

		rawJson = rawJson.trim();

		while (rawJson.length > 0 && !rawJson.endsWith('}'))
			rawJson = rawJson.substr(0, rawJson.length - 1);

		if (rawJson.length == 0)
			throw '[Song] Chart vazio ou inválido: ' + chartPath;

		try
		{
			return parseJSONshit(rawJson);
		}
		catch (e:Dynamic)
		{
			throw '[Song] JSON inválido em "' + chartPath + '": ' + Std.string(e);
		}
	}

	public static function parseJSONshit(rawJson:String):SwagSong
	{
		var parsed:Dynamic = Json.parse(rawJson);

		if (parsed == null || Reflect.field(parsed, 'song') == null)
			throw 'O JSON precisa possuir o objeto "song".';

		var dynamicSong:Dynamic = Reflect.field(parsed, 'song');

		if (Reflect.field(dynamicSong, 'events') == null)
			Reflect.setField(dynamicSong, 'events', []);

		if (Reflect.field(dynamicSong, 'notes') == null)
			Reflect.setField(dynamicSong, 'notes', []);

		var songData:SwagSong = cast dynamicSong;
		songData.validScore = true;
		return songData;
	}
}
