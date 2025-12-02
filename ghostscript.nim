## Ghostscript Nim bindings
##
## High-level wrapper for the Ghostscript interpreter API.
##
## Example:
##   ```nim
##   import pkg/ghostscript
##
##   # Convert PDF to PNG
##   let gs = newGhostscript()
##   gs.init(@[
##     "-dSAFER",
##     "-dBATCH",
##     "-dNOPAUSE",
##     "-sDEVICE=png16m",
##     "-r300",
##     "-sOutputFile=output.png",
##     "input.pdf"
##   ])
##   gs.close()
##   ```

import std/[strutils, os]

import lowlevel/raw

proc escapePostScriptString(s: string): string =
  ## Escape a string for use in PostScript parenthesized strings.
  ## Escapes backslash, open paren, and close paren.
  result = newStringOfCap(s.len)
  for c in s:
    case c
    of '\\':
      result.add("\\\\")
    of '(':
      result.add("\\(")
    of ')':
      result.add("\\)")
    else:
      result.add(c)

export GsArgEncoding, GsSetParamType, GsPermitFileType, GsErrorCode, GsError
export StdinCallback, StdoutCallback, StderrCallback, PollCallback, GsCallout
export gsParamMoreToCome

type
  Revision* = object
    product*: string
    copyright*: string
    revision*: int
    revisionDate*: int

  Ghostscript* = ref object
    instance: GsInstance
    initialized: bool
    callerHandle: pointer

  OutputBuffer = object
    data: string

  ParamInfo* = object ## Information about a Ghostscript parameter.
    name*: string
    paramType*: GsSetParamType

proc `=destroy`(x: typeof(Ghostscript()[])) =
  ## Destructor to ensure resources are freed.
  ## Called automatically by GC when Ghostscript object is collected.
  ## Note: Destructors must not raise exceptions.
  if x.instance != nil:
    if x.initialized:
      # Ignore exit errors - delete_instance must always be called
      discard gsapi_exit(x.instance)
    gsapi_delete_instance(x.instance)

proc stdoutCallback(callerHandle: pointer, str: cstring, len: cint): cint {.cdecl.} =
  if callerHandle != nil and len > 0:
    let buf = cast[ptr OutputBuffer](callerHandle)
    let oldLen = buf.data.len
    buf.data.setLen(oldLen + len)
    copyMem(addr buf.data[oldLen], str, len)
  result = len

proc newGsError*(code: cint, msg: string = ""): ref GsError =
  let error = new(GsError)
  error.code = cast[GsErrorCode](code)
  if msg.len > 0:
    error.msg = msg
  else:
    error.msg = "Ghostscript error: " & $code
  result = error

proc isError*(code: cint): bool =
  code < 0 and code != cint(gsErrorQuit) and code != cint(gsErrorInfo)

proc isFatal*(code: cint): bool =
  code <= -100

proc checkError*(code: cint, msg: string = "") =
  if isError(code):
    raise newGsError(code, msg)

