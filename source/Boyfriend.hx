package;

using StringTools;

class Boyfriend extends Character
{
	public var stunned:Bool = false;

	public function new(x:Float, y:Float, ?char:String = 'bf')
	{
		super(x, y, char, true);
	}

	override function update(elapsed:Float):Void
	{
		if (!debugMode && animation.curAnim != null)
		{
			var animName:String = animation.curAnim.name;

			if (animName.startsWith('sing'))
				holdTimer += elapsed;
			else
				holdTimer = 0;

			if (animName.endsWith('miss') && animation.curAnim.finished)
				playAnim(jsonIdleAnimation, true, false, 10);

			if (animName == 'firstDeath' && animation.curAnim.finished)
				playAnim('deathLoop');
		}

		super.update(elapsed);
	}
}
