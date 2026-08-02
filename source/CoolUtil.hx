package;

using StringTools;

class CoolUtil
{
	public static var difficultyArray:Array<String> = ['Easy', 'Normal', 'Hard'];

	public static function difficultyFromInt(difficulty:Int):String
	{
		return difficultyArray[difficulty];
	}

	public static function coolTextFile(path:String):Array<String>
	{
		var content = Paths.getText(path);
		if (content == null)
			return [];

		return coolStringFile(content);
	}

	public static function coolStringFile(content:String):Array<String>
	{
		if (content == null)
			return [];

		var list = content.trim().split('\n');
		for (i in 0...list.length)
			list[i] = list[i].trim();

		return list;
	}

	public static function numberArray(max:Int, ?min:Int = 0):Array<Int>
	{
		var dumbArray:Array<Int> = [];
		for (i in min...max)
			dumbArray.push(i);
		return dumbArray;
	}
}
