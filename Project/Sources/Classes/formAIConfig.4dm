// Class: formAIConfig
// Description: Form class for the AI Configuration dialog.
//   Allows selecting separate embed/chat servers & models, and managing OpenAI API key.
//   Full XLIFF localization support via Localized string().

// --- Properties: Embed ---
property embedServerList : Object
property embedModelList : Object

// --- Properties: Chat ---
property chatServerList : Object
property chatModelList : Object

// --- Properties: Language ---
property languageList : Object

// --- Properties: OpenAI key ---
property apiKeyStatus : Text

// --- Properties: Status ---
property statusText : Text

//MARK: - Constructor

Class constructor()
	
	var $settings : Object
	$settings:=cs.AppUtils.me.readSettings()
	
	var $serverNames : Collection
	$serverNames:=OB Keys($settings.servers)
	
	// Language dropdown
	var $lang : Text
	$lang:=$settings.language
	If ($lang="")
		$lang:="en"
	End if 
	var $langIdx : Integer
	If ($lang="fr")
		$langIdx:=1
	Else 
		$langIdx:=0
	End if 
	This.languageList:={values: ["English"; "Français"; "日本語"]; index: $langIdx}
	
	// Embed server dropdown
	var $embedIdx : Integer
	$embedIdx:=$serverNames.indexOf($settings.embedding.server)
	If ($embedIdx<0)
		$embedIdx:=0
	End if 
	This.embedServerList:={values: $serverNames; index: $embedIdx}
	
	// Chat server dropdown
	var $chatIdx : Integer
	$chatIdx:=$serverNames.indexOf($settings.chat.server)
	If ($chatIdx<0)
		$chatIdx:=0
	End if 
	This.chatServerList:={values: $serverNames; index: $chatIdx}
	
	// Load models for each server
	This.embedModelList:={values: New collection; index: 0}
	This.chatModelList:={values: New collection; index: 0}
	
	This._loadModels("embed"; $settings.embedding.server; $settings.embedding.model)
	This._loadModels("chat"; $settings.chat.server; $settings.chat.model)
	
	// API key status
	This._updateApiKeyStatus()
	
	This.statusText:=cs.AppUtils.me.loc("msg_ac_load_models")
	
	
	//MARK: - Create AI client
	
Function _createClient($serverName : Text)->$client : Object
	var $settings : Object
	$settings:=cs.AppUtils.me.readSettings()
	var $serverConfig : Object
	$serverConfig:=$settings.servers[$serverName]
	
	If ($serverConfig=Null)
		This.statusText:=cs.AppUtils.me.locP("msg_ac_server_not_config"; New collection($serverName))
		return 
	End if 
	
	// For OpenAI, check API key availability but don't prompt here
	If ($serverName="openai") && (($serverConfig.apiKey="") || ($serverConfig.apiKey=Null))
		This.statusText:=cs.AppUtils.me.loc("msg_ac_no_api_key")
		return 
	End if 
	
	$client:=Try(cs.AIKit.OpenAI.new({apiKey: $serverConfig.apiKey; baseURL: $serverConfig.baseURL}))
	
	//MARK: - Load models for a role (embed or chat)
	
