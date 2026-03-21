//%attributes = {"invisible":true}
var $llama : cs.llama.llama

var $homeFolder : 4D.Folder
$homeFolder:=Folder(fk home folder).folder(".GGUF")
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
//$event.onSuccess:=Formula(ALERT($2.models.extract("name").join(",")+" loaded!"))
$event.onData:=Formula(LOG EVENT(Into 4D debug message; This.file.fullName+":"+String((This.range.end/This.range.length)*100; "###.00%")))
$event.onResponse:=Formula(LOG EVENT(Into 4D debug message; This.file.fullName+":download complete"))
$event.onTerminate:=Formula(LOG EVENT(Into 4D debug message; (["process"; $1.pid; "terminated!"].join(" "))))

$port:=8080

$folder:=$homeFolder.folder("Qwen3-4B-Instruct-2507")  //where to keep the repo
$path:="Qwen3-4B-Instruct-2507-Q4_K_M.gguf"  //path to the file
$URL:="keisuke-miyako/Qwen3-4B-Instruct-2507-gguf-q4k_m"  //path to the repo

var $logFile : 4D.File
$logFile:=$folder.file("llama.log")
$folder.create()
If (Not($logFile.exists))
	$logFile.setContent(4D.Blob.new())
End if 

$batch_size:=32000
$batches:=2
$threads:=1

var $cores : Integer
$cores:=System info.cores\2

$options:={\
log_file: $logFile; \
ctx_size: $batch_size*$batches*$threads; \
batch_size: $batch_size*$batches; \
parallel: $cores; \
threads: $threads; \
threads_batch: $threads; \
threads_http: $threads; \
log_disable: False; \
n_gpu_layers: -1}

$folder:=$homeFolder.folder("Qwen3.5-0.8B")
$path:="Qwen3.5-0.8B-Q4_K_M.gguf"
$URL:="unsloth/Qwen3.5-0.8B-GGUF"
var $embeddings : cs.event.huggingface
$embeddings:=cs.event.huggingface.new($folder; $URL; $path)
$huggingfaces:=cs.event.huggingfaces.new([$embeddings])

$llama:=cs.llama.llama.new($port; $huggingfaces; $homeFolder; $options; $event)