proc errorMessage*(code: GsErrorCode): string =
  case code
  of gsErrorOk: "OK"
  of gsErrorUnknownError: "Unknown error"
  of gsErrorDictFull: "Dictionary full"
  of gsErrorDictStackOverflow: "Dictionary stack overflow"
  of gsErrorDictStackUnderflow: "Dictionary stack underflow"
  of gsErrorExecStackOverflow: "Execution stack overflow"
  of gsErrorInterrupt: "Interrupt"
  of gsErrorInvalidAccess: "Invalid access"
  of gsErrorInvalidExit: "Invalid exit"
  of gsErrorInvalidFileAccess: "Invalid file access"
  of gsErrorInvalidFont: "Invalid font"
  of gsErrorInvalidRestore: "Invalid restore"
  of gsErrorIOError: "I/O error"
  of gsErrorLimitcheck: "Limit check"
  of gsErrorNoCurrentPoint: "No current point"
  of gsErrorRangecheck: "Range check"
  of gsErrorStackOverflow: "Stack overflow"
  of gsErrorStackUnderflow: "Stack underflow"
  of gsErrorSyntaxError: "Syntax error"
  of gsErrorTimeout: "Timeout"
  of gsErrorTypecheck: "Type check"
  of gsErrorUndefined: "Undefined"
  of gsErrorUndefinedFilename: "Undefined filename"
  of gsErrorUndefinedResult: "Undefined result"
  of gsErrorUnmatchedMark: "Unmatched mark"
  of gsErrorVMerror: "VM error"
  of gsErrorConfigurationError: "Configuration error"
  of gsErrorUndefinedResource: "Undefined resource"
  of gsErrorUnregistered: "Unregistered"
  of gsErrorInvalidContext: "Invalid context"
  of gsErrorInvalidId: "Invalid ID"
  of gsErrorPdfStackOverflow: "PDF stack overflow"
  of gsErrorCircularReference: "Circular reference"
  of gsErrorHitDetected: "Hit detected"
  of gsErrorFatal: "Fatal error"
  of gsErrorQuit: "Quit"
  of gsErrorInterpreterExit: "Interpreter exit"
  of gsErrorRemapColor: "Remap color"
  of gsErrorExecStackUnderflow: "Execution stack underflow"
  of gsErrorVMreclaim: "VM reclaim"
  of gsErrorNeedInput: "Need input"
  of gsErrorNeedFile: "Need file"
  of gsErrorInfo: "Info"

proc getRevision*(): Revision =
  ## Get Ghostscript version information.
  ## This is safe to call at any time.
  var rev: GsapiRevision
  let code = gsapi_revision(addr rev, cint(sizeof(GsapiRevision)))
  if code != 0:
    raise newGsError(code, "Failed to get revision")
  result = Revision(
    product: $rev.product,
    copyright: $rev.copyright,
    revision: int(rev.revision),
    revisionDate: int(rev.revisiondate),
  )

proc newGhostscript*(callerHandle: pointer = nil): Ghostscript =
  ## Create a new Ghostscript instance.
  ##
  ## Note: Ghostscript supports only one instance at a time on most platforms.
  ## Creating a second instance while one exists will fail.
  result = Ghostscript(callerHandle: callerHandle)
  let code = gsapi_new_instance(addr result.instance, callerHandle)
  checkError(code, "Failed to create Ghostscript instance")

proc setArgEncoding*(gs: Ghostscript, encoding: GsArgEncoding) =
  ## Set the encoding for arguments. Default is local encoding.
  ## For UTF-8, use gsArgEncodingUtf8.
  ## Must be called before init.
  let code = gsapi_set_arg_encoding(gs.instance, cint(encoding))
  checkError(code, "Failed to set argument encoding")

proc setStdio*(
    gs: Ghostscript,
    stdinFn: StdinCallback,
    stdoutFn: StdoutCallback,
    stderrFn: StderrCallback,
) =
  ## Set custom stdio callbacks.
  ## Pass nil for any callback to use the default behavior.
  ## Must be called before init.
  let code = gsapi_set_stdio(gs.instance, stdinFn, stdoutFn, stderrFn)
  checkError(code, "Failed to set stdio callbacks")

proc setStdio*(
    gs: Ghostscript,
    stdinFn: StdinCallback,
    stdoutFn: StdoutCallback,
    stderrFn: StderrCallback,
    callerHandle: pointer,
) =
  ## Set custom stdio callbacks with a caller handle.
  ## The callerHandle is passed to each callback.
  ## Pass nil for any callback to use the default behavior.
  ## Must be called before init.
  let code =
    gsapi_set_stdio_with_handle(gs.instance, stdinFn, stdoutFn, stderrFn, callerHandle)
  checkError(code, "Failed to set stdio callbacks")

proc setPoll*(gs: Ghostscript, pollFn: PollCallback) =
  ## Set a poll callback for handling interrupts.
  ## The callback is called periodically during long operations.
  ## Return a negative value from the callback to abort.
  ## Must be called before init.
  let code = gsapi_set_poll(gs.instance, pollFn)
  checkError(code, "Failed to set poll callback")

