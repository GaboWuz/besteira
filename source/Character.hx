package;

import flixel.FlxSprite;
import flixel.graphics.frames.FlxAtlasFrames;

using StringTools;

class Character extends FlxSprite
{
	public var animOffsets:Map<String, Array<Dynamic>>;
	public var debugMode:Bool = false;
	public var isPlayer:Bool = false;
	public var curCharacter:String = 'bf';
	public var holdTimer:Float = 0;

	// Kadesh: sustain segura a animação até este tempo da música.
	public var sustainHoldEnd:Float = -1;
	public var sustainDirection:Int = -1;

	// Kadesh: usados por personagem/ícone externos.
	public var healthIcon:String = '';
	public var isJsonCharacter:Bool = false;
	public var jsonIdleAnimation:String = 'idle';
	public var positionOffsetX:Float = 0;
	public var positionOffsetY:Float = 0;

	// Eventos básicos da Psych.
	public var idleSuffix:String = '';
	public var specialAnim:Bool = false;
	public var specialAnimTimer:Float = 0;

	private var danced:Bool = false;

	public function new(x:Float, y:Float, ?character:String = 'bf', ?isPlayer:Bool = false)
	{
		super(x, y);

		animOffsets = new Map<String, Array<Dynamic>>();
		curCharacter = character;
		healthIcon = character;
		this.isPlayer = isPlayer;
		antialiasing = true;

		var loadedFromJson:Bool = CharacterData.tryApply(this, curCharacter);
		if (!loadedFromJson)
			loadHardcodedCharacter();

		// Nome inválido ou personagem antigo incompleto nunca deve fechar o jogo.
		if (frames == null)
			CharacterData.applyEmergencyFallback(this, isPlayer);

		dance();

		if (isPlayer)
		{
			flipX = !flipX;

			// BF já vem desenhado para o lado correto. Outros personagens precisam
			// trocar LEFT/RIGHT quando usados como player.
			if (!curCharacter.startsWith('bf')
				&& animation.getByName('singRIGHT') != null
				&& animation.getByName('singLEFT') != null)
			{
				var oldRight = animation.getByName('singRIGHT').frames;
				animation.getByName('singRIGHT').frames = animation.getByName('singLEFT').frames;
				animation.getByName('singLEFT').frames = oldRight;

				if (animation.getByName('singRIGHTmiss') != null
					&& animation.getByName('singLEFTmiss') != null)
				{
					var oldMiss = animation.getByName('singRIGHTmiss').frames;
					animation.getByName('singRIGHTmiss').frames = animation.getByName('singLEFTmiss').frames;
					animation.getByName('singLEFTmiss').frames = oldMiss;
				}
			}
		}
	}

