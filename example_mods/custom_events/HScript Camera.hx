package;

function onEvent(name:String, value1:String, value2:String):Void
{
	if (name != 'HScript Camera') return;

	var zoom:Float = Std.parseFloat(value1);
	var duration:Float = Std.parseFloat(value2);
	if (Math.isNaN(zoom)) zoom = 0.9;
	if (Math.isNaN(duration)) duration = 0.3;

	triggerEvent('Set Camera Zoom', Std.string(zoom), Std.string(duration));
}
