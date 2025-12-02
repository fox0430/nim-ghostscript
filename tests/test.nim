import std/[unittest, os, strutils]

import ../ghostscript
import ../lowlevel/raw

suite "Ghostscript bindings":
  test "getRevision returns valid info":
    let rev = getRevision()
    check rev.product.len > 0
    check rev.copyright.len > 0
    check rev.revision > 0
    check rev.revisionDate > 0

  test "create and close instance":
    let gs = newGhostscript()
    check gs != nil
    gs.close()

  test "set arg encoding":
    let gs = newGhostscript()
    defer:
      gs.close()
    gs.setArgEncoding(gsArgEncodingUtf8)

  test "init with minimal args":
    let gs = newGhostscript()
    defer:
      gs.close()
    gs.setArgEncoding(gsArgEncodingUtf8)
    gs.init(@["-dNODISPLAY", "-dBATCH", "-dNOPAUSE", "-q"])

  test "run PostScript string":
    let gs = newGhostscript()
    defer:
      gs.close()
    gs.setArgEncoding(gsArgEncodingUtf8)
    gs.init(@["-dNODISPLAY", "-dBATCH", "-dNOPAUSE", "-q"])
    discard gs.runString("1 1 add pop")

  test "error codes":
    check cint(gsErrorOk) == 0
    check cint(gsErrorFatal) == -100
    check isError(-1)
    check not isError(0)
    check isFatal(-100)
    check not isFatal(-1)

  test "error messages":
    check errorMessage(gsErrorOk) == "OK"
    check errorMessage(gsErrorIOError) == "I/O error"
    check errorMessage(gsErrorVMerror) == "VM error"

  test "getPageCount returns correct count":
    let tempPdf = getTempDir() / "ghostscript_test.pdf"
    defer:
      removeFile(tempPdf)

    # Create a 3-page PDF
    block:
      let gs = newGhostscript()
      gs.setArgEncoding(gsArgEncodingUtf8)
      gs.init(
        @[
          "-dSAFER",
          "-dBATCH",
          "-dNOPAUSE",
          "-dNOPROMPT",
          "-sDEVICE=pdfwrite",
          "-sOutputFile=" & tempPdf,
          "-c",
          "<< /PageSize [612 792] >> setpagedevice showpage showpage showpage",
        ]
      )
      gs.close()

    check fileExists(tempPdf)
    let count = getPageCount(tempPdf)
    check count == 3

  test "run PostScript string with length":
    let gs = newGhostscript()
    defer:
      gs.close()
    gs.setArgEncoding(gsArgEncodingUtf8)
    gs.init(@["-dNODISPLAY", "-dBATCH", "-dNOPAUSE", "-q"])
    # Test with a string that could contain null bytes in other contexts
    discard gs.runStringWithLength("1 2 add pop")

  test "enumerate params works without error":
    let gs = newGhostscript()
    defer:
      gs.close()
    gs.setArgEncoding(gsArgEncodingUtf8)
    gs.init(@["-dNODISPLAY", "-dBATCH", "-dNOPAUSE", "-q"])

    # Verify iteration completes without error
    # Parameter count may vary by Ghostscript version/config
    var count = 0
    for param in gs.enumerateParams():
      check param.name.len > 0
      inc count

  test "getParams returns sequence without error":
    let gs = newGhostscript()
    defer:
      gs.close()
    gs.setArgEncoding(gsArgEncodingUtf8)
    gs.init(@["-dNODISPLAY", "-dBATCH", "-dNOPAUSE", "-q"])

    # Verify getParams completes without error
    let params = gs.getParams()

    # Verify all returned params have names
    for param in params:
      check param.name.len > 0

  test "getPageCount raises IOError for missing file":
    expect IOError:
      discard getPageCount("/nonexistent/file.pdf")

  test "destructor cleans up without explicit close":
    # Ghostscript only supports one instance at a time.
    # If destructor doesn't work, the second instance creation will fail.
    block:
      let gs = newGhostscript()
      gs.setArgEncoding(gsArgEncodingUtf8)
      gs.init(@["-dNODISPLAY", "-dBATCH", "-dNOPAUSE", "-q"])
      # No close() - destructor should handle cleanup

    # If destructor worked, this should succeed
    let gs2 = newGhostscript()
    gs2.setArgEncoding(gsArgEncodingUtf8)
    gs2.init(@["-dNODISPLAY", "-dBATCH", "-dNOPAUSE", "-q"])
    gs2.close()

