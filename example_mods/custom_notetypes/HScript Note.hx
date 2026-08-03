function goodNoteHit(id, direction, noteType, isSustainNote)
{
    if (noteType == 'HScript Note' && !isSustainNote)
        triggerEvent('Add Camera Zoom', '0.01', '0.015');
}

function opponentNoteHit(id, direction, noteType, isSustainNote)
{
    if (noteType == 'HScript Note' && !isSustainNote)
        setProperty('dad.alpha', 0.92);
}