proc setPoll*(gs: Ghostscript, pollFn: PollCallback, callerHandle: pointer) =
  ## Set a poll callback with a caller handle.
  ## The callerHandle is passed to the callback.
  ## Must be called before init.
  let code = gsapi_set_poll_with_handle(gs.instance, pollFn, callerHandle)
  checkError(code, "Failed to set poll callback")

proc registerCallout*(
    gs: Ghostscript, callout: GsCallout, calloutHandle: pointer = nil
) =
  ## Register a callout handler for device-specific callbacks.
  ## Callouts allow devices to communicate with the calling application.
  ## The callout receives: instance, calloutHandle, deviceName, id, size, data.
  ## Return 0 from the callout to indicate the callout was handled.
  ## Must be called before init.
  let code = gsapi_register_callout(gs.instance, callout, calloutHandle)
  checkError(code, "Failed to register callout")

proc deregisterCallout*(
    gs: Ghostscript, callout: GsCallout, calloutHandle: pointer = nil
) =
  ## Deregister a previously registered callout handler.
  ## The callout and calloutHandle must match those used in registerCallout.
  gsapi_deregister_callout(gs.instance, callout, calloutHandle)

proc setDefaultDeviceList*(gs: Ghostscript, devices: openArray[string]) =
  ## Set the default device list (e.g., @["display", "x11", "bbox"]).
  ## Must be called after creation and before init.
  let list = devices.join(" ")
  let code = gsapi_set_default_device_list(gs.instance, list.cstring, cint(list.len))
  checkError(code, "Failed to set default device list")

proc getDefaultDeviceList*(gs: Ghostscript): seq[string] =
  ## Get the current default device list.
  var list: cstring
  var listlen: cint
  let code = gsapi_get_default_device_list(gs.instance, addr list, addr listlen)
  checkError(code, "Failed to get default device list")
  if list != nil and listlen > 0:
    let s = $list
    result = s.split(' ')

proc init*(gs: Ghostscript, args: openArray[string]) =
  ## Initialize the interpreter with command-line arguments.
  ##
  ## Common arguments:
  ## - "-dSAFER": Run in safer mode
  ## - "-dBATCH": Exit after processing
  ## - "-dNOPAUSE": Don't pause between pages
  ## - "-sDEVICE=xxx": Set output device (pdfwrite, png16m, jpeg, etc.)
  ## - "-sOutputFile=xxx": Set output filename
  ## - "-r300": Set resolution to 300 DPI
  ##
  ## Returns normally for success.
  ## Raises GsError for errors.
  # argv[0] is ignored by gsapi_init_with_args (same as C main convention)
  var fullArgs = @["gs"] & @args
  var cargs = allocCStringArray(fullArgs)
  defer:
    deallocCStringArray(cargs)

  let code = gsapi_init_with_args(gs.instance, cint(fullArgs.len), cargs)

  # gsErrorQuit and gsErrorInfo are not real errors
  if code == cint(gsErrorQuit):
    gs.initialized = false
    return
  elif code == cint(gsErrorInfo):
    gs.initialized = false
    return

  checkError(code, "Failed to initialize Ghostscript")
  gs.initialized = true

proc runString*(gs: Ghostscript, code: string, userErrors: bool = false): int =
  ## Run a PostScript string.
  ## Returns the exit code.
  var exitCode: cint
  let userErr =
    if userErrors:
      cint(1)
    else:
      cint(0)
  let result_code = gsapi_run_string(gs.instance, code.cstring, userErr, addr exitCode)
  if isFatal(result_code):
    checkError(result_code, "Fatal error running string")
  result = int(exitCode)

proc runStringWithLength*(
    gs: Ghostscript, code: string, userErrors: bool = false
): int =
  ## Run a PostScript string with explicit length.
  ## Useful for strings containing null bytes.
  ## Returns the exit code.
  var exitCode: cint
  let userErr =
    if userErrors:
      cint(1)
    else:
      cint(0)
  let result_code = gsapi_run_string_with_length(
    gs.instance, code.cstring, cuint(code.len), userErr, addr exitCode
  )
  if isFatal(result_code):
    checkError(result_code, "Fatal error running string")
  result = int(exitCode)