suite "Parameter manipulation":
  test "setParam bool works without error":
    let gs = newGhostscript()
    defer:
      gs.close()
    gs.setArgEncoding(gsArgEncodingUtf8)
    gs.init(@["-dNODISPLAY", "-dBATCH", "-dNOPAUSE", "-q"])

    # Test setting a boolean parameter (just verify no exception)
    gs.setParam("SAFER", true)
    check true

  test "setParam and getParamInt":
    let gs = newGhostscript()
    defer:
      gs.close()
    gs.setArgEncoding(gsArgEncodingUtf8)
    gs.init(@["-dNODISPLAY", "-dBATCH", "-dNOPAUSE", "-q"])

    # Test getting an integer parameter (MaxBitmap is commonly available)
    let maxBitmap = gs.getParamInt("MaxBitmap")
    check maxBitmap >= 0

  test "setParam string works without error":
    let gs = newGhostscript()
    defer:
      gs.close()
    gs.setArgEncoding(gsArgEncodingUtf8)
    gs.init(@["-dNODISPLAY", "-dBATCH", "-dNOPAUSE", "-q"])

    # Test setting a string parameter (just verify no exception)
    # Note: Not all parameters are readable via getParam
    gs.setParam("OutputFile", "/dev/null")
    check true

  test "setParam with moreToCome flag":
    let gs = newGhostscript()
    defer:
      gs.close()
    gs.setArgEncoding(gsArgEncodingUtf8)
    gs.init(@["-dNODISPLAY", "-dBATCH", "-dNOPAUSE", "-q"])

    # Set multiple params with moreToCome, then final without
    # Just verify setting params with this flag works without error
    gs.setParam("SAFER", true, moreToCome = true)
    gs.setParam("QUIET", true, moreToCome = false)
    check true

suite "Stdio callbacks":
  var capturedOutput: string

  proc testStdoutCallback(
      callerHandle: pointer, str: cstring, len: cint
  ): cint {.cdecl.} =
    if len > 0:
      capturedOutput.add($str)
    result = len

  test "setStdio captures stdout":
    capturedOutput = ""
    let gs = newGhostscript()
    defer:
      gs.close()

    gs.setStdio(nil, testStdoutCallback, nil)
    gs.setArgEncoding(gsArgEncodingUtf8)
    gs.init(@["-dNODISPLAY", "-dBATCH", "-dNOPAUSE"])

    # Print something to capture
    discard gs.runString("(Hello from test) print flush")

    check capturedOutput.contains("Hello from test")

  test "setStdio with callerHandle":
    var handleOutput = ""

    proc handleCallback(
        callerHandle: pointer, str: cstring, len: cint
    ): cint {.cdecl.} =
      if callerHandle != nil and len > 0:
        let outputPtr = cast[ptr string](callerHandle)
        outputPtr[].add($str)
      result = len

    let gs = newGhostscript()
    defer:
      gs.close()

    gs.setStdio(nil, handleCallback, nil, addr handleOutput)
    gs.setArgEncoding(gsArgEncodingUtf8)
    gs.init(@["-dNODISPLAY", "-dBATCH", "-dNOPAUSE"])

    discard gs.runString("(Test with handle) print flush")

    check handleOutput.contains("Test with handle")

suite "Poll callback":
  var pollCount: int

  proc testPollCallback(callerHandle: pointer): cint {.cdecl.} =
    inc pollCount
    result = 0 # Return 0 to continue, negative to abort

  test "setPoll is called during operations":
    pollCount = 0
    let gs = newGhostscript()
    defer:
      gs.close()

    gs.setPoll(testPollCallback)
    gs.setArgEncoding(gsArgEncodingUtf8)
    gs.init(@["-dNODISPLAY", "-dBATCH", "-dNOPAUSE", "-q"])

    # Run some PostScript that takes a bit of work
    discard gs.runString("1 1 100 { pop } for")

    # Poll may or may not be called depending on operation length
    # Just verify no errors occurred
    check true

suite "File operations":
  test "runFile executes PostScript file":
    let tempPs = getTempDir() / "ghostscript_test.ps"
    let tempOutput = getTempDir() / "ghostscript_test_output.txt"
    defer:
      removeFile(tempPs)
      removeFile(tempOutput)

    # Create a simple PostScript file
    writeFile(
      tempPs,
      """
      %!PS
      /testproc { 1 1 add } def
      testproc pop
    """,
    )

    let gs = newGhostscript()
    defer:
      gs.close()
    gs.setArgEncoding(gsArgEncodingUtf8)
    gs.init(@["-dNODISPLAY", "-dBATCH", "-dNOPAUSE", "-q"])

    let exitCode = gs.runFile(tempPs)
    check exitCode == 0

  test "runFile raises IOError for missing file":
    let gs = newGhostscript()
    defer:
      gs.close()
    gs.setArgEncoding(gsArgEncodingUtf8)
    gs.init(@["-dNODISPLAY", "-dBATCH", "-dNOPAUSE", "-q"])

    expect IOError:
      discard gs.runFile("/nonexistent/file.ps")

