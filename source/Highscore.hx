package;

import flixel.FlxG;

using StringTools;

class Highscore
{
	#if (haxe >= "4.0.0")
	public static var songScores:Map<String, Int> = new Map();
	public static var songCombos:Map<String, String> = new Map();
	#else
	public static var songScores:Map<String, Int> = new Map<String, Int>();
	public static var songCombos:Map<String, String> = new Map<String, String>();
	#end

	public static function normalizeSong(song:String):String
	{
		return Paths.formatToSongPath(song);
	}

	public static function saveScore(song:String, score:Int = 0, ?diff:Int = 0):Void
	{
		var daSong:String = formatSong(song, diff);

		#if !switch
		NGio.postScore(score, song);
		#end

		if (!isBotplay())
		{
			if (!songScores.exists(daSong) || songScores.get(daSong) < score)
				setScore(daSong, score);
		}
		else
			trace('BotPlay detected. Score saving is disabled.');
	}

	public static function saveCombo(song:String, combo:String, ?diff:Int = 0):Void
	{
		var daSong:String = formatSong(song, diff);
		var finalCombo:String = combo.split(')')[0].replace('(', '');

		if (!isBotplay())
		{
			if (!songCombos.exists(daSong)
				|| getComboInt(songCombos.get(daSong)) < getComboInt(finalCombo))
			{
				setCombo(daSong, finalCombo);
			}
		}
	}

	public static function saveWeekScore(week:Int = 1, score:Int = 0, ?diff:Int = 0):Void
	{
		#if !switch
		NGio.postScore(score, "Week " + week);
		#end

		if (!isBotplay())
		{
			var daWeek:String = formatSong('week' + week, diff);

			if (!songScores.exists(daWeek) || songScores.get(daWeek) < score)
				setScore(daWeek, score);
		}
		else
			trace('BotPlay detected. Score saving is disabled.');
	}

	static function isBotplay():Bool
	{
		return FlxG.save != null
			&& FlxG.save.data != null
			&& FlxG.save.data.botplay == true;
	}

	/**
	 * As funções set recebem uma chave já normalizada.
	 */
	static function setScore(song:String, score:Int):Void
	{
		songScores.set(song, score);

		if (FlxG.save != null)
		{
			FlxG.save.data.songScores = songScores;
			FlxG.save.flush();
		}
	}

	static function setCombo(song:String, combo:String):Void
	{
		songCombos.set(song, combo);

		if (FlxG.save != null)
		{
			FlxG.save.data.songCombos = songCombos;
			FlxG.save.flush();
		}
	}

	public static function formatSong(song:String, diff:Int):String
	{
		var daSong:String = normalizeSong(song);

		if (diff == 0)
			daSong += '-easy';
		else if (diff == 2)
			daSong += '-hard';

		return daSong;
	}

	/**
	 * Chave usada pelas builds antigas, antes da normalização central.
	 * Serve somente para migrar pontuações já existentes.
	 */
	static function legacyFormatSong(song:String, diff:Int):String
	{
		var daSong:String = song == null ? "" : song.replace(" ", "-");

		switch (daSong)
		{
			case 'Dad-Battle':
				daSong = 'Dadbattle';
			case 'Philly-Nice':
				daSong = 'Philly';
		}

		if (diff == 0)
			daSong += '-easy';
		else if (diff == 2)
			daSong += '-hard';

		return daSong;
	}

	static function getComboInt(combo:String):Int
	{
		switch (combo)
		{
			case 'SDCB':
				return 1;
			case 'FC':
				return 2;
			case 'GFC':
				return 3;
			case 'MFC':
				return 4;
			default:
				return 0;
		}
	}

	public static function getScore(song:String, diff:Int):Int
	{
		var key:String = formatSong(song, diff);

		if (!songScores.exists(key))
		{
			var oldKey:String = legacyFormatSong(song, diff);

			if (oldKey != key && songScores.exists(oldKey))
				setScore(key, songScores.get(oldKey));
			else
				setScore(key, 0);
		}

		return songScores.get(key);
	}

	public static function getCombo(song:String, diff:Int):String
	{
		var key:String = formatSong(song, diff);

		if (!songCombos.exists(key))
		{
			var oldKey:String = legacyFormatSong(song, diff);

			if (oldKey != key && songCombos.exists(oldKey))
				setCombo(key, songCombos.get(oldKey));
			else
				setCombo(key, '');
		}

		return songCombos.get(key);
	}

	public static function getWeekScore(week:Int, diff:Int):Int
	{
		var key:String = formatSong('week' + week, diff);

		if (!songScores.exists(key))
			setScore(key, 0);

		return songScores.get(key);
	}

	public static function load():Void
	{
		if (FlxG.save.data.songScores != null)
			songScores = FlxG.save.data.songScores;

		if (FlxG.save.data.songCombos != null)
			songCombos = FlxG.save.data.songCombos;
	}
}
