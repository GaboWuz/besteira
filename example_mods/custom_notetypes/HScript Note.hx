package;

function goodNoteHit(id:Int, direction:Int, noteType:String, isSustainNote:Bool):Void
{
	if (noteType != 'HScript Note') return;
	cameraFlash('camHUD', 'FFFFFF', 0.05, false);
}