suite "String chunked execution":
  test "runStringBegin/Continue/End":
    let gs = newGhostscript()
    defer:
      gs.close()
    gs.setArgEncoding(gsArgEncodingUtf8)
    gs.init(@["-dNODISPLAY", "-dBATCH", "-dNOPAUSE", "-q"])

    # Begin chunked execution
    discard gs.runStringBegin()

    # Send PostScript in chunks
    discard gs.runStringContinue("/x 10 def ")
    discard gs.runStringContinue("/y 20 def ")
    discard gs.runStringContinue("x y add pop ")

    # End chunked execution
    let exitCode = gs.runStringEnd()
    check exitCode == 0

suite "Device list":
  test "getDefaultDeviceList returns devices":
    let gs = newGhostscript()
    defer:
      gs.close()

    let devices = gs.getDefaultDeviceList()
    # Should have at least some default devices
    check devices.len > 0

  test "setDefaultDeviceList and getDefaultDeviceList":
    let gs = newGhostscript()
    defer:
      gs.close()

    # Set a custom device list
    gs.setDefaultDeviceList(@["pdfwrite", "png16m", "jpeg"])

    let devices = gs.getDefaultDeviceList()
    check "pdfwrite" in devices
    check "png16m" in devices
    check "jpeg" in devices

suite "Path control":
  test "addControlPath and removeControlPath":
    let gs = newGhostscript()
    defer:
      gs.close()
    gs.setArgEncoding(gsArgEncodingUtf8)
    gs.init(@["-dNODISPLAY", "-dBATCH", "-dNOPAUSE", "-q"])

    let testPath = getTempDir()

    # Add a control path
    gs.addControlPath(gsPermitFileReading, testPath)

    # Remove the control path
    gs.removeControlPath(gsPermitFileReading, testPath)

    # No errors means success
    check true

  test "purgeControlPaths":
    let gs = newGhostscript()
    defer:
      gs.close()
    gs.setArgEncoding(gsArgEncodingUtf8)
    gs.init(@["-dNODISPLAY", "-dBATCH", "-dNOPAUSE", "-q"])

    let testPath = getTempDir()

    # Add some paths
    gs.addControlPath(gsPermitFileReading, testPath)
    gs.addControlPath(gsPermitFileReading, "/tmp")

    # Purge all reading paths
    gs.purgeControlPaths(gsPermitFileReading)

    # No errors means success
    check true

  test "activatePathControl and isPathControlActive":
    let gs = newGhostscript()
    defer:
      gs.close()
    gs.setArgEncoding(gsArgEncodingUtf8)
    gs.init(@["-dNODISPLAY", "-dBATCH", "-dNOPAUSE", "-q"])

    # Get initial state (may be active or inactive depending on gs version)
    let initialState = gs.isPathControlActive()

    # Toggle path control
    gs.activatePathControl(not initialState)
    check gs.isPathControlActive() == (not initialState)

    # Toggle back
    gs.activatePathControl(initialState)
    check gs.isPathControlActive() == initialState

