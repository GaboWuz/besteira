package mobile;

import flixel.FlxG;
import flixel.group.FlxSpriteGroup;
import flixel.util.FlxColor;

/**
 * Eu quando FNF'
 * @author Idklool
 */
enum HitboxType {
  DODGE;
  DEFAULT;
} // Depois eu faço (quando for nescessario, ou seja, nunc)

class HitBox extends FlxSpriteGroup
{
  public var buttonLeft:FlxButton;
  public var buttonDown:FlxButton;
  public var buttonUp:FlxButton;
  public var buttonRight:FlxButton;
  
  public function new()
  {
    super();

    buttonLeft = buttonDown = buttonUp = buttonRight = new FlxButton(0, 0);

    add(buttonLeft = createHitbox(0, 0, Std.int(FlxG.width / 4), FlxG.height, '0xC24B99'));
    add(buttonDown = createHitbox(FlxG.width / 4, 0, Std.int(FlxG.width / 4), FlxG.height, '0x00FFFF'));
    add(buttonUp = createHitbox(FlxG.width / 2, 0, Std.int(FlxG.width / 4), FlxG.height, '0x12FA05'));
    add(buttonRight = createHitbox(FlxG.width * 3 / 4, 0, Std.int(FlxG.width / 4), FlxG.height, '0xF9393F'));

    scrollFactor.set();
  }
  
  function createHitbox(x:Float, y:Float, width:Int, height:Int, color:String)
  {
    var button:FlxButton = new FlxButton(x, y);

    button.makeGraphic(width, height, FlxColor.fromString(color));

    button.alpha = 0.1;

    button.onDown.callback = () -> button.alpha = 0.001;

    button.onUp.callback = () -> button.alpha = 0.001;

    button.onOut.callback = button.onUp.callback;

    return button;
  }

  override function destroy()
  {
    super.destroy();

    buttonLeft = buttonDown = buttonUp = buttonRight = null;
  }
}