//%attributes = {"lang":"en"}
// Method: PM_OnStartup
// Description: Called on application startup. Opens the PrimeMatch form.
//   Uses the HDI pattern: spawns a child process for the dialog,
//   keeps the application process alive so 4D stays in Application mode.

#DECLARE($param : Integer)

Case of 
	: (Count parameters:C259=0)
		// First call from On Startup (application process) — no params
		// Spawn a child process to run the dialog
		var $pid : Integer
		$pid:=New process:C317(Current method name:C684; 0; "PrimeMatch"; 0)
		// Keep the application process alive while the dialog is open.
		// This prevents 4D from switching to Design mode.
		// When "Return to Design mode" is clicked, 4D aborts the child process,
		// Process state returns < 0, the loop exits, and On Startup returns.
		While (Process state:C330($pid)>=0)
			DELAY PROCESS:C323(Current process:C322; 60)
		End while 
		
	Else 
		// Second call in child process — open the dialog
		
		// Read saved language preference
		var $settings : Object
		$settings:=cs.AppUtils.me.readSettings()
		If ($settings.language#"")
			SET DATABASE LOCALIZATION:C1104($settings.language)
		End if 
		
		var $w : Integer
		$w:=Open form window:C675("PrimeMatch"; Plain form window no title:K39:19; Horizontally centered:K39:1; Vertically centered:K39:4)
		DIALOG:C40("PrimeMatch")
		CLOSE WINDOW:C154($w)
		
End case