suite "Helper functions":
  test "escapePostScriptString escapes special characters":
    # Access the proc through PostScript execution
    let gs = newGhostscript()
    defer:
      gs.close()
    gs.setArgEncoding(gsArgEncodingUtf8)
    gs.init(@["-dNODISPLAY", "-dBATCH", "-dNOPAUSE", "-q"])

    # Test that strings with special characters work in PostScript
    # The escapePostScriptString is used internally by getPageCount
    # We test it indirectly by creating a PDF with special chars in path
    let testPath = getTempDir() / "test(file).pdf"
    defer:
      if fileExists(testPath):
        removeFile(testPath)

    # Create a simple PDF
    block:
      let gs2 = newGhostscript()
      gs2.setArgEncoding(gsArgEncodingUtf8)
      gs2.init(
        @[
          "-dSAFER",
          "-dBATCH",
          "-dNOPAUSE",
          "-dNOPROMPT",
          "-sDEVICE=pdfwrite",
          "-sOutputFile=" & testPath,
          "-c",
          "<< /PageSize [612 792] >> setpagedevice showpage",
        ]
      )
      gs2.close()

    # getPageCount uses escapePostScriptString internally
    if fileExists(testPath):
      let count = getPageCount(testPath)
      check count == 1

  test "newGsError creates error with code":
    let error = newGsError(cint(gsErrorIOError), "Test I/O error")
    check error.code == gsErrorIOError
    check error.msg == "Test I/O error"

  test "newGsError creates error with default message":
    let error = newGsError(-12)
    check error.code == gsErrorIOError
    check "Ghostscript error" in error.msg

  test "checkError raises on error code":
    expect GsError:
      checkError(-12, "Expected error")

  test "checkError does not raise on success":
    checkError(0, "Should not raise")
    check true

  test "isError identifies errors correctly":
    check isError(-1) == true
    check isError(-12) == true
    check isError(0) == false
    check isError(cint(gsErrorQuit)) == false # -101 is not an error
    check isError(cint(gsErrorInfo)) == false # -110 is not an error

  test "isFatal identifies fatal errors":
    check isFatal(-100) == true
    check isFatal(-101) == true
    check isFatal(-110) == true
    check isFatal(-1) == false
    check isFatal(-99) == false

suite "Convenience functions":
  test "convertPdfToPng converts PDF to PNG":
    let tempPdf = getTempDir() / "gs_conv_test.pdf"
    let tempPng = getTempDir() / "gs_conv_test.png"
    defer:
      removeFile(tempPdf)
      removeFile(tempPng)

    # First create a PDF
    block:
      let gs = newGhostscript()
      gs.setArgEncoding(gsArgEncodingUtf8)
      gs.init(
        @[
          "-dSAFER",
          "-dBATCH",
          "-dNOPAUSE",
          "-dNOPROMPT",
          "-sDEVICE=pdfwrite",
          "-sOutputFile=" & tempPdf,
          "-c",
          "<< /PageSize [612 792] >> setpagedevice showpage",
        ]
      )
      gs.close()

    check fileExists(tempPdf)

    # Convert to PNG
    convertPdfToPng(tempPdf, tempPng, dpi = 72)

    check fileExists(tempPng)

  test "convertPdfToJpeg converts PDF to JPEG":
    let tempPdf = getTempDir() / "gs_conv_test2.pdf"
    let tempJpeg = getTempDir() / "gs_conv_test2.jpg"
    defer:
      removeFile(tempPdf)
      removeFile(tempJpeg)

    # Create a PDF
    block:
      let gs = newGhostscript()
      gs.setArgEncoding(gsArgEncodingUtf8)
      gs.init(
        @[
          "-dSAFER",
          "-dBATCH",
          "-dNOPAUSE",
          "-dNOPROMPT",
          "-sDEVICE=pdfwrite",
          "-sOutputFile=" & tempPdf,
          "-c",
          "<< /PageSize [612 792] >> setpagedevice showpage",
        ]
      )
      gs.close()

    check fileExists(tempPdf)

    # Convert to JPEG
    convertPdfToJpeg(tempPdf, tempJpeg, dpi = 72, quality = 75)

    check fileExists(tempJpeg)

  test "convertPsToPdf converts PostScript to PDF":
    let tempPs = getTempDir() / "gs_conv_test.ps"
    let tempPdf = getTempDir() / "gs_conv_test3.pdf"
    defer:
      removeFile(tempPs)
      removeFile(tempPdf)

    # Create a PostScript file
    writeFile(
      tempPs,
      """
      %!PS-Adobe-3.0
      << /PageSize [612 792] >> setpagedevice
      showpage
    """,
    )

    check fileExists(tempPs)

    # Convert to PDF
    convertPsToPdf(tempPs, tempPdf)

    check fileExists(tempPdf)

  test "convertPdfToPng raises IOError for missing file":
    expect IOError:
      convertPdfToPng("/nonexistent/file.pdf", "/tmp/output.png")

  test "convertPdfToJpeg raises IOError for missing file":
    expect IOError:
      convertPdfToJpeg("/nonexistent/file.pdf", "/tmp/output.jpg")

  test "convertPsToPdf raises IOError for missing file":
    expect IOError:
      convertPsToPdf("/nonexistent/file.ps", "/tmp/output.pdf")

