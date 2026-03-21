//%attributes = {"lang":"en"}
// Method: _semanticHighlightsAsync
// Runs the chat AI call in a background worker, then sends the result
// back to the form via CALL FORM so the UI stays responsive.
// Always calls _onHighlightsReceived to stop the progress animation.

#DECLARE($mandate : Text; $description : Text; $matchScore : Real; $isFrench : Boolean; $formWindow : Integer)

var $highlights : Text
var $settings : Object
var $AppUtils : Object
$AppUtils:=cs.AppUtils.me
$settings:=$AppUtils.readSettings()

var $serverName : Text
$serverName:=$settings.chat.server
var $serverConfig : Object
$serverConfig:=$settings.servers[$serverName]

If ($serverConfig=Null)
	If ($isFrench)
		$highlights:="Serveur '"+$serverName+"' non configuré."
	Else 
		$highlights:="Server '"+$serverName+"' not configured."
	End if 
Else 
	var $client : cs.AIKit.OpenAI
	$client:=Try(cs.AIKit.OpenAI.new($serverConfig))
	
	// --- Build prompts ---
	var $systemPrompt : Text
	If ($isFrench)
		$systemPrompt:="Tu es un conseiller en investissement immobilier. Tu aides l'utilisateur à comprendre en quoi un bien immobilier correspond (ou non) à son mandat d'investissement. Structure ta réponse en deux sections claires :\n\nCE QUI CORRESPOND AU MANDAT :\nListe"+" les éléments de la description du bien qui rejoignent les critères du mandat. Cite les passages pertinents.\n\nCE QUI NE CORRESPOND PAS :\nListe les éléments du mandat qui ne trouvent pas d'écho dans la description du bien, ou les caractéristique"+"s du bien qui s'en éloignent.\n\nSi globalement le bien est éloigné du mandat, termine par une suggestion de chercher un bien avec un score de correspondance plus élevé.\nReste concis et accessible, évite le jargon technique. Réponds en français."+" Utilise du texte brut uniquement : pas de markdown, pas de gras, pas d'italique, pas de puces avec astérisques. Utilise des tirets simples (-) pour les listes."
	Else 
		$systemPrompt:="You are a real estate investment advisor. You help the user understand how well a property matches (or doesn't match) their investment mandate. Structure your answer in two clear sections:\n\nWHAT MATCHES THE MANDATE:\nList the elements from the property"+" description that align with the mandate criteria. Quote relevant passages.\n\nWHAT DOESN'T MATCH:\nList the mandate criteria that are not reflected in the property description, or property characteristics that diverge from the mandate.\n\nIf overall the p"+"roperty is far from the mandate, end with a suggestion to look for a property with a higher match score.\nBe concise and accessible, avoid overly technical language. Use plain text only: no markdown, no bold, no italics, no asterisks. Use simple dashes"+" (-) for bullet points."
	End if 
	
	var $userPrompt : Text
	If ($isFrench)
		$userPrompt:="MANDAT D'INVESTISSEMENT :\n\""+$mandate+"\"\n\nDESCRIPTION DU BIEN :\n\""+$description+"\"\n\nScore de correspondance : "+String($matchScore; "###.#")+"%\n\nExplique en quoi ce bien correspond ou non au mandat. Organise ta réponse en deux parties : ce qui correspond au mandat, et ce qui ne correspond pas. Réponds en français, en texte brut."
	Else 
		$userPrompt:="INVESTMENT MANDATE:\n\""+$mandate+"\"\n\nPROPERTY DESCRIPTION:\n\""+$description+"\"\n\nMatch score: "+String($matchScore; "###.#")+"%\n\nExplain how this property matches or doesn't match the mandate. Organize your answer in two parts: what matches the mandate, and what doesn't. Reply in plain text."
	End if 
	
	var $chatModel : Text
	$chatModel:=$settings.chat.model
	
	var $messages : Collection
	$messages:=New collection(\
		New object("role"; "system"; "content"; $systemPrompt); \
		New object("role"; "user"; "content"; $userPrompt))
	
	// --- Call AI ---
	var $chatResult : Object
	$chatResult:=Try($client.chat.completions.create($messages; {model: $chatModel}))
	
	If ($chatResult#Null) && ($chatResult.success)
		$highlights:=$chatResult.choice.message.text
	Else 
		If ($chatResult#Null)
			If ($isFrench)
				$highlights:="Analyse impossible (modèle : "+$chatModel+").\nScore : "+String($matchScore; "###.#")+"%"
			Else 
				$highlights:="Unable to generate analysis (model: "+$chatModel+").\nMatch score: "+String($matchScore; "###.#")+"%"
			End if 
		Else 
			If ($isFrench)
				$highlights:="Fournisseur IA non joignable (modèle : "+$chatModel+").\nScore : "+String($matchScore; "###.#")+"%"
			Else 
				$highlights:="AI provider not reachable (model: "+$chatModel+").\nMatch score: "+String($matchScore; "###.#")+"%"
			End if 
		End if 
	End if 
End if 

// Always send result back — this also stops the progress bar animation
CALL FORM($formWindow; Formula(Form._onHighlightsReceived($1)); $highlights)

KILL WORKER

