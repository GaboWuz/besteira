// Character HScript aditivo.
// Use "kadesh-hx-example" como player1/player2 no chart.
// Como não existe JSON/hardcoded com esse nome, a Kadesh cria um fallback
// seguro e este arquivo pode reconstruí-lo ou apenas ajustá-lo.

function onCreate()
{
    // "character" aponta automaticamente para a instância deste arquivo.
    // Para um personagem totalmente externo, descomente e ajuste:
    // loadCharacterAtlas('dad', 'characters/MeuPersonagem', 'sparrow');
    // addCharacterAnimation('dad', 'idle', 'Meu Idle', 24, false, 0, 0);
    // addCharacterAnimation('dad', 'singLEFT', 'Meu Left', 24, false, 0, 0);
    // addCharacterAnimation('dad', 'singDOWN', 'Meu Down', 24, false, 0, 0);
    // addCharacterAnimation('dad', 'singUP', 'Meu Up', 24, false, 0, 0);
    // addCharacterAnimation('dad', 'singRIGHT', 'Meu Right', 24, false, 0, 0);

    if (character != null)
    {
        character.color = FlxColor.fromRGB(190, 225, 255);
        character.antialiasing = true;
    }

    setCharacterIcon('dad', 'kadesh-example');
    setCharacterIdle('dad', 'idle');
}