proc runStringBegin*(gs: Ghostscript, userErrors: bool = false): int =
  ## Begin running PostScript strings in chunks.
  ## Returns the exit code.
  var exitCode: cint
  let userErr =
    if userErrors:
      cint(1)
    else:
      cint(0)
  let code = gsapi_run_string_begin(gs.instance, userErr, addr exitCode)
  if isFatal(code):
    checkError(code, "Fatal error in run_string_begin")
  result = int(exitCode)

proc runStringContinue*(gs: Ghostscript, str: string, userErrors: bool = false): int =
  ## Continue running PostScript string.
  ## Call runStringBegin first, then runStringContinue for each chunk,
  ## then runStringEnd.
  ## Returns the exit code.
  var exitCode: cint
  let userErr =
    if userErrors:
      cint(1)
    else:
      cint(0)
  let code = gsapi_run_string_continue(
    gs.instance, str.cstring, cuint(str.len), userErr, addr exitCode
  )
  # gsErrorNeedInput is expected between chunks
  if code != cint(gsErrorNeedInput) and isFatal(code):
    checkError(code, "Fatal error in run_string_continue")
  result = int(exitCode)

proc runStringEnd*(gs: Ghostscript, userErrors: bool = false): int =
  ## End running PostScript strings in chunks.
  ## Returns the exit code.
  var exitCode: cint
  let userErr =
    if userErrors:
      cint(1)
    else:
      cint(0)
  let code = gsapi_run_string_end(gs.instance, userErr, addr exitCode)
  if isFatal(code):
    checkError(code, "Fatal error in run_string_end")
  result = int(exitCode)

proc runFile*(gs: Ghostscript, filename: string, userErrors: bool = false): int =
  ## Run a PostScript or PDF file.
  ## Returns the exit code.
  ## Raises IOError if file does not exist.
  if not fileExists(filename):
    raise newException(IOError, "File not found: " & filename)
  var exitCode: cint
  let userErr =
    if userErrors:
      cint(1)
    else:
      cint(0)
  let code = gsapi_run_file(gs.instance, filename.cstring, userErr, addr exitCode)
  if isFatal(code):
    checkError(code, "Fatal error running file: " & filename)
  result = int(exitCode)

proc setParam*(gs: Ghostscript, name: string, value: bool, moreToCome: bool = false) =
  ## Set a boolean parameter.
  ## If moreToCome is true, Ghostscript defers processing until a call without this flag.
  var v = cint(if value: 1 else: 0)
  let paramType =
    if moreToCome:
      cast[GsSetParamType](cint(gsParamBool) or gsParamMoreToCome)
    else:
      gsParamBool
  let code = gsapi_set_param(gs.instance, name.cstring, addr v, paramType)
  checkError(code, "Failed to set parameter: " & name)

proc setParam*(gs: Ghostscript, name: string, value: int, moreToCome: bool = false) =
  ## Set an integer parameter.
  ## If moreToCome is true, Ghostscript defers processing until a call without this flag.
  var v = int64(value)
  let paramType =
    if moreToCome:
      cast[GsSetParamType](cint(gsParamI64) or gsParamMoreToCome)
    else:
      gsParamI64
  let code = gsapi_set_param(gs.instance, name.cstring, addr v, paramType)
  checkError(code, "Failed to set parameter: " & name)

proc setParam*(gs: Ghostscript, name: string, value: float, moreToCome: bool = false) =
  ## Set a float parameter.
  ## If moreToCome is true, Ghostscript defers processing until a call without this flag.
  var v = cfloat(value)
  let paramType =
    if moreToCome:
      cast[GsSetParamType](cint(gsParamFloat) or gsParamMoreToCome)
    else:
      gsParamFloat
  let code = gsapi_set_param(gs.instance, name.cstring, addr v, paramType)
  checkError(code, "Failed to set parameter: " & name)

