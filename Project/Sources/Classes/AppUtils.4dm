// Class: AppUtils
// Description: Shared utility class for settings I/O and localization helpers.
//   Used by formPrimeMatch and formAIConfig to avoid code duplication.
//   All functions are shared — call via cs.AppUtils.me() singleton or cs.AppUtils.new().

property _settingsCache : Object

//MARK: - Singleton accessor

shared singleton Class constructor()
	
	//MARK: - Settings I/O
	
Function readSettings()->$settings : Object
	var $sf : 4D.File
	$sf:=File("/RESOURCES/settings.json")
	If ($sf.exists)
		$settings:=JSON Parse($sf.getText("utf-8"))
	Else 
		// Defaults
		$settings:={embedding: {server: "openai"; model: "text-embedding-ada-002"}; \
			chat: {server: "openai"; model: "gtp-5.4"}; \
			lastEmbeddingDate: ""; \
			language: "en"; \
			servers: {\
			openai: {baseURL: "https://api.openai.com/v1"; apiKey: ""}}}
	End if 
	
	var $server : Text
	For each ($server; $settings.servers)
		$settings.servers[$server].apiKey:=This._getKeyForProvider($server)
	End for each 
	
Function _secretsFolder() : 4D.Folder
	
	return Folder("/PACKAGE/Secrets")
	
Function _setKeyForProvider($provider : Text; $apiKey : Text)
	
	var $file : 4D.File
	$file:=This._secretsFolder().file($provider+".token")
	If ($file.exists) && ($file.getText()#$apiKey)
		$file.setText($apiKey)
	End if 
	
Function _getKeyForProvider($provider : Text) : Text
	
	var $file : 4D.File
	$file:=This._secretsFolder().file($provider+".token")
	return $file.exists ? $file.getText() : ""
	
Function saveSettings($settings : Object)
	
	var $server : Text
	For each ($server; $settings.servers)
		This._setKeyForProvider($server; $settings.servers[$server].apiKey)
		$settings.servers[$server].apiKey:=""
	End for each 
	
	var $sf : 4D.File
	$sf:=File("/RESOURCES/settings.json")
	$sf.setText(JSON Stringify($settings; *); "utf-8")
	
	//MARK: - Localization helpers
	
Function loc($key : Text)->$result : Text
	// Returns the localized string for the given XLIFF resname key.
	$result:=Localized string($key)
	If ($result="")
		$result:=$key
	End if 
	
Function locP($key : Text; $params : Collection)->$result : Text
	// Returns a localized string with {1}, {2}, ... placeholders substituted.
	$result:=Localized string($key)
	If ($result="")
		$result:=$key
	End if 
	var $i : Integer
	For ($i; 0; $params.length-1)
		$result:=Replace string($result; "{"+String($i+1)+"}"; String($params[$i]))
	End for 
	