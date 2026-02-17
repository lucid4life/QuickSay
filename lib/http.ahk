; ==============================================================================
;  HTTP HELPERS — shared multipart file upload via WinHTTP COM
;  Used by QuickSay.ahk (main app) and onboarding_ui.ahk (separate process)
; ==============================================================================

; Write text into an ADODB binary stream (UTF-8, no BOM)
WriteTextToStream(targetStream, text) {
    tmp := ComObject("ADODB.Stream")
    tmp.Type := 2  ; adTypeText
    tmp.Charset := "utf-8"
    tmp.Open()
    tmp.WriteText(text)
    tmp.Position := 0
    tmp.Type := 1  ; adTypeBinary
    tmp.Position := 3  ; Skip UTF-8 BOM (EF BB BF)
    tmp.CopyTo(targetStream)
    tmp.Close()
}

; Secure multipart file upload via WinHTTP COM (for Whisper STT API)
; Returns Map with "status" (int), "body" (string), "error" (string)
HttpPostFile(url, apiKey, filePath, formFields, timeoutSec := 30) {
    result := Map("status", 0, "body", "", "error", "")

    body := ""
    fileStream := ""
    try {
        boundary := "----QuickSay" . A_TickCount

        ; Build multipart body using ADODB.Stream (handles binary file data safely)
        body := ComObject("ADODB.Stream")
        body.Type := 1  ; Binary
        body.Open()

        ; Write form fields
        for key, val in formFields {
            WriteTextToStream(body, "--" . boundary . "`r`n"
                . 'Content-Disposition: form-data; name="' . key . '"' . "`r`n`r`n"
                . val . "`r`n")
        }

        ; Write file part header
        SplitPath(filePath, &fileName)
        WriteTextToStream(body, "--" . boundary . "`r`n"
            . 'Content-Disposition: form-data; name="file"; filename="' . fileName . '"' . "`r`n"
            . "Content-Type: application/octet-stream" . "`r`n`r`n")

        ; Write file binary data
        fileStream := ComObject("ADODB.Stream")
        fileStream.Type := 1  ; Binary
        fileStream.Open()
        fileStream.LoadFromFile(filePath)
        fileStream.CopyTo(body)
        fileStream.Close()
        fileStream := ""

        ; Write closing boundary
        WriteTextToStream(body, "`r`n--" . boundary . "--`r`n")

        ; Read complete body as byte array
        body.Position := 0
        bodyData := body.Read()
        body.Close()
        body := ""

        ; Send via WinHTTP (API key never appears on command line)
        http := ComObject("WinHttp.WinHttpRequest.5.1")
        http.SetTimeouts(5000, 10000, timeoutSec * 1000, timeoutSec * 1000)
        http.Open("POST", url, false)
        http.SetRequestHeader("Authorization", "Bearer " . apiKey)
        http.SetRequestHeader("Content-Type", "multipart/form-data; boundary=" . boundary)
        http.Send(bodyData)

        result["status"] := http.Status
        ; Decode response as UTF-8 to prevent mojibake on Unicode characters
        result["body"] := Utf8Decode(http.ResponseBody)
    } catch as err {
        result["error"] := err.Message
        ; Close ADODB.Stream objects on error
        if (fileStream != "")
            try fileStream.Close()
        if (body != "")
            try body.Close()
    }

    return result
}

; Decode raw response bytes as UTF-8 (WinHTTP ResponseText can use wrong codepage)
Utf8Decode(responseBody) {
    stream := ComObject("ADODB.Stream")
    stream.Type := 1  ; adTypeBinary
    stream.Open()
    stream.Write(responseBody)
    stream.Position := 0
    stream.Type := 2  ; adTypeText
    stream.Charset := "utf-8"
    text := stream.ReadText()
    stream.Close()
    return text
}