proc setParam*(gs: Ghostscript, name: string, value: string, moreToCome: bool = false) =
  ## Set a string parameter.
  ## If moreToCome is true, Ghostscript defers processing until a call without this flag.
  let paramType =
    if moreToCome:
      cast[GsSetParamType](cint(gsParamString) or gsParamMoreToCome)
    else:
      gsParamString
  let code = gsapi_set_param(gs.instance, name.cstring, value.cstring, paramType)
  checkError(code, "Failed to set parameter: " & name)

proc getParamBool*(gs: Ghostscript, name: string): bool =
  ## Get a boolean parameter.
  var v: cint
  let code = gsapi_get_param(gs.instance, name.cstring, addr v, gsParamBool)
  checkError(code, "Failed to get parameter: " & name)
  result = v != 0

proc getParamInt*(gs: Ghostscript, name: string): int =
  ## Get an integer parameter.
  var v: int64
  let code = gsapi_get_param(gs.instance, name.cstring, addr v, gsParamI64)
  checkError(code, "Failed to get parameter: " & name)
  result = int(v)

proc getParamFloat*(gs: Ghostscript, name: string): float =
  ## Get a float parameter.
  var v: cfloat
  let code = gsapi_get_param(gs.instance, name.cstring, addr v, gsParamFloat)
  checkError(code, "Failed to get parameter: " & name)
  result = float(v)

proc getParamString*(gs: Ghostscript, name: string): string =
  ## Get a string parameter.
  # First call to get required size
  let size = gsapi_get_param(gs.instance, name.cstring, nil, gsParamString)
  if size < 0:
    checkError(size, "Failed to get parameter size: " & name)
  if size == 0:
    return ""
  var buf = newString(size)
  let code = gsapi_get_param(gs.instance, name.cstring, addr buf[0], gsParamString)
  checkError(code, "Failed to get parameter: " & name)
  # Remove null terminator if present
  if buf.len > 0 and buf[^1] == '\0':
    buf.setLen(buf.len - 1)
  result = buf

iterator enumerateParams*(gs: Ghostscript): ParamInfo =
  ## Iterate over all available parameters.
  ## Yields ParamInfo containing name and type of each parameter.
  var iter: pointer = nil
  var key: cstring
  var paramType: GsSetParamType
  while true:
    let code = gsapi_enumerate_params(gs.instance, addr iter, addr key, addr paramType)
    if code != 1:
      break
    yield ParamInfo(name: $key, paramType: paramType)

proc getParams*(gs: Ghostscript): seq[ParamInfo] =
  ## Get all available parameters as a sequence.
  for param in gs.enumerateParams():
    result.add(param)

proc addControlPath*(gs: Ghostscript, pathType: GsPermitFileType, path: string) =
  ## Add a path to the permitted paths for file access control.
  let code = gsapi_add_control_path(gs.instance, cint(pathType), path.cstring)
  checkError(code, "Failed to add control path")

proc removeControlPath*(gs: Ghostscript, pathType: GsPermitFileType, path: string) =
  ## Remove a path from the permitted paths.
  let code = gsapi_remove_control_path(gs.instance, cint(pathType), path.cstring)
  checkError(code, "Failed to remove control path")

proc purgeControlPaths*(gs: Ghostscript, pathType: GsPermitFileType) =
  ## Remove all paths of the specified type from permitted paths.
  gsapi_purge_control_paths(gs.instance, cint(pathType))

proc activatePathControl*(gs: Ghostscript, enable: bool) =
  ## Enable or disable path control.
  gsapi_activate_path_control(gs.instance, cint(if enable: 1 else: 0))

proc isPathControlActive*(gs: Ghostscript): bool =
  ## Check if path control is active.
  result = gsapi_is_path_control_active(gs.instance) != 0

