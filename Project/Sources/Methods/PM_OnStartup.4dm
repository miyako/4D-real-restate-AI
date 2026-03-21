//%attributes = {"lang":"en"}
#DECLARE($param : Integer)

Case of 
	: (Count parameters=0)
		CALL WORKER("PrimeMatch"; Current method name; 0)
	Else 
		// Second call in child process — open the dialog
		
		// Read saved language preference
		var $settings : Object
		$settings:=cs.AppUtils.me.readSettings()
		If ($settings.language#"")
			SET DATABASE LOCALIZATION($settings.language)
		End if 
		
		var $w : Integer
		$w:=Open form window("PrimeMatch"; Plain form window no title; Horizontally centered; Vertically centered; *)
		DIALOG("PrimeMatch"; *)
		
End case 