	private function loadHardcodedCharacter():Void
	{
		var tex:FlxAtlasFrames;

		switch (curCharacter)
		{
			case 'gf':
				tex = Paths.getSparrowAtlas('characters/GF_assets');
				frames = tex;
				animation.addByPrefix('cheer', 'GF Cheer', 24, false);
				animation.addByPrefix('singLEFT', 'GF left note', 24, false);
				animation.addByPrefix('singRIGHT', 'GF Right Note', 24, false);
				animation.addByPrefix('singUP', 'GF Up Note', 24, false);
				animation.addByPrefix('singDOWN', 'GF Down Note', 24, false);
				animation.addByIndices('sad', 'gf sad', [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12], '', 24, false);
				animation.addByIndices('danceLeft', 'GF Dancing Beat', [30, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14], '', 24, false);
				animation.addByIndices('danceRight', 'GF Dancing Beat', [15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29], '', 24, false);
				animation.addByIndices('hairBlow', 'GF Dancing Beat Hair blowing', [0, 1, 2, 3], '', 24);
				animation.addByIndices('hairFall', 'GF Dancing Beat Hair Landing', [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11], '', 24, false);
				animation.addByPrefix('scared', 'GF FEAR', 24);
				addOffset('cheer');
				addOffset('sad', -2, -2);
				addOffset('danceLeft', 0, -9);
				addOffset('danceRight', 0, -9);
				addOffset('singUP', 0, 4);
				addOffset('singRIGHT', 0, -20);
				addOffset('singLEFT', 0, -19);
				addOffset('singDOWN', 0, -20);
				addOffset('hairBlow', 45, -8);
				addOffset('hairFall', 0, -9);
				addOffset('scared', -2, -17);
				playAnim('danceRight');

			case 'gf-christmas':
				tex = Paths.getSparrowAtlas('characters/gfChristmas');
				frames = tex;
				animation.addByPrefix('cheer', 'GF Cheer', 24, false);
				animation.addByPrefix('singLEFT', 'GF left note', 24, false);
				animation.addByPrefix('singRIGHT', 'GF Right Note', 24, false);
				animation.addByPrefix('singUP', 'GF Up Note', 24, false);
				animation.addByPrefix('singDOWN', 'GF Down Note', 24, false);
				animation.addByIndices('sad', 'gf sad', [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12], '', 24, false);
				animation.addByIndices('danceLeft', 'GF Dancing Beat', [30, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14], '', 24, false);
				animation.addByIndices('danceRight', 'GF Dancing Beat', [15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29], '', 24, false);
				animation.addByIndices('hairBlow', 'GF Dancing Beat Hair blowing', [0, 1, 2, 3], '', 24);
				animation.addByIndices('hairFall', 'GF Dancing Beat Hair Landing', [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11], '', 24, false);
				animation.addByPrefix('scared', 'GF FEAR', 24);
				addOffset('cheer');
				addOffset('sad', -2, -2);
				addOffset('danceLeft', 0, -9);
				addOffset('danceRight', 0, -9);
				addOffset('singUP', 0, 4);
				addOffset('singRIGHT', 0, -20);
				addOffset('singLEFT', 0, -19);
				addOffset('singDOWN', 0, -20);
				addOffset('hairBlow', 45, -8);
				addOffset('hairFall', 0, -9);
				addOffset('scared', -2, -17);
				playAnim('danceRight');

			case 'gf-car':
				frames = Paths.getSparrowAtlas('characters/gfCar');
				animation.addByIndices('singUP', 'GF Dancing Beat Hair blowing CAR', [0], '', 24, false);
				animation.addByIndices('danceLeft', 'GF Dancing Beat Hair blowing CAR', [30, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14], '', 24, false);
				animation.addByIndices('danceRight', 'GF Dancing Beat Hair blowing CAR', [15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29], '', 24, false);
				addOffset('danceLeft');
				addOffset('danceRight');
				playAnim('danceRight');

			case 'gf-pixel':
				frames = Paths.getSparrowAtlas('characters/gfPixel');
				animation.addByIndices('singUP', 'GF IDLE', [2], '', 24, false);
				animation.addByIndices('danceLeft', 'GF IDLE', [30, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14], '', 24, false);
				animation.addByIndices('danceRight', 'GF IDLE', [15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29], '', 24, false);
				addOffset('danceLeft');
				addOffset('danceRight');
				playAnim('danceRight');
				setGraphicSize(Std.int(width * PlayState.daPixelZoom));
				updateHitbox();
				antialiasing = false;

			case 'dad':
				frames = Paths.getSparrowAtlas('characters/DADDY_DEAREST', 'shared');
				animation.addByPrefix('idle', 'Dad idle dance', 24);
				animation.addByPrefix('singUP', 'Dad Sing Note UP', 24);
				animation.addByPrefix('singRIGHT', 'Dad Sing Note RIGHT', 24);
				animation.addByPrefix('singDOWN', 'Dad Sing Note DOWN', 24);
				animation.addByPrefix('singLEFT', 'Dad Sing Note LEFT', 24);
				addOffset('idle');
				addOffset('singUP', -6, 50);
				addOffset('singRIGHT', 0, 27);
				addOffset('singLEFT', -10, 10);
				addOffset('singDOWN', 0, -30);
				playAnim('idle');

			case 'spooky':
				frames = Paths.getSparrowAtlas('characters/spooky_kids_assets');
				animation.addByPrefix('singUP', 'spooky UP NOTE', 24, false);
				animation.addByPrefix('singDOWN', 'spooky DOWN note', 24, false);
				animation.addByPrefix('singLEFT', 'note sing left', 24, false);
				animation.addByPrefix('singRIGHT', 'spooky sing right', 24, false);
				animation.addByIndices('danceLeft', 'spooky dance idle', [0, 2, 6], '', 12, false);
				animation.addByIndices('danceRight', 'spooky dance idle', [8, 10, 12, 14], '', 12, false);
				addOffset('danceLeft');
				addOffset('danceRight');
				addOffset('singUP', -20, 26);
				addOffset('singRIGHT', -130, -14);
				addOffset('singLEFT', 130, -10);
				addOffset('singDOWN', -50, -130);
				playAnim('danceRight');

			case 'mom' | 'mom-car':
				frames = Paths.getSparrowAtlas(curCharacter == 'mom' ? 'characters/Mom_Assets' : 'characters/momCar');
				animation.addByPrefix('idle', 'Mom Idle', 24, false);
				animation.addByPrefix('singUP', 'Mom Up Pose', 24, false);
				animation.addByPrefix('singDOWN', 'MOM DOWN POSE', 24, false);
				animation.addByPrefix('singLEFT', 'Mom Left Pose', 24, false);
				animation.addByPrefix('singRIGHT', 'Mom Pose Left', 24, false);
				addOffset('idle');
				addOffset('singUP', 14, 71);
				addOffset('singRIGHT', 10, -60);
				addOffset('singLEFT', 250, -23);
				addOffset('singDOWN', 20, -160);
				playAnim('idle');

			case 'monster' | 'monster-christmas':
				frames = Paths.getSparrowAtlas(curCharacter == 'monster' ? 'characters/Monster_Assets' : 'characters/monsterChristmas');
				animation.addByPrefix('idle', 'monster idle', 24, false);
				animation.addByPrefix('singUP', 'monster up note', 24, false);
				animation.addByPrefix('singDOWN', 'monster down', 24, false);
				animation.addByPrefix('singLEFT', 'Monster left note', 24, false);
				animation.addByPrefix('singRIGHT', 'Monster Right note', 24, false);
				addOffset('idle');
				addOffset('singUP', -20, 50);
				addOffset('singRIGHT', -51);
				addOffset('singLEFT', -30);
				addOffset('singDOWN', curCharacter == 'monster' ? -30 : -40, curCharacter == 'monster' ? -40 : -94);
				playAnim('idle');

			case 'pico':
				frames = Paths.getSparrowAtlas('characters/Pico_FNF_assetss');
				animation.addByPrefix('idle', 'Pico Idle Dance', 24);
				animation.addByPrefix('singUP', 'pico Up note0', 24, false);
				animation.addByPrefix('singDOWN', 'Pico Down Note0', 24, false);
				if (isPlayer)
				{
					animation.addByPrefix('singLEFT', 'Pico NOTE LEFT0', 24, false);
					animation.addByPrefix('singRIGHT', 'Pico Note Right0', 24, false);
					animation.addByPrefix('singRIGHTmiss', 'Pico Note Right Miss', 24, false);
					animation.addByPrefix('singLEFTmiss', 'Pico NOTE LEFT miss', 24, false);
				}
				else
				{
					animation.addByPrefix('singLEFT', 'Pico Note Right0', 24, false);
					animation.addByPrefix('singRIGHT', 'Pico NOTE LEFT0', 24, false);
					animation.addByPrefix('singRIGHTmiss', 'Pico NOTE LEFT miss', 24, false);
					animation.addByPrefix('singLEFTmiss', 'Pico Note Right Miss', 24, false);
				}
				animation.addByPrefix('singUPmiss', 'pico Up note miss', 24);
				animation.addByPrefix('singDOWNmiss', 'Pico Down Note MISS', 24);
				addOffset('idle');
				addOffset('singUP', -29, 27);
				addOffset('singRIGHT', -68, -7);
				addOffset('singLEFT', 65, 9);
				addOffset('singDOWN', 200, -70);
				addOffset('singUPmiss', -19, 67);
				addOffset('singRIGHTmiss', -60, 41);
				addOffset('singLEFTmiss', 62, 64);
				addOffset('singDOWNmiss', 210, -28);
				playAnim('idle');
				flipX = true;

			case 'bf':
				frames = Paths.getSparrowAtlas('characters/BOYFRIEND', 'shared');
				addBoyfriendAnimations(true, true);
				addOffset('firstDeath', 37, 11);
				addOffset('deathLoop', 37, 5);
				addOffset('deathConfirm', 37, 69);
				animation.addByPrefix('firstDeath', 'BF dies', 24, false);
				animation.addByPrefix('deathLoop', 'BF Dead Loop', 24, true);
				animation.addByPrefix('deathConfirm', 'BF Dead confirm', 24, false);
				animation.addByPrefix('scared', 'BF idle shaking', 24);
				addOffset('scared', -4);
				playAnim('idle');
				flipX = true;

			case 'bf-christmas':
				frames = Paths.getSparrowAtlas('characters/bfChristmas');
				addBoyfriendAnimations(true, true);
				playAnim('idle');
				flipX = true;

			case 'bf-car':
				frames = Paths.getSparrowAtlas('characters/bfCar');
				addBoyfriendAnimations(true, false);
				playAnim('idle');
				flipX = true;

			case 'bf-pixel':
				frames = Paths.getSparrowAtlas('characters/bfPixel');
				animation.addByPrefix('idle', 'BF IDLE', 24, false);
				animation.addByPrefix('singUP', 'BF UP NOTE', 24, false);
				animation.addByPrefix('singLEFT', 'BF LEFT NOTE', 24, false);
				animation.addByPrefix('singRIGHT', 'BF RIGHT NOTE', 24, false);
				animation.addByPrefix('singDOWN', 'BF DOWN NOTE', 24, false);
				animation.addByPrefix('singUPmiss', 'BF UP MISS', 24, false);
				animation.addByPrefix('singLEFTmiss', 'BF LEFT MISS', 24, false);
				animation.addByPrefix('singRIGHTmiss', 'BF RIGHT MISS', 24, false);
				animation.addByPrefix('singDOWNmiss', 'BF DOWN MISS', 24, false);
				addOffset('idle');
				addOffset('singUP');
				addOffset('singRIGHT');
				addOffset('singLEFT');
				addOffset('singDOWN');
				addOffset('singUPmiss');
				addOffset('singRIGHTmiss');
				addOffset('singLEFTmiss');
				addOffset('singDOWNmiss');
				setGraphicSize(Std.int(width * 6));
				updateHitbox();
				playAnim('idle');
				width -= 100;
				height -= 100;
				antialiasing = false;
				flipX = true;

			case 'bf-pixel-dead':
				frames = Paths.getSparrowAtlas('characters/bfPixelsDEAD');
				animation.addByPrefix('singUP', 'BF Dies pixel', 24, false);
				animation.addByPrefix('firstDeath', 'BF Dies pixel', 24, false);
				animation.addByPrefix('deathLoop', 'Retry Loop', 24, true);
				animation.addByPrefix('deathConfirm', 'RETRY CONFIRM', 24, false);
				addOffset('firstDeath');
				addOffset('deathLoop', -37);
				addOffset('deathConfirm', -37);
				playAnim('firstDeath');
				setGraphicSize(Std.int(width * 6));
				updateHitbox();
				antialiasing = false;
				flipX = true;
				healthIcon = 'bf-pixel';

			case 'senpai' | 'senpai-angry':
				frames = Paths.getSparrowAtlas('characters/senpai');
				var angry:String = curCharacter == 'senpai-angry' ? 'Angry ' : '';
				var senpaiPrefix:String = curCharacter == 'senpai-angry' ? 'Angry Senpai' : 'SENPAI';
				animation.addByPrefix('idle', angry + 'Senpai Idle', 24, false);
				animation.addByPrefix('singUP', senpaiPrefix + ' UP NOTE', 24, false);
				animation.addByPrefix('singLEFT', senpaiPrefix + ' LEFT NOTE', 24, false);
				animation.addByPrefix('singRIGHT', senpaiPrefix + ' RIGHT NOTE', 24, false);
				animation.addByPrefix('singDOWN', senpaiPrefix + ' DOWN NOTE', 24, false);
				addOffset('idle');
				addOffset('singUP', 5, 37);
				addOffset('singRIGHT');
				addOffset('singLEFT', 40);
				addOffset('singDOWN', 14);
				playAnim('idle');
				setGraphicSize(Std.int(width * 6));
				updateHitbox();
				antialiasing = false;

			case 'spirit':
				frames = Paths.getPackerAtlas('characters/spirit');
				animation.addByPrefix('idle', 'idle spirit_', 24, false);
				animation.addByPrefix('singUP', 'up_', 24, false);
				animation.addByPrefix('singRIGHT', 'right_', 24, false);
				animation.addByPrefix('singLEFT', 'left_', 24, false);
				animation.addByPrefix('singDOWN', 'spirit down_', 24, false);
				addOffset('idle', -220, -280);
				addOffset('singUP', -220, -240);
				addOffset('singRIGHT', -220, -280);
				addOffset('singLEFT', -200, -280);
				addOffset('singDOWN', 170, 110);
				setGraphicSize(Std.int(width * 6));
				updateHitbox();
				playAnim('idle');
				antialiasing = false;

			case 'parents-christmas':
				frames = Paths.getSparrowAtlas('characters/mom_dad_christmas_assets');
				animation.addByPrefix('idle', 'Parent Christmas Idle', 24, false);
				animation.addByPrefix('singUP', 'Parent Up Note Dad', 24, false);
				animation.addByPrefix('singDOWN', 'Parent Down Note Dad', 24, false);
				animation.addByPrefix('singLEFT', 'Parent Left Note Dad', 24, false);
				animation.addByPrefix('singRIGHT', 'Parent Right Note Dad', 24, false);
				animation.addByPrefix('singUP-alt', 'Parent Up Note Mom', 24, false);
				animation.addByPrefix('singDOWN-alt', 'Parent Down Note Mom', 24, false);
				animation.addByPrefix('singLEFT-alt', 'Parent Left Note Mom', 24, false);
				animation.addByPrefix('singRIGHT-alt', 'Parent Right Note Mom', 24, false);
				addOffset('idle');
				addOffset('singUP', -47, 24);
				addOffset('singRIGHT', -1, -23);
				addOffset('singLEFT', -30, 16);
				addOffset('singDOWN', -31, -29);
				addOffset('singUP-alt', -47, 24);
				addOffset('singRIGHT-alt', -1, -24);
				addOffset('singLEFT-alt', -30, 15);
				addOffset('singDOWN-alt', -30, -27);
				playAnim('idle');
		}
	}

