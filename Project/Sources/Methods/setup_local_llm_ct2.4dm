//%attributes = {"invisible":true}
var $CTranslate2 : cs.CTranslate2.CTranslate2

var $homeFolder : 4D.Folder
$homeFolder:=Folder(fk home folder).folder(".CTranslate2")
var $file : 4D.File
var $URL : Text
var $port : Integer

var $event : cs.event.event
$event:=cs.event.event.new()

/*
Function onError($params : Object; $error : cs.event.error)
Function onSuccess($params : Object; $models : cs.event.models)
Function onData($request : 4D.HTTPRequest; $event : Object)
Function onResponse($request : 4D.HTTPRequest; $event : Object)
Function onTerminate($worker : 4D.SystemWorker; $params : Object)
*/

$event.onError:=Formula(ALERT($2.message))
$event.onSuccess:=Formula(ALERT($2.models.extract("name").join(",")+" loaded!"))
$event.onData:=Formula(LOG EVENT(Into 4D debug message; This.file.fullName+":"+String((This.range.end/This.range.length)*100; "###.00%")))
$event.onResponse:=Formula(LOG EVENT(Into 4D debug message; This.file.fullName+":download complete"))
$event.onTerminate:=Formula(LOG EVENT(Into 4D debug message; (["process"; $1.pid; "terminated!"].join(" "))))

$port:=8081

var $options : Object
$options:={}
var $huggingfaces : cs.event.huggingfaces

var $folder : 4D.Folder
var $path : Text
$folder:=$homeFolder.folder("e5-base-v2")
$path:="e5-base-v2-ct2-int8"
$URL:="keisuke-miyako/e5-base-v2-ct2-int8"
var $embeddings : cs.event.huggingface
$embeddings:=cs.event.huggingface.new($folder; $URL; $path; "embedding")

$huggingfaces:=cs.event.huggingfaces.new([$embeddings])
$options:={}

$CTranslate2:=cs.CTranslate2.CTranslate2.new($port; $huggingfaces; $homeFolder; $options; $event)