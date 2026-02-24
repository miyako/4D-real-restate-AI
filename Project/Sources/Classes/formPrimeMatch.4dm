//%attributes = {"lang":"en"} comment added and reserved by 4D
// Class: formPrimeMatch
// Description: Form class for the PrimeMatch AI-Driven Investment Screener.
//   100% class-based — all AI logic, data loading, and search live here.
//   Full XLIFF localization support (EN/FR) via Localized string().

// --- Properties: Filters ---
property regionList : Object
property assetTypeList : Object
property minYield : Integer
property minYieldDisplay : Text
property mandateText : Text

// --- Properties: Results ---
property searchResults : Collection
property selectedResult : Object
property selectedIndex : Integer
property resultCountLabel : Text

// --- Properties: Detail Panel ---
property detailName : Text
property detailDescription : Text
property detailHighlights : Text
property detailMetrics : Text

// --- Properties: Status ---
property statusMessage : Text
property lastQueryDisplay : Text
property providerLabel : Text

// --- Properties: Progress animation ---
property analysisProgress : Integer
property _progressDirection : Integer

// --- Properties: Expand/collapse ---
property _resultsExpanded : Boolean

//MARK: - Constructor

Class constructor()
	
	// --- Language initialization ---
	// Read saved language preference and set localization BEFORE building UI strings
	var $settings : Object
	$settings:=cs.AppUtils.me.readSettings()
	var $lang : Text
	$lang:=$settings.language
	If ($lang="")
		$lang:="en"
	End if 
	SET DATABASE LOCALIZATION($lang)
	
	// Region dropdown
	This.regionList:={values: ["All"; "North America"; "Europe"; "Asia Pacific"; "Latin America"; "Middle East"; "Africa"]; index: 0}
	
	// Asset type dropdown
	This.assetTypeList:={values: ["All"; "Office"; "Industrial"; "Retail"; "Multifamily"; "Healthcare"; "Life Sciences"; "Hospitality"; "Mixed-Use"; "Land"]; index: 0}
	
	// Yield slider (0-100 mapped to 0.0-10.0%)
	This.minYield:=0
	This.minYieldDisplay:="0.0%"
	
	// Mandate
	This.mandateText:=""
	
	// Results
	This.searchResults:=[]
	This.selectedResult:=Null
	This.selectedIndex:=0
	This.resultCountLabel:=""
	
	// Detail panel
	This.detailName:=""
	This.detailDescription:=""
	This.detailHighlights:=""
	This.detailMetrics:=""
	
	// Status
	This.statusMessage:=cs.AppUtils.me.loc("msg_ready")
	
	// Build header AI summary from settings
	This._refreshHeaderSummary()
	
	// Check if data already loaded
	var $propCount : Integer
	$propCount:=ds.Properties.all().length
	If ($propCount>0)
		This.statusMessage:=cs.AppUtils.me.locP("msg_props_in_db"; New collection($propCount))
	End if 

//MARK: - Header summary