	private function addBoyfriendAnimations(addMiss:Bool, addHey:Bool):Void
	{
		animation.addByPrefix('idle', 'BF idle dance', 24, false);
		animation.addByPrefix('singUP', 'BF NOTE UP0', 24, false);
		animation.addByPrefix('singLEFT', 'BF NOTE LEFT0', 24, false);
		animation.addByPrefix('singRIGHT', 'BF NOTE RIGHT0', 24, false);
		animation.addByPrefix('singDOWN', 'BF NOTE DOWN0', 24, false);

		if (addMiss)
		{
			animation.addByPrefix('singUPmiss', 'BF NOTE UP MISS', 24, false);
			animation.addByPrefix('singLEFTmiss', 'BF NOTE LEFT MISS', 24, false);
			animation.addByPrefix('singRIGHTmiss', 'BF NOTE RIGHT MISS', 24, false);
			animation.addByPrefix('singDOWNmiss', 'BF NOTE DOWN MISS', 24, false);
		}

		if (addHey)
			animation.addByPrefix('hey', 'BF HEY', 24, false);

		addOffset('idle', -5);
		addOffset('singUP', -29, 27);
		addOffset('singRIGHT', -38, -7);
		addOffset('singLEFT', 12, -6);
		addOffset('singDOWN', -10, -50);
		addOffset('singUPmiss', -29, 27);
		addOffset('singRIGHTmiss', -30, 21);
		addOffset('singLEFTmiss', 12, 24);
		addOffset('singDOWNmiss', -11, -19);
		addOffset('hey', 7, 4);
	}

