## Low-level FFI bindings for Ghostscript API
##
## This module provides direct bindings to the Ghostscript C API (iapi.h).
## For most use cases, prefer the high-level wrapper in the main ghostscript module.

when defined(windows):
  const GhostscriptLib* = "gsdll64.dll"
elif defined(macosx):
  const GhostscriptLib* = "libgs.dylib"
  {.passL: "-lgs".}
else:
  const GhostscriptLib* = "libgs.so"
  {.passL: "-lgs".}

type
  GsInstance* = pointer
  GsMemory* = pointer
  GpFile* = pointer

  GsapiRevision* {.bycopy.} = object
    product*: cstring
    copyright*: cstring
    revision*: clong
    revisiondate*: clong

  GsSetParamType* {.size: sizeof(cint).} = enum
    gsParamInvalid = -1
    gsParamNull = 0
    gsParamBool = 1
    gsParamInt = 2
    gsParamFloat = 3
    gsParamName = 4
    gsParamString = 5
    gsParamLong = 6
    gsParamI64 = 7
    gsParamSizeT = 8
    gsParamParsed = 9

  GsArgEncoding* {.size: sizeof(cint).} = enum
    gsArgEncodingLocal = 0
    gsArgEncodingUtf8 = 1
    gsArgEncodingUtf16LE = 2

  GsPermitFileType* {.size: sizeof(cint).} = enum
    gsPermitFileReading = 0
    gsPermitFileWriting = 1
    gsPermitFileControl = 2

  GsErrorCode* {.size: sizeof(cint).} = enum
    gsErrorInfo = -110
    gsErrorNeedFile = -107
    gsErrorNeedInput = -106
    gsErrorVMreclaim = -105
    gsErrorExecStackUnderflow = -104
    gsErrorRemapColor = -103
    gsErrorInterpreterExit = -102
    gsErrorQuit = -101
    gsErrorFatal = -100
    gsErrorHitDetected = -99
    gsErrorCircularReference = -32
    gsErrorPdfStackOverflow = -31
    gsErrorInvalidId = -30
    gsErrorInvalidContext = -29
    gsErrorUnregistered = -28
    gsErrorUndefinedResource = -27
    gsErrorConfigurationError = -26
    gsErrorVMerror = -25
    gsErrorUnmatchedMark = -24
    gsErrorUndefinedResult = -23
    gsErrorUndefinedFilename = -22
    gsErrorUndefined = -21
    gsErrorTypecheck = -20
    gsErrorTimeout = -19
    gsErrorSyntaxError = -18
    gsErrorStackUnderflow = -17
    gsErrorStackOverflow = -16
    gsErrorRangecheck = -15
    gsErrorNoCurrentPoint = -14
    gsErrorLimitcheck = -13
    gsErrorIOError = -12
    gsErrorInvalidRestore = -11
    gsErrorInvalidFont = -10
    gsErrorInvalidFileAccess = -9
    gsErrorInvalidExit = -8
    gsErrorInvalidAccess = -7
    gsErrorInterrupt = -6
    gsErrorExecStackOverflow = -5
    gsErrorDictStackUnderflow = -4
    gsErrorDictStackOverflow = -3
    gsErrorDictFull = -2
    gsErrorUnknownError = -1
    gsErrorOk = 0

  GsError* = object of CatchableError
    code*: GsErrorCode

  StdinCallback* = proc(callerHandle: pointer, buf: cstring, len: cint): cint {.cdecl.}
  StdoutCallback* = proc(callerHandle: pointer, str: cstring, len: cint): cint {.cdecl.}
  StderrCallback* = proc(callerHandle: pointer, str: cstring, len: cint): cint {.cdecl.}
  PollCallback* = proc(callerHandle: pointer): cint {.cdecl.}

  GsCallout* = proc(
    instance: pointer,
    calloutHandle: pointer,
    deviceName: cstring,
    id: cint,
    size: cint,
    data: pointer,
  ): cint {.cdecl.}

const gsParamMoreToCome* = 0x80000000'i32

# Core API functions
proc gsapi_revision*(
  pr: ptr GsapiRevision, len: cint
): cint {.cdecl, importc, dynlib: GhostscriptLib.}

proc gsapi_new_instance*(
  pinstance: ptr GsInstance, callerHandle: pointer
): cint {.cdecl, importc, dynlib: GhostscriptLib.}

proc gsapi_delete_instance*(
  instance: GsInstance
) {.cdecl, importc, dynlib: GhostscriptLib.}

# Stdio callbacks
proc gsapi_set_stdio*(
  instance: GsInstance,
  stdinFn: StdinCallback,
  stdoutFn: StdoutCallback,
  stderrFn: StderrCallback,
): cint {.cdecl, importc, dynlib: GhostscriptLib.}