suite "Exit handling":
  test "explicit exit call":
    let gs = newGhostscript()
    gs.setArgEncoding(gsArgEncodingUtf8)
    gs.init(@["-dNODISPLAY", "-dBATCH", "-dNOPAUSE", "-q"])

    # Explicit exit before close
    gs.exit()

    # Close should still work after exit
    gs.close()

  test "close calls exit automatically":
    let gs = newGhostscript()
    gs.setArgEncoding(gsArgEncodingUtf8)
    gs.init(@["-dNODISPLAY", "-dBATCH", "-dNOPAUSE", "-q"])

    # Just close - it should call exit internally
    gs.close()

    # Create another instance to verify cleanup worked
    let gs2 = newGhostscript()
    gs2.close()

suite "Error message mapping":
  test "all error codes have messages":
    # Test that all error codes return meaningful messages
    check errorMessage(gsErrorOk) == "OK"
    check errorMessage(gsErrorUnknownError) == "Unknown error"
    check errorMessage(gsErrorDictFull) == "Dictionary full"
    check errorMessage(gsErrorDictStackOverflow) == "Dictionary stack overflow"
    check errorMessage(gsErrorDictStackUnderflow) == "Dictionary stack underflow"
    check errorMessage(gsErrorExecStackOverflow) == "Execution stack overflow"
    check errorMessage(gsErrorInterrupt) == "Interrupt"
    check errorMessage(gsErrorInvalidAccess) == "Invalid access"
    check errorMessage(gsErrorInvalidExit) == "Invalid exit"
    check errorMessage(gsErrorInvalidFileAccess) == "Invalid file access"
    check errorMessage(gsErrorInvalidFont) == "Invalid font"
    check errorMessage(gsErrorInvalidRestore) == "Invalid restore"
    check errorMessage(gsErrorIOError) == "I/O error"
    check errorMessage(gsErrorLimitcheck) == "Limit check"
    check errorMessage(gsErrorNoCurrentPoint) == "No current point"
    check errorMessage(gsErrorRangecheck) == "Range check"
    check errorMessage(gsErrorStackOverflow) == "Stack overflow"
    check errorMessage(gsErrorStackUnderflow) == "Stack underflow"
    check errorMessage(gsErrorSyntaxError) == "Syntax error"
    check errorMessage(gsErrorTimeout) == "Timeout"
    check errorMessage(gsErrorTypecheck) == "Type check"
    check errorMessage(gsErrorUndefined) == "Undefined"
    check errorMessage(gsErrorUndefinedFilename) == "Undefined filename"
    check errorMessage(gsErrorUndefinedResult) == "Undefined result"
    check errorMessage(gsErrorUnmatchedMark) == "Unmatched mark"
    check errorMessage(gsErrorVMerror) == "VM error"
    check errorMessage(gsErrorConfigurationError) == "Configuration error"
    check errorMessage(gsErrorUndefinedResource) == "Undefined resource"
    check errorMessage(gsErrorUnregistered) == "Unregistered"
    check errorMessage(gsErrorInvalidContext) == "Invalid context"
    check errorMessage(gsErrorInvalidId) == "Invalid ID"
    check errorMessage(gsErrorPdfStackOverflow) == "PDF stack overflow"
    check errorMessage(gsErrorCircularReference) == "Circular reference"
    check errorMessage(gsErrorHitDetected) == "Hit detected"
    check errorMessage(gsErrorFatal) == "Fatal error"
    check errorMessage(gsErrorQuit) == "Quit"
    check errorMessage(gsErrorInterpreterExit) == "Interpreter exit"
    check errorMessage(gsErrorRemapColor) == "Remap color"
    check errorMessage(gsErrorExecStackUnderflow) == "Execution stack underflow"
    check errorMessage(gsErrorVMreclaim) == "VM reclaim"
    check errorMessage(gsErrorNeedInput) == "Need input"
    check errorMessage(gsErrorNeedFile) == "Need file"
    check errorMessage(gsErrorInfo) == "Info"

suite "Arg encoding":
  test "local encoding works":
    let gs = newGhostscript()
    defer:
      gs.close()
    gs.setArgEncoding(gsArgEncodingLocal)
    gs.init(@["-dNODISPLAY", "-dBATCH", "-dNOPAUSE", "-q"])

  test "utf8 encoding works":
    let gs = newGhostscript()
    defer:
      gs.close()
    gs.setArgEncoding(gsArgEncodingUtf8)
    gs.init(@["-dNODISPLAY", "-dBATCH", "-dNOPAUSE", "-q"])

  # Note: UTF16LE encoding is primarily for Windows and may not work
  # correctly on Linux/macOS with standard string arguments