	public function beginSustainHold(endTime:Float, direction:Int):Void
	{
		sustainHoldEnd = Math.max(sustainHoldEnd, endTime);
		sustainDirection = direction;
		holdTimer = 0;
	}

	public function refreshSustainHold(endTime:Float, direction:Int):Void
	{
		sustainHoldEnd = Math.max(sustainHoldEnd, endTime);
		sustainDirection = direction;
	}

	public function clearSustainHold():Void
	{
		sustainHoldEnd = -1;
		sustainDirection = -1;
	}

	public function isHoldingSustain():Bool
	{
		return sustainHoldEnd >= 0 && Conductor.songPosition <= sustainHoldEnd;
	}

	override function update(elapsed:Float):Void
	{
		if (sustainHoldEnd >= 0 && Conductor.songPosition > sustainHoldEnd)
			clearSustainHold();

		if (specialAnim)
		{
			if (specialAnimTimer > 0)
			{
				specialAnimTimer -= elapsed;
				if (specialAnimTimer <= 0)
				{
					specialAnim = false;
					dance();
				}
			}
			else if (animation.curAnim == null || animation.curAnim.finished)
			{
				specialAnim = false;
				dance();
			}
		}

		// Boyfriend.hx cuida do player. Aqui cuidamos apenas do oponente.
		if (!specialAnim && !isPlayer && animation.curAnim != null)
		{
			if (animation.curAnim.name.startsWith('sing'))
				holdTimer += elapsed;

			var dadVar:Float = curCharacter == 'dad' ? 6.1 : 4;
			if (!isHoldingSustain() && holdTimer >= Conductor.stepCrochet * dadVar * 0.001)
			{
				dance();
				holdTimer = 0;
			}
		}

		if (curCharacter == 'gf' && animation.curAnim != null
			&& animation.curAnim.name == 'hairFall' && animation.curAnim.finished)
		{
			playAnim('danceRight');
		}

		super.update(elapsed);
	}

