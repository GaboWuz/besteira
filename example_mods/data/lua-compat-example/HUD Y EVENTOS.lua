--[[
ショーケースモードluaファイル
MODのPV撮影などにお役立ちください。
luaの利用でのクレジット記載は不要です
制作　黒髪零@2823
--]]
function onCreate()
	doTweenColor('peso', 'dad', 'fffdf3', 1, 'linear')
	doTweenColor('pesa', 'boyfriend', 'fffdf3', 1, 'linear')
	doTweenColor('pese', 'gf', 'fffdf3', 1, 'linear')
end

function onCreatePost()

	setProperty('scoreTxt.visible', false);
	setProperty('showRating', true);
	setProperty('showComboNum', true)
	setProperty('Num.visible', false);
	setProperty('timeBar.visible', false);
	setProperty('timeBarBG.visible', false);
	setProperty('timeTxt.visible', false);
	setPropertyFromClass('Main','fpsVar.visible',false)

	function onStepHit()

		if curStep == 256 then
			noteTweenX('oppo0', 0, 400, 0.2, 'quartInOut')
			noteTweenX('oppo1', 1, 520, 0.2, 'quartInOut')
			noteTweenX('oppo2', 2, 640, 0.2, 'quartInOut')
			noteTweenX('oppo3', 3, 760, 0.2, 'quartInOut')
			noteTweenX('play0', 4, 400, 0.2, 'quartInOut')
			noteTweenX('play1', 5, 520, 0.2, 'quartInOut')
			noteTweenX('play2', 6, 640, 0.2, 'quartInOut')
			noteTweenX('play3', 7, 760, 0.2, 'quartInOut')
			for i=0,3 do
				noteTweenAlpha(i+6, i, 0.15, 0.2, 'quadInOut')		
			end
		end;

		if curStep == 320 then
			noteTweenX('oppo0', 0, 75, 0.2, 'quartInOut')
			noteTweenX('oppo1', 1, 190, 0.2, 'quartInOut')
			noteTweenX('oppo2', 2, 305, 0.2, 'quartInOut')
			noteTweenX('oppo3', 3, 420, 0.2, 'quartInOut')
			noteTweenX('play0', 4, 740, 0.2, 'quartInOut')
			noteTweenX('play1', 5, 855, 0.2, 'quartInOut')
			noteTweenX('play2', 6, 970, 0.2, 'quartInOut')
			noteTweenX('play3', 7, 1085, 0.2, 'quartInOut')
			for i=0,3 do
				noteTweenAlpha(i+6, i, 1, 0.1, 'quadInOut')		
			end
		end;

		if curStep == 900 then
			makeLuaSprite('flash', '', 0, 0);
			makeGraphic('flash',1280,720,'000000')
			addLuaSprite('flash', true);
			setLuaSpriteScrollFactor('flash',0,0)
			setProperty('flash.scale.x',2)
			setProperty('flash.scale.y',2)
			setProperty('flash.alpha',0)
			doTweenAlpha('flTw','flash',1,0.51,'linear')
		end;
		if curStep == 900 then
			for i=0,7 do
				noteTweenAlpha(i+16, i, 0, 0.51, 'quadInOut')		
			end
		end;

	end
	
end