proc exit*(gs: Ghostscript) =
  ## Exit the interpreter.
  ## Must be called before close if init was called.
  if gs.initialized:
    let code = gsapi_exit(gs.instance)
    gs.initialized = false
    # gsErrorQuit is not an error
    if code != cint(gsErrorQuit):
      checkError(code, "Failed to exit Ghostscript")

proc close*(gs: Ghostscript) =
  ## Close and destroy the Ghostscript instance.
  ## Calls exit automatically if needed.
  if gs.instance != nil:
    if gs.initialized:
      gs.exit()
    gsapi_delete_instance(gs.instance)
    gs.instance = nil

# Convenience functions

proc convertPdfToPng*(inputFile, outputFile: string, dpi: int = 300) =
  ## Convert a PDF file to PNG image(s).
  ## If outputFile contains %d, multiple pages will be output.
  ## Raises IOError if inputFile does not exist.
  if not fileExists(inputFile):
    raise newException(IOError, "Input file not found: " & inputFile)
  let gs = newGhostscript()
  defer:
    gs.close()
  gs.setArgEncoding(gsArgEncodingUtf8)
  gs.init(
    @[
      "-dSAFER",
      "-dBATCH",
      "-dNOPAUSE",
      "-dNOPROMPT",
      "-sDEVICE=png16m",
      "-r" & $dpi,
      "-sOutputFile=" & outputFile,
      inputFile,
    ]
  )

proc convertPdfToJpeg*(
    inputFile, outputFile: string, dpi: int = 300, quality: int = 90
) =
  ## Convert a PDF file to JPEG image(s).
  ## Raises IOError if inputFile does not exist.
  if not fileExists(inputFile):
    raise newException(IOError, "Input file not found: " & inputFile)
  let gs = newGhostscript()
  defer:
    gs.close()
  gs.setArgEncoding(gsArgEncodingUtf8)
  gs.init(
    @[
      "-dSAFER",
      "-dBATCH",
      "-dNOPAUSE",
      "-dNOPROMPT",
      "-sDEVICE=jpeg",
      "-dJPEGQ=" & $quality,
      "-r" & $dpi,
      "-sOutputFile=" & outputFile,
      inputFile,
    ]
  )

proc convertPsToPdf*(inputFile, outputFile: string) =
  ## Convert a PostScript file to PDF.
  ## Raises IOError if inputFile does not exist.
  if not fileExists(inputFile):
    raise newException(IOError, "Input file not found: " & inputFile)
  let gs = newGhostscript()
  defer:
    gs.close()
  gs.setArgEncoding(gsArgEncodingUtf8)
  gs.init(
    @[
      "-dSAFER",
      "-dBATCH",
      "-dNOPAUSE",
      "-dNOPROMPT",
      "-sDEVICE=pdfwrite",
      "-sOutputFile=" & outputFile,
      inputFile,
    ]
  )

proc getPageCount*(pdfFile: string): int =
  ## Get the number of pages in a PDF file.
  ## Raises IOError if pdfFile does not exist.
  ## Raises ValueError if page count cannot be parsed (e.g., invalid PDF).
  if not fileExists(pdfFile):
    raise newException(IOError, "PDF file not found: " & pdfFile)
  var outputBuf = OutputBuffer(data: "")
  let gs = newGhostscript()
  defer:
    gs.close()

  # Set up stdout capture before init
  discard gsapi_set_stdio_with_handle(
    gs.instance,
    nil, # stdin
    stdoutCallback,
    nil, # stderr
    addr outputBuf,
  )

  gs.setArgEncoding(gsArgEncodingUtf8)
  gs.init(
    @[
      "-dSAFER",
      "-dBATCH",
      "-dNOPAUSE",
      "-dNOPROMPT",
      "-dNODISPLAY",
      "-q",
      "-c",
      "(" & escapePostScriptString(pdfFile) &
        ") (r) file runpdfbegin pdfpagecount = quit",
    ]
  )

  let output = outputBuf.data.strip()
  try:
    result = parseInt(output)
  except ValueError:
    raise newException(
      ValueError,
      "Failed to parse page count from '" & pdfFile & "': got '" & output & "'",
    )