Function _refreshHeaderSummary()
	var $s : Object
	$s:=cs.AppUtils.me.readSettings()
	
	var $embedInfo : Text
	$embedInfo:=$s.embedding.server+": "+$s.embedding.model
	var $chatInfo : Text
	$chatInfo:=$s.chat.server+": "+$s.chat.model
	var $dateInfo : Text
	If ($s.lastEmbeddingDate#"")
		$dateInfo:="  |  "+cs.AppUtils.me.locP("msg_last_embed"; New collection($s.lastEmbeddingDate))
	Else 
		$dateInfo:="  |  "+cs.AppUtils.me.loc("msg_no_embeddings_yet")
	End if 
	
	This.providerLabel:="Embed: "+$embedInfo+"  |  Chat: "+$chatInfo+$dateInfo

//MARK: - AI Client factory

Function _createClient($serverName : Text) -> $client : Object
	// Creates an AIKit OpenAI client for the given server name.
	// If openai and no API key, prompts the user.
	var $settings : Object
	$settings:=cs.AppUtils.me.readSettings()
	var $serverConfig : Object
	$serverConfig:=$settings.servers[$serverName]
	
	If ($serverConfig=Null)
		ALERT(cs.AppUtils.me.locP("msg_server_not_config"; New collection($serverName)))
		return
	End if 
	
	// If OpenAI and no API key, prompt
	If ($serverName="openai") && (($serverConfig.apiKey="") || ($serverConfig.apiKey=Null))
		var $key : Text
		$key:=Request(cs.AppUtils.me.loc("msg_enter_api_key"); "")
		If (OK=1) && ($key#"")
			$serverConfig.apiKey:=$key
			$settings.servers.openai.apiKey:=$key
			cs.AppUtils.me.saveSettings($settings)
		Else 
			ALERT(cs.AppUtils.me.loc("msg_api_key_required"))
			return
		End if 
	End if 
	
	$client:=Try(cs.AIKit.OpenAI.new({apiKey: $serverConfig.apiKey; baseURL: $serverConfig.baseURL}))

//MARK: - Generate Embedding

Function _generateEmbedding($text : Text) -> $vector : Object
	var $settings : Object
	$settings:=cs.AppUtils.me.readSettings()
	
	var $client : Object
	$client:=This._createClient($settings.embedding.server)
	
	If ($client=Null)
		return
	End if 
	
	var $result : Object
	$result:=Try($client.embeddings.create($text; $settings.embedding.model))
	
	If ($result#Null)
		If ($result.success)
			$vector:=$result.vector
		Else 
			var $errMsg : Text
			$errMsg:=cs.AppUtils.me.locP("msg_embed_error"; New collection($settings.embedding.server; $settings.embedding.model))
			If ($result.errors#Null) && ($result.errors.length>0)
				$errMsg:=$errMsg+": "+JSON Stringify($result.errors)
			End if 
			ALERT($errMsg)
		End if 
	Else 
		ALERT(cs.AppUtils.me.locP("msg_embed_null"; New collection($settings.embedding.server; $settings.embedding.model)))
	End if 

//MARK: - Execute Search

Function _executeSearch($mandateText : Text; $filterRegion : Text; $filterAssetType : Text; $filterMinYield : Real) -> $results : Collection
	$results:=New collection
	
	If ($mandateText="")
		ALERT(cs.AppUtils.me.loc("msg_enter_mandate"))
		return
	End if 
	
	// 1. Generate embedding for the mandate
	var $mandateVector : Object
	$mandateVector:=This._generateEmbedding($mandateText)
	
	If ($mandateVector=Null)
		ALERT(cs.AppUtils.me.loc("msg_embed_failed"))
		return
	End if 
	
	// 2. Combined ORDA query — vector similarity + conventional filters in a single native pass.
	//    4D handles the vector comparison via >= operator with a comparison object.
	//    See: blog.4d.com/4d-ai-searching-entities-by-vector-similarity-in-4d/
	var $vectorParam : Object
	$vectorParam:={vector: $mandateVector; metric: mk cosine; threshold: 0.2}
	
	var $queryParts : Collection
	$queryParts:=New collection("vectorDesc >= :1")
	
	If ($filterRegion#"All") && ($filterRegion#"")
		$queryParts.push("region = :2")
	End if 
	
	If ($filterAssetType#"All") && ($filterAssetType#"")
		$queryParts.push("assetType = :3")
	End if 
	
	If ($filterMinYield>0)
		$queryParts.push("askingYield >= :4")
	End if 
	
	var $queryString : Text
	$queryString:=$queryParts.join(" and ")
	
	// Build human-readable query for status display
	var $displayQuery : Text
	$displayQuery:=Replace string($queryString; ":1"; "{vector:[mandateVector]; metric:cosine; threshold:"+String($vectorParam.threshold)+"}")
	$displayQuery:=Replace string($displayQuery; ":2"; "\""+ $filterRegion+"\"")
	$displayQuery:=Replace string($displayQuery; ":3"; "\""+$filterAssetType+"\"")
	$displayQuery:=Replace string($displayQuery; ":4"; String($filterMinYield))
	This.lastQueryDisplay:="ds.Properties.query(\""+$displayQuery+"\")"
	
	var $filtered : cs.PropertiesSelection
	$filtered:=ds.Properties.query($queryString; $vectorParam; $filterRegion; $filterAssetType; $filterMinYield)
	
	// 3. Compute match percentage for display (only on pre-filtered results)
	var $entity : cs.PropertiesEntity
	var $similarity : Real
	var $pct : Real
	For each ($entity; $filtered)
		$similarity:=$entity.vectorDesc.cosineSimilarity($mandateVector)
		$pct:=Round(($similarity+1)/2*100; 1)
		
		$results.push(New object(\
			"ID"; $entity.ID; \
			"propertyName"; $entity.propertyName; \
			"region"; $entity.region; \
			"assetType"; $entity.assetType; \
			"askingYield"; $entity.askingYield; \
			"description"; $entity.description; \
			"askingPrice"; $entity.askingPrice; \
			"sqft"; $entity.sqft; \
			"yearBuilt"; $entity.yearBuilt; \
			"matchScore"; $pct))
	End for each 
	
	$results:=$results.orderBy("matchScore desc")
	
	// 4. Save to search history
	var $history : cs.SearchHistoryEntity
	$history:=ds.SearchHistory.new()
	$history.mandateText:=$mandateText
	$history.filterRegion:=$filterRegion
	$history.filterAssetType:=$filterAssetType
	$history.filterMinYield:=$filterMinYield
	$history.searchDate:=Current date
	$history.resultCount:=$results.length
	$history.save()

//MARK: - Load Demo Data (was PM_LoadDemoData)

Function _loadDemoData()
	var $file : 4D.File
	$file:=File("/RESOURCES/demo_properties.json")
	
	If (Not($file.exists))
		ALERT(cs.AppUtils.me.loc("msg_demo_not_found"))
		return
	End if 
	
	var $properties : Collection
	$properties:=JSON Parse($file.getText("utf-8"))
	
	If ($properties=Null)
		ALERT(cs.AppUtils.me.loc("msg_demo_parse_fail"))
		return
	End if 
	
	// Clear existing data (demo reset)
	var $all : cs.PropertiesSelection
	$all:=ds.Properties.all()
	If ($all.length>0)
		$all.drop()
	End if 
	
	var $count : Integer
	var $embedOK : Integer
	var $embedFail : Integer
	var $saveFail : Integer
	$count:=0
	$embedOK:=0
	$embedFail:=0
	$saveFail:=0
	
	var $total : Integer
	$total:=$properties.length
	
	var $prop : Object
	var $entity : cs.PropertiesEntity
	For each ($prop; $properties)
		$count:=$count+1
		This.statusMessage:=cs.AppUtils.me.locP("msg_loading_props"; New collection($count; $total))
		
		$entity:=ds.Properties.new()
		$entity.propertyName:=$prop.propertyName
		$entity.region:=$prop.region
		$entity.assetType:=$prop.assetType
		$entity.askingYield:=Num($prop.askingYield)
		$entity.description:=$prop.description
		$entity.askingPrice:=Num($prop.askingPrice)
		$entity.sqft:=Num($prop.sqft)
		$entity.yearBuilt:=Num($prop.yearBuilt)
		
		// Generate embedding
		var $vector : Object
		$vector:=Try(This._generateEmbedding($prop.description))
		If ($vector#Null)
			$entity.vectorDesc:=$vector
			$embedOK:=$embedOK+1
		Else 
			$embedFail:=$embedFail+1
		End if 
		
		var $saveStatus : Object
		$saveStatus:=$entity.save()
		If (Not($saveStatus.success))
			$saveFail:=$saveFail+1
		End if 
	End for each 
	
	// Update last embedding date
	var $settings : Object
	$settings:=cs.AppUtils.me.readSettings()
	$settings.lastEmbeddingDate:=String(Current date; ISO date; Current time)
	cs.AppUtils.me.saveSettings($settings)
	
	// Report
	var $actualCount : Integer
	$actualCount:=ds.Properties.all().length
	var $msg : Text
	$msg:=cs.AppUtils.me.locP("msg_props_loaded"; New collection($actualCount; $embedOK))
	If ($embedFail>0)
		$msg:=$msg+cs.AppUtils.me.locP("msg_embed_failures"; New collection($embedFail))
	End if 
	If ($saveFail>0)
		$msg:=$msg+cs.AppUtils.me.locP("msg_save_failures"; New collection($saveFail))
	End if 
	This.statusMessage:=$msg
	This._refreshHeaderSummary()

//MARK: - Regenerate all embeddings

Function _regenerateEmbeddings()
	var $all : cs.PropertiesSelection
	$all:=ds.Properties.all()
	var $total : Integer
	$total:=$all.length
	
	If ($total=0)
		This.statusMessage:=cs.AppUtils.me.loc("msg_no_props_regen")
		return
	End if 
	
	var $success : Integer
	var $fail : Integer
	$success:=0
	$fail:=0
	
	var $entity : cs.PropertiesEntity
	For each ($entity; $all)
		This.statusMessage:=cs.AppUtils.me.locP("msg_regen_progress"; New collection($success+$fail+1; $total))
		
		var $vec : Object
		$vec:=This._generateEmbedding($entity.description)
		
		If ($vec#Null)
			$entity.vectorDesc:=$vec
			If ($entity.save().success)
				$success:=$success+1
			Else 
				$fail:=$fail+1
			End if 
		Else 
			$fail:=$fail+1
		End if 
	End for each 
	
	// Update last embedding date
	var $settings : Object
	$settings:=cs.AppUtils.me.readSettings()
	$settings.lastEmbeddingDate:=String(Current date; ISO date; Current time)
	cs.AppUtils.me.saveSettings($settings)
	
	This.statusMessage:=cs.AppUtils.me.locP("msg_regen_done"; New collection($success; $total))
	If ($fail>0)
		This.statusMessage:=This.statusMessage+cs.AppUtils.me.locP("msg_regen_failed"; New collection($fail))
	End if 
	This._refreshHeaderSummary()

//MARK: - Form & form objects event handlers

Function formEventHandler($formEventCode : Integer)
	Case of 
		: ($formEventCode=On Load)
			// Apply localized titles to all form objects
			This._applyLocalization()
			// Hide progress bar initially
			OBJECT SET VISIBLE(*; "progressAnalysis"; False)
			This.analysisProgress:=0
			This._progressDirection:=5
			// Dark background for dropdowns (fill not supported on dropdown type)
			var $darkBg : Integer
			$darkBg:=0x000D1826
			OBJECT SET RGB COLORS(*; "ddRegion"; -1; $darkBg)
			OBJECT SET RGB COLORS(*; "ddAssetType"; -1; $darkBg)
			// Start in compact mode (results panel hidden)
			This._collapseResults(True)
			
		: ($formEventCode=On Timer)
			// Animate the progress bar back & forth
			This.analysisProgress:=This.analysisProgress+This._progressDirection
			If (This.analysisProgress>=100)
				This._progressDirection:=-5
			End if 
			If (This.analysisProgress<=0)
				This._progressDirection:=5
			End if 
			
	End case 

//MARK: - Slider event handler

Function sliderYieldEventHandler($formEventCode : Integer)
	Case of 
		: ($formEventCode=On Data Change)
			var $yieldVal : Real
			$yieldVal:=This.minYield/10
			This.minYieldDisplay:=String($yieldVal; "##0.0")+"%"
	End case 

//MARK: - Button: Execute Intelligence Match

Function btnExecuteEventHandler($formEventCode : Integer)
	Case of 
		: ($formEventCode=On Clicked)
			If (This.mandateText="")
				ALERT(cs.AppUtils.me.loc("msg_enter_mandate_search"))
			Else 
				This.statusMessage:=cs.AppUtils.me.loc("msg_searching")
				OBJECT SET ENABLED(*; "btnExecute"; False)
				
				var $selRegion : Text
				var $selAsset : Text
				var $selYield : Real
				
				$selRegion:=This.regionList.values[This.regionList.index]
				$selAsset:=This.assetTypeList.values[This.assetTypeList.index]
				$selYield:=This.minYield/10
				
				This.searchResults:=This._executeSearch(This.mandateText; $selRegion; $selAsset; $selYield)
				
				// Expand the results panel if not already visible
				This._expandResults()
				
				This.resultCountLabel:=cs.AppUtils.me.locP("msg_n_results"; New collection(This.searchResults.length))
				This.statusMessage:=cs.AppUtils.me.locP("msg_search_complete"; New collection(This.searchResults.length))+"\n"+This.lastQueryDisplay
				
				// Clear detail panel
				This.detailName:=""
				This.detailDescription:=""
				This.detailHighlights:=""
				This.detailMetrics:=""
				This.selectedResult:=Null
				This.selectedIndex:=0
				
				OBJECT SET ENABLED(*; "btnExecute"; True)
			End if 
	End case 

//MARK: - Button: Load Demo Data

Function btnLoadDataEventHandler($formEventCode : Integer)
	Case of 
		: ($formEventCode=On Clicked)
			This.statusMessage:=cs.AppUtils.me.loc("msg_loading_demo")
			This._loadDemoData()
	End case 

//MARK: - Button: Regenerate Embeddings

Function btnReembedEventHandler($formEventCode : Integer)
	Case of 
		: ($formEventCode=On Clicked)
			var $count : Integer
			$count:=ds.Properties.all().length
			If ($count=0)
				ALERT(cs.AppUtils.me.loc("msg_no_props_db"))
			Else 
				var $settings : Object
				$settings:=cs.AppUtils.me.readSettings()
				If (CONFIRM(cs.AppUtils.me.locP("msg_confirm_regen"; New collection($count; $settings.embedding.server; $settings.embedding.model)); cs.AppUtils.me.loc("msg_btn_regenerate"); cs.AppUtils.me.loc("msg_btn_cancel")))
					This._regenerateEmbeddings()
				End if 
			End if 
	End case 

//MARK: - Button: Open AI Config dialog

Function btnAIConfigEventHandler($formEventCode : Integer)
	Case of 
		: ($formEventCode=On Clicked)
			// Open the AI configuration dialog
			var $w : Integer
			$w:=Open form window("AIConfig"; Movable form dialog box)
			DIALOG("AIConfig")
			CLOSE WINDOW($w)
			// After dialog closes, refresh the header summary and re-apply localization (language may have changed)
			var $settings : Object
			$settings:=cs.AppUtils.me.readSettings()
			var $lang : Text
			$lang:=$settings.language
			If ($lang="")
				$lang:="en"
			End if 
			SET DATABASE LOCALIZATION($lang)
			This._applyLocalization()
			This._refreshHeaderSummary()
	End case 

//MARK: - Demo Scenarios

Function btnDemoAEventHandler($formEventCode : Integer)
	Case of 
		: ($formEventCode=On Clicked)
			This.mandateText:="Carbon-neutral office space for tech tenants with sustainable building features and high-speed connectivity."
			This.regionList.index:=0
			This.assetTypeList.index:=0
			This.minYield:=0
			This.minYieldDisplay:="0.0%"
			This.statusMessage:=cs.AppUtils.me.loc("msg_demo_a_loaded")
	End case 

Function btnDemoBEventHandler($formEventCode : Integer)
	Case of 
		: ($formEventCode=On Clicked)
			This.mandateText:="Value-add opportunities in urban centers with high vacancy, requiring renovation and repositioning to capture rental upside."
			This.regionList.index:=0
			This.assetTypeList.index:=0
			This.minYield:=50
			This.minYieldDisplay:="5.0%"
			This.statusMessage:=cs.AppUtils.me.loc("msg_demo_b_loaded")
	End case 

Function btnDemoCEventHandler($formEventCode : Integer)
	Case of 
		: ($formEventCode=On Clicked)
			This.mandateText:="Entrepôt logistique du dernier kilomètre en zone urbaine dense, avec certification environnementale et accès multimodal rail-route pour opérateurs e-commerce."
			This.regionList.index:=0
			This.assetTypeList.index:=0
			This.minYield:=0
			This.minYieldDisplay:="0.0%"
			This.statusMessage:=cs.AppUtils.me.loc("msg_demo_c_loaded")
	End case 

Function btnDemoDEventHandler($formEventCode : Integer)
	Case of 
		: ($formEventCode=On Clicked)
			This.mandateText:="Immeuble de bureaux haut de gamme en centre-ville avec potentiel de restructuration lourde, proche des transports en commun, adapté au travail hybride et au bien-être des occupants."
			This.regionList.index:=0
			This.assetTypeList.index:=0
			This.minYield:=40
			This.minYieldDisplay:="4.0%"
			This.statusMessage:=cs.AppUtils.me.loc("msg_demo_d_loaded")
	End case 

//MARK: - Listbox: Results selection

Function listboxResultsEventHandler($formEventCode : Integer)
	Case of 
		: ($formEventCode=On Selection Change)
			If (This.selectedResult#Null)
				This.detailName:=This.selectedResult.propertyName+cs.AppUtils.me.loc("msg_match_label")+String(This.selectedResult.matchScore; "###.#")+"%"
				This.detailDescription:=This.selectedResult.description
				This.detailMetrics:=cs.AppUtils.me.locP("msg_detail_metrics"; New collection(\
					This.selectedResult.region; \
					This.selectedResult.assetType; \
					String(This.selectedResult.askingYield; "##0.0"); \
					String(This.selectedResult.askingPrice; "###,###,##0"); \
					String(This.selectedResult.sqft; "###,###,##0"); \
					String(This.selectedResult.yearBuilt)))
				
				This.detailHighlights:=cs.AppUtils.me.loc("msg_generating_analysis")
				
				// Show progress bar and start animation timer
				This.analysisProgress:=0
				This._progressDirection:=5
				OBJECT SET VISIBLE(*; "progressAnalysis"; True)
				SET TIMER(3)  // ~50ms ticks for smooth animation
				
				// Run AI call asynchronously via a worker so the UI stays responsive
				var $mandate : Text
				var $description : Text
				var $matchScore : Real
				var $isFrench : Boolean
				var $formWindow : Integer
				var $settingsLang : Object
				$mandate:=This.mandateText
				$description:=This.selectedResult.description
				$matchScore:=This.selectedResult.matchScore
				$settingsLang:=cs.AppUtils.me.readSettings()
				$isFrench:=($settingsLang.language="fr")
				$formWindow:=Current form window
				
				CALL WORKER("semanticWorker"; "_semanticHighlightsAsync"; $mandate; $description; $matchScore; $isFrench; $formWindow)
			End if 
	End case 

//MARK: - Expand / Collapse results panel

Function _collapseResults($center : Boolean)
	// Hide all right-panel objects and shrink the window
	This._resultsExpanded:=False
	var $rightObjects : Collection
	$rightObjects:=New collection("resultsAccent"; "labelResults"; "lblResultCount"; \
		"cardResults"; "listboxResults"; \
		"detailAccent"; "labelDetail"; "lblSelectedName"; \
		"cardDescription"; "labelDescTitle"; "txtDescription"; \
		"cardHighlights"; "labelHighlightsTitle"; "progressAnalysis"; "txtHighlights"; \
		"labelMetrics"; "footerProvider")
	var $obj : Text
	For each ($obj; $rightObjects)
		OBJECT SET VISIBLE(*; $obj; False)
	End for each 
	// Hide collapse button
	OBJECT SET VISIBLE(*; "btnCollapseResults"; False)
	// Move AI Config button into compact area
	OBJECT SET COORDINATES(*; "btnAIConfig"; 400; 14; 520; 44)
	// Widen left-panel elements to fill compact width
	OBJECT SET COORDINATES(*; "ddRegion"; 120; 122; 504; 150)
	OBJECT SET COORDINATES(*; "ddAssetType"; 120; 158; 504; 186)
	OBJECT SET COORDINATES(*; "txtThesis"; 24; 266; 510; 420)
	OBJECT SET COORDINATES(*; "btnExecute"; 24; 434; 510; 482)
	OBJECT SET COORDINATES(*; "separatorBtns"; 28; 498; 510; 498)
	OBJECT SET COORDINATES(*; "labelDemoSection"; 28; 510; 510; 532)
	OBJECT SET COORDINATES(*; "btnDemoA"; 24; 538; 256; 576)
	OBJECT SET COORDINATES(*; "btnDemoB"; 264; 538; 510; 576)
	OBJECT SET COORDINATES(*; "btnDemoC"; 24; 582; 256; 620)
	OBJECT SET COORDINATES(*; "btnDemoD"; 264; 582; 510; 620)
	OBJECT SET COORDINATES(*; "separatorBtns2"; 28; 636; 510; 636)
	OBJECT SET COORDINATES(*; "btnLoadData"; 24; 652; 256; 690)
	OBJECT SET COORDINATES(*; "btnReembed"; 264; 652; 510; 690)
	OBJECT SET COORDINATES(*; "labelStatus"; 24; 706; 510; 860)
	// Adjust footer text width for compact
	OBJECT SET COORDINATES(*; "footerText"; 28; 876; 520; 896)
	// Resize window to compact width
	var $compactWidth : Integer
	$compactWidth:=540
	If ($center)
		var $screenL; $screenT; $screenR; $screenB : Integer
		SCREEN COORDINATES($screenL; $screenT; $screenR; $screenB)
		var $winL; $winT : Integer
		$winL:=($screenR-$screenL-$compactWidth)/2
		$winT:=($screenB-$screenT-900)/2
		SET WINDOW RECT($winL; $winT; $winL+$compactWidth; $winT+900; Current form window)
	Else 
		var $curL; $curT; $curR; $curB : Integer
		GET WINDOW RECT($curL; $curT; $curR; $curB; Current form window)
		SET WINDOW RECT($curL; $curT; $curL+$compactWidth; $curB; Current form window)
	End if 

Function _expandResults()
	This._resultsExpanded:=True
	var $rightObjects : Collection
	$rightObjects:=New collection("resultsAccent"; "labelResults"; "lblResultCount"; \
		"cardResults"; "listboxResults"; \
		"detailAccent"; "labelDetail"; "lblSelectedName"; \
		"cardDescription"; "labelDescTitle"; "txtDescription"; \
		"cardHighlights"; "labelHighlightsTitle"; "txtHighlights"; \
		"labelMetrics"; "footerProvider")
	var $obj : Text
	For each ($obj; $rightObjects)
		OBJECT SET VISIBLE(*; $obj; True)
	End for each 
	// Show collapse button
	OBJECT SET VISIBLE(*; "btnCollapseResults"; True)
	// Restore AI Config button to original position
	OBJECT SET COORDINATES(*; "btnAIConfig"; 1300; 14; 1420; 44)
	// Restore left-panel elements to original sizes
	OBJECT SET COORDINATES(*; "ddRegion"; 120; 122; 388; 150)
	OBJECT SET COORDINATES(*; "ddAssetType"; 120; 158; 388; 186)
	OBJECT SET COORDINATES(*; "txtThesis"; 24; 266; 390; 420)
	OBJECT SET COORDINATES(*; "btnExecute"; 24; 434; 390; 482)
	OBJECT SET COORDINATES(*; "separatorBtns"; 28; 498; 386; 498)
	OBJECT SET COORDINATES(*; "labelDemoSection"; 28; 510; 388; 532)
	OBJECT SET COORDINATES(*; "btnDemoA"; 24; 538; 202; 576)
	OBJECT SET COORDINATES(*; "btnDemoB"; 210; 538; 390; 576)
	OBJECT SET COORDINATES(*; "btnDemoC"; 24; 582; 202; 620)
	OBJECT SET COORDINATES(*; "btnDemoD"; 210; 582; 390; 620)
	OBJECT SET COORDINATES(*; "separatorBtns2"; 28; 636; 386; 636)
	OBJECT SET COORDINATES(*; "btnLoadData"; 24; 652; 202; 690)
	OBJECT SET COORDINATES(*; "btnReembed"; 210; 652; 390; 690)
	OBJECT SET COORDINATES(*; "labelStatus"; 24; 706; 390; 860)
	// Restore footer text width
	OBJECT SET COORDINATES(*; "footerText"; 28; 876; 628; 896)
	// Expand window keeping current position
	var $fullWidth : Integer
	$fullWidth:=1440
	var $curL; $curT; $curR; $curB : Integer
	GET WINDOW RECT($curL; $curT; $curR; $curB; Current form window)
	// Find which screen the window is on (use left edge)
	var $screenL; $screenT; $screenR; $screenB : Integer
	var $numScreens; $i : Integer
	$numScreens:=Count screens
	var $sL; $sT; $sR; $sB : Integer
	$screenL:=0
	$screenT:=0
	$screenR:=0
	$screenB:=0
	For ($i; 1; $numScreens)
		SCREEN COORDINATES($sL; $sT; $sR; $sB; $i)
		If ($curL>=$sL)
			If ($curL<$sR)
				$screenL:=$sL
				$screenT:=$sT
				$screenR:=$sR
				$screenB:=$sB
			End if 
		End if 
	End for 
	If ($screenR=$screenL)
		// Fallback to main screen
		SCREEN COORDINATES($screenL; $screenT; $screenR; $screenB)
	End if 
	// Check if expanding would go off-screen on the detected monitor
	var $newR : Integer
	$newR:=$curL+$fullWidth
	If ($newR>$screenR)
		$curL:=$screenR-$fullWidth
		If ($curL<$screenL)
			$curL:=$screenL
		End if 
	End if
	SET WINDOW RECT($curL; $curT; $curL+$fullWidth; $curB; Current form window)

//MARK: - Callback: Highlights received from worker

Function _onHighlightsReceived($highlights : Text)
	This.detailHighlights:=$highlights
	SET TIMER(0)
	OBJECT SET VISIBLE(*; "progressAnalysis"; False)

//MARK: - Localization: Apply titles to form objects

Function _applyLocalization()
	// Programmatically set all form object titles using Localized string().
	// This ensures XLIFF strings display even if form JSON :xliff: refs don't resolve.
	
	// Header
	OBJECT SET TITLE(*; "headerTitle"; cs.AppUtils.me.loc("pm_title"))
	OBJECT SET TITLE(*; "btnAIConfig"; cs.AppUtils.me.loc("pm_ai_settings"))
	
	// Left panel labels
	OBJECT SET TITLE(*; "labelMandatePanel"; cs.AppUtils.me.loc("pm_mandate_input"))
	OBJECT SET TITLE(*; "labelRegion"; cs.AppUtils.me.loc("pm_region"))
	OBJECT SET TITLE(*; "labelAssetType"; cs.AppUtils.me.loc("pm_asset_type"))
	OBJECT SET TITLE(*; "labelYield"; cs.AppUtils.me.loc("pm_min_yield"))
	OBJECT SET TITLE(*; "labelThesis"; cs.AppUtils.me.loc("pm_thesis_label"))
	
	// Execute button
	OBJECT SET TITLE(*; "btnExecute"; cs.AppUtils.me.loc("pm_execute"))
	
	// Demo section
	OBJECT SET TITLE(*; "labelDemoSection"; cs.AppUtils.me.loc("pm_demo_section"))
	OBJECT SET TITLE(*; "btnDemoA"; cs.AppUtils.me.loc("pm_demo_a"))
	OBJECT SET TITLE(*; "btnDemoB"; cs.AppUtils.me.loc("pm_demo_b"))
	OBJECT SET TITLE(*; "btnDemoC"; cs.AppUtils.me.loc("pm_demo_c"))
	OBJECT SET TITLE(*; "btnDemoD"; cs.AppUtils.me.loc("pm_demo_d"))
	
	// Load / Regenerate buttons
	OBJECT SET TITLE(*; "btnLoadData"; cs.AppUtils.me.loc("pm_load_data"))
	OBJECT SET TITLE(*; "btnReembed"; cs.AppUtils.me.loc("pm_regenerate"))
	
	// Right panel labels
	OBJECT SET TITLE(*; "labelResults"; cs.AppUtils.me.loc("pm_results"))
	OBJECT SET TITLE(*; "labelDetail"; cs.AppUtils.me.loc("pm_detail"))
	OBJECT SET TITLE(*; "labelDescTitle"; cs.AppUtils.me.loc("pm_description"))
	OBJECT SET TITLE(*; "labelHighlightsTitle"; cs.AppUtils.me.loc("pm_highlights"))
	
	// Listbox column headers
	OBJECT SET TITLE(*; "colMatchHeader"; cs.AppUtils.me.loc("pm_col_match"))
	OBJECT SET TITLE(*; "colNameHeader"; cs.AppUtils.me.loc("pm_col_name"))
	OBJECT SET TITLE(*; "colRegionHeader"; cs.AppUtils.me.loc("pm_col_region"))
	OBJECT SET TITLE(*; "colTypeHeader"; cs.AppUtils.me.loc("pm_col_asset"))
	OBJECT SET TITLE(*; "colYieldHeader"; cs.AppUtils.me.loc("pm_col_yield"))
	OBJECT SET TITLE(*; "colPriceHeader"; cs.AppUtils.me.loc("pm_col_price"))
	OBJECT SET TITLE(*; "colSqftHeader"; cs.AppUtils.me.loc("pm_col_sqft"))
	
	// Footer
	OBJECT SET TITLE(*; "footerText"; cs.AppUtils.me.loc("pm_footer"))

//MARK: - Button: Close window

Function btnCloseEventHandler($formEventCode : Integer)
	Case of 
		: ($formEventCode=On Clicked)
			CANCEL
		: ($formEventCode=On Mouse Enter)
			OBJECT SET FORMAT(*; "btnClose"; ";path:/RESOURCES/images/mac/close2.png")
		: ($formEventCode=On Mouse Leave)
			OBJECT SET FORMAT(*; "btnClose"; ";path:/RESOURCES/images/mac/close.png")
	End case 

//MARK: - Button: Collapse results

Function btnCollapseResultsEventHandler($formEventCode : Integer)
	Case of 
		: ($formEventCode=On Clicked)
			This._collapseResults()
	End case 

//MARK: - Button: Drag window

Function btnDragWindowEventHandler($formEventCode : Integer)
	DRAG WINDOW