Function _loadModels($role : Text; $serverName : Text; $currentModel : Text)
	var $client : Object
	$client:=This._createClient($serverName)
	
	If ($client=Null)
		If ($role="embed")
			This.embedModelList:={values: New collection($currentModel); index: 0}
		Else 
			This.chatModelList:={values: New collection($currentModel); index: 0}
		End if 
		return 
	End if 
	
	var $result : Object
	$result:=Try($client.models.list())
	
	var $models : Collection
	If ($result#Null) && ($result.success)
		$models:=$result.models.extract("id").sort()
	Else 
		$models:=New collection
	End if 
	
	// If no models returned, keep at least the current one
	If ($models.length=0)
		$models:=New collection($currentModel)
	End if 
	
	var $idx : Integer
	$idx:=$models.indexOf($currentModel)
	If ($idx<0)
		$idx:=0
	End if 
	
	If ($role="embed")
		This.embedModelList:={values: $models; index: $idx}
	Else 
		This.chatModelList:={values: $models; index: $idx}
	End if 
	
	//MARK: - API key status
	
Function _updateApiKeyStatus()
	var $settings : Object
	$settings:=cs.AppUtils.me.readSettings()
	If ($settings.servers.openai.apiKey#"") && ($settings.servers.openai.apiKey#Null)
		This.apiKeyStatus:=cs.AppUtils.me.locP("msg_ac_key_set"; New collection(Substring($settings.servers.openai.apiKey; 1; 8)))
	Else 
		This.apiKeyStatus:=cs.AppUtils.me.loc("msg_ac_no_key")
	End if 
	
	//MARK: - Event handlers
	
Function formEventHandler($formEventCode : Integer)
	Case of 
		: ($formEventCode=On Load)
			This._applyLocalization()
			// Force label colors (stroke in JSON not reliable for text objects in dialogs)
			var $labelColor : Integer
			var $bgColor : Integer
			$labelColor:=0x00C0CDD8
			$bgColor:=0x000E1A2B
			OBJECT SET RGB COLORS(*; "lblLanguage"; $labelColor; $bgColor)
			OBJECT SET RGB COLORS(*; "lblEmbedServer"; $labelColor; $bgColor)
			OBJECT SET RGB COLORS(*; "lblEmbedModel"; $labelColor; $bgColor)
			OBJECT SET RGB COLORS(*; "lblChatServer"; $labelColor; $bgColor)
			OBJECT SET RGB COLORS(*; "lblChatModel"; $labelColor; $bgColor)
			// Force dropdown text to white on dark background (fill/stroke not reliable for dropdowns)
			var $ddFg : Integer
			var $ddBg : Integer
			$ddFg:=-1
			$ddBg:=0x000D1826
			OBJECT SET RGB COLORS(*; "ddLanguage"; $ddFg; $ddBg)
			OBJECT SET RGB COLORS(*; "ddEmbedServer"; $ddFg; $ddBg)
			OBJECT SET RGB COLORS(*; "ddEmbedModel"; $ddFg; $ddBg)
			OBJECT SET RGB COLORS(*; "ddChatServer"; $ddFg; $ddBg)
			OBJECT SET RGB COLORS(*; "ddChatModel"; $ddFg; $ddBg)
	End case 
	
	//MARK: - Language changed
	
Function ddLanguageEventHandler($formEventCode : Integer)
	Case of 
		: ($formEventCode=On Data Change)
			var $lang : Text
			Case of 
				: (This.languageList.index=2)
					$lang:="ja"
				: (This.languageList.index=1)
					$lang:="fr"
				Else 
					$lang:="en"
			End case 
			// Save preference immediately
			var $settings : Object
			$settings:=cs.AppUtils.me.readSettings()
			$settings.language:=$lang
			cs.AppUtils.me.saveSettings($settings)
			// Switch 4D localization
			SET DATABASE LOCALIZATION($lang)
			// Refresh Settings dialog labels
			This._applyLocalization()
	End case 
	
	//MARK: - Embed server changed
	
Function ddEmbedServerEventHandler($formEventCode : Integer)
	Case of 
		: ($formEventCode=On Data Change)
			var $serverName : Text
			$serverName:=This.embedServerList.values[This.embedServerList.index]
			This.statusText:=cs.AppUtils.me.locP("msg_ac_loading_models"; New collection($serverName))
			This._loadModels("embed"; $serverName; "")
			This.statusText:=cs.AppUtils.me.locP("msg_ac_models_loaded"; New collection(This.embedModelList.values.length; $serverName))
	End case 
	
	//MARK: - Chat server changed
	
Function ddChatServerEventHandler($formEventCode : Integer)
	Case of 
		: ($formEventCode=On Data Change)
			var $serverName : Text
			$serverName:=This.chatServerList.values[This.chatServerList.index]
			This.statusText:=cs.AppUtils.me.locP("msg_ac_loading_models"; New collection($serverName))
			This._loadModels("chat"; $serverName; "")
			This.statusText:=cs.AppUtils.me.locP("msg_ac_models_loaded"; New collection(This.chatModelList.values.length; $serverName))
	End case 
	
	//MARK: - Refresh embed models
	
Function btnRefreshEmbedEventHandler($formEventCode : Integer)
	Case of 
		: ($formEventCode=On Clicked)
			var $serverName : Text
			$serverName:=This.embedServerList.values[This.embedServerList.index]
			This.statusText:=cs.AppUtils.me.locP("msg_ac_refreshing"; New collection($serverName))
			var $currentModel : Text
			If (This.embedModelList.values.length>0)
				$currentModel:=This.embedModelList.values[This.embedModelList.index]
			Else 
				$currentModel:=""
			End if 
			This._loadModels("embed"; $serverName; $currentModel)
			This.statusText:=cs.AppUtils.me.locP("msg_ac_models_loaded"; New collection(This.embedModelList.values.length; $serverName))
	End case 
	
	//MARK: - Refresh chat models
	
Function btnRefreshChatEventHandler($formEventCode : Integer)
	Case of 
		: ($formEventCode=On Clicked)
			var $serverName : Text
			$serverName:=This.chatServerList.values[This.chatServerList.index]
			This.statusText:=cs.AppUtils.me.locP("msg_ac_refreshing"; New collection($serverName))
			var $currentModel : Text
			If (This.chatModelList.values.length>0)
				$currentModel:=This.chatModelList.values[This.chatModelList.index]
			Else 
				$currentModel:=""
			End if 
			This._loadModels("chat"; $serverName; $currentModel)
			This.statusText:=cs.AppUtils.me.locP("msg_ac_models_loaded"; New collection(This.chatModelList.values.length; $serverName))
	End case 
	
	//MARK: - Set OpenAI API key
	
Function btnSetApiKeyEventHandler($formEventCode : Integer)
	Case of 
		: ($formEventCode=On Clicked)
			var $key : Text
			$key:=Request(cs.AppUtils.me.loc("msg_enter_api_key"); "")
			If (OK=1) && ($key#"")
				var $settings : Object
				$settings:=cs.AppUtils.me.readSettings()
				$settings.servers.openai.apiKey:=$key
				cs.AppUtils.me.saveSettings($settings)
				This._updateApiKeyStatus()
				This.statusText:=cs.AppUtils.me.loc("msg_ac_api_saved")
			End if 
	End case 
	
	//MARK: - Save
	
Function btnSaveEventHandler($formEventCode : Integer)
	Case of 
		: ($formEventCode=On Clicked)
			var $settings : Object
			$settings:=cs.AppUtils.me.readSettings()
			
			// Save embed server + model
			$settings.embedding.server:=This.embedServerList.values[This.embedServerList.index]
			If (This.embedModelList.values.length>0)
				$settings.embedding.model:=This.embedModelList.values[This.embedModelList.index]
			End if 
			
			// Save chat server + model
			$settings.chat.server:=This.chatServerList.values[This.chatServerList.index]
			If (This.chatModelList.values.length>0)
				$settings.chat.model:=This.chatModelList.values[This.chatModelList.index]
			End if 
			
			cs.AppUtils.me.saveSettings($settings)
			
			// Check if embed model changed — offer to regenerate
			var $propCount : Integer
			$propCount:=ds.Properties.all().length
			If ($propCount>0)
				This.statusText:=cs.AppUtils.me.loc("msg_ac_config_saved_note")
			Else 
				This.statusText:=cs.AppUtils.me.loc("msg_ac_config_saved")
			End if 
			
			CANCEL  // Close the dialog (returns 0)
	End case 
	
	//MARK: - Cancel
	
Function btnCancelEventHandler($formEventCode : Integer)
	Case of 
		: ($formEventCode=On Clicked)
			CANCEL  // Close without saving
	End case 
	
	//MARK: - Localization: Apply titles to form objects
	
Function _applyLocalization()
	OBJECT SET TITLE(*; "headerTitle"; cs.AppUtils.me.loc("ac_title"))
	OBJECT SET TITLE(*; "lblLangSection"; cs.AppUtils.me.loc("ac_lang_section"))
	OBJECT SET TITLE(*; "lblLanguage"; cs.AppUtils.me.loc("ac_language"))
	OBJECT SET TITLE(*; "lblEmbedSection"; cs.AppUtils.me.loc("ac_embed_section"))
	OBJECT SET TITLE(*; "lblEmbedServer"; cs.AppUtils.me.loc("ac_server"))
	OBJECT SET TITLE(*; "lblEmbedModel"; cs.AppUtils.me.loc("ac_model"))
	OBJECT SET TITLE(*; "btnRefreshEmbed"; cs.AppUtils.me.loc("ac_refresh"))
	OBJECT SET TITLE(*; "lblChatSection"; cs.AppUtils.me.loc("ac_chat_section"))
	OBJECT SET TITLE(*; "lblChatServer"; cs.AppUtils.me.loc("ac_server"))
	OBJECT SET TITLE(*; "lblChatModel"; cs.AppUtils.me.loc("ac_model"))
	OBJECT SET TITLE(*; "btnRefreshChat"; cs.AppUtils.me.loc("ac_refresh"))
	OBJECT SET TITLE(*; "lblOpenAISection"; cs.AppUtils.me.loc("ac_openai_section"))
	OBJECT SET TITLE(*; "btnSetApiKey"; cs.AppUtils.me.loc("ac_set_key"))
	OBJECT SET TITLE(*; "btnSave"; cs.AppUtils.me.loc("ac_save"))
	OBJECT SET TITLE(*; "btnCancel"; cs.AppUtils.me.loc("ac_cancel"))
	
	