proc gsapi_set_stdio_with_handle*(
  instance: GsInstance,
  stdinFn: StdinCallback,
  stdoutFn: StdoutCallback,
  stderrFn: StderrCallback,
  callerHandle: pointer,
): cint {.cdecl, importc, dynlib: GhostscriptLib.}

# Poll callback
proc gsapi_set_poll*(
  instance: GsInstance, pollFn: PollCallback
): cint {.cdecl, importc, dynlib: GhostscriptLib.}

proc gsapi_set_poll_with_handle*(
  instance: GsInstance, pollFn: PollCallback, callerHandle: pointer
): cint {.cdecl, importc, dynlib: GhostscriptLib.}

# Callout registration
proc gsapi_register_callout*(
  instance: GsInstance, callout: GsCallout, calloutHandle: pointer
): cint {.cdecl, importc, dynlib: GhostscriptLib.}

proc gsapi_deregister_callout*(
  instance: GsInstance, callout: GsCallout, calloutHandle: pointer
) {.cdecl, importc, dynlib: GhostscriptLib.}

# Device list
proc gsapi_set_default_device_list*(
  instance: GsInstance, list: cstring, listlen: cint
): cint {.cdecl, importc, dynlib: GhostscriptLib.}

proc gsapi_get_default_device_list*(
  instance: GsInstance, list: ptr cstring, listlen: ptr cint
): cint {.cdecl, importc, dynlib: GhostscriptLib.}

# Argument encoding
proc gsapi_set_arg_encoding*(
  instance: GsInstance, encoding: cint
): cint {.cdecl, importc, dynlib: GhostscriptLib.}

# Initialization and execution
proc gsapi_init_with_args*(
  instance: GsInstance, argc: cint, argv: cstringArray
): cint {.cdecl, importc, dynlib: GhostscriptLib.}

proc gsapi_run_string_begin*(
  instance: GsInstance, userErrors: cint, pexitCode: ptr cint
): cint {.cdecl, importc, dynlib: GhostscriptLib.}

proc gsapi_run_string_continue*(
  instance: GsInstance,
  str: cstring,
  length: cuint,
  userErrors: cint,
  pexitCode: ptr cint,
): cint {.cdecl, importc, dynlib: GhostscriptLib.}

proc gsapi_run_string_end*(
  instance: GsInstance, userErrors: cint, pexitCode: ptr cint
): cint {.cdecl, importc, dynlib: GhostscriptLib.}

proc gsapi_run_string_with_length*(
  instance: GsInstance,
  str: cstring,
  length: cuint,
  userErrors: cint,
  pexitCode: ptr cint,
): cint {.cdecl, importc, dynlib: GhostscriptLib.}

proc gsapi_run_string*(
  instance: GsInstance, str: cstring, userErrors: cint, pexitCode: ptr cint
): cint {.cdecl, importc, dynlib: GhostscriptLib.}

proc gsapi_run_file*(
  instance: GsInstance, fileName: cstring, userErrors: cint, pexitCode: ptr cint
): cint {.cdecl, importc, dynlib: GhostscriptLib.}

proc gsapi_exit*(instance: GsInstance): cint {.cdecl, importc, dynlib: GhostscriptLib.}

# Parameter handling
proc gsapi_set_param*(
  instance: GsInstance, param: cstring, value: pointer, paramType: GsSetParamType
): cint {.cdecl, importc, dynlib: GhostscriptLib.}

proc gsapi_get_param*(
  instance: GsInstance, param: cstring, value: pointer, paramType: GsSetParamType
): cint {.cdecl, importc, dynlib: GhostscriptLib.}

proc gsapi_enumerate_params*(
  instance: GsInstance,
  iter: ptr pointer,
  key: ptr cstring,
  paramType: ptr GsSetParamType,
): cint {.cdecl, importc, dynlib: GhostscriptLib.}

# Path control
proc gsapi_add_control_path*(
  instance: GsInstance, pathType: cint, path: cstring
): cint {.cdecl, importc, dynlib: GhostscriptLib.}

proc gsapi_remove_control_path*(
  instance: GsInstance, pathType: cint, path: cstring
): cint {.cdecl, importc, dynlib: GhostscriptLib.}

proc gsapi_purge_control_paths*(
  instance: GsInstance, pathType: cint
) {.cdecl, importc, dynlib: GhostscriptLib.}

proc gsapi_activate_path_control*(
  instance: GsInstance, enable: cint
) {.cdecl, importc, dynlib: GhostscriptLib.}

proc gsapi_is_path_control_active*(
  instance: GsInstance
): cint {.cdecl, importc, dynlib: GhostscriptLib.}