	public function dance():Void
	{
		if (debugMode || isHoldingSustain() || specialAnim)
			return;

		if (isJsonCharacter)
		{
			var leftName:String = resolveIdleName('danceLeft');
			var rightName:String = resolveIdleName('danceRight');
			var idleName:String = resolveIdleName(jsonIdleAnimation);
			var hasLeft:Bool = animation.getByName(leftName) != null;
			var hasRight:Bool = animation.getByName(rightName) != null;

			if (hasLeft && hasRight)
			{
				danced = !danced;
				playAnim(danced ? rightName : leftName);
			}
			else
				playAnim(idleName);
			return;
		}

		switch (curCharacter)
		{
			case 'gf' | 'gf-christmas' | 'gf-car' | 'gf-pixel':
				if (animation.curAnim == null || !animation.curAnim.name.startsWith('hair'))
				{
					danced = !danced;
					playAnim(resolveIdleName(danced ? 'danceRight' : 'danceLeft'));
				}

			case 'spooky':
				danced = !danced;
				playAnim(resolveIdleName(danced ? 'danceRight' : 'danceLeft'));

			default:
				var idleName:String = resolveIdleName('idle');
				if (animation.getByName(idleName) != null)
					playAnim(idleName);
		}
	}


	public function playSpecialAnim(name:String, duration:Float = 0):Bool
	{
		if (name == null || animation.getByName(name) == null)
			return false;

		clearSustainHold();
		specialAnim = true;
		specialAnimTimer = duration > 0 ? duration : 0;
		playAnim(name, true);
		return true;
	}

