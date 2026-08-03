// Use no events.json: [tempo, [["Camera Pulse", "0.02", "0.04"]]]
function onEvent(name, value1, value2)
{
    if (name == 'Camera Pulse')
        triggerEvent('Add Camera Zoom', value1 == '' ? '0.02' : value1, value2 == '' ? '0.04' : value2);
}