	public function cancelSpecialAnim():Void
	{
		specialAnim = false;
		specialAnimTimer = 0;
	}

	public function setIdleSuffix(value:String):Void
	{
		idleSuffix = value == null ? '' : value;
		specialAnim = false;
		dance();
	}

	function resolveIdleName(baseName:String):String
	{
		if (idleSuffix != null && idleSuffix.length > 0)
		{
			var suffixed:String = baseName + idleSuffix;
			if (animation.getByName(suffixed) != null)
				return suffixed;
		}

		return baseName;
	}

	public function playAnim(AnimName:String, Force:Bool = false, Reversed:Bool = false, Frame:Int = 0):Void
	{
		if (animation.getByName(AnimName) == null)
		{
			trace('[Character] Animação inexistente em ' + curCharacter + ': ' + AnimName);
			return;
		}

		animation.play(AnimName, Force, Reversed, Frame);

		if (animOffsets.exists(AnimName))
		{
			var daOffset = animOffsets.get(AnimName);
			offset.set(daOffset[0], daOffset[1]);
		}
		else
			offset.set(0, 0);

		if (curCharacter == 'gf')
		{
			if (AnimName == 'singLEFT')
				danced = true;
			else if (AnimName == 'singRIGHT')
				danced = false;
			else if (AnimName == 'singUP' || AnimName == 'singDOWN')
				danced = !danced;
		}
	}

	public function addOffset(name:String, x:Float = 0, y:Float = 0):Void
	{
		animOffsets[name] = [x, y];
	}
}
