require "import"
import "com.androlua.Http"
import "cjson"
import "com.androlua.LuaDialog"
import "android.widget.*"
import "android.view.*"
import "android.view.ViewGroup$LayoutParams"
import "android.graphics.Color"
import "android.content.Context"
import "android.content.DialogInterface"
import "android.content.Intent"
import "android.net.Uri"
import "android.os.*"
import "android.graphics.Typeface"
import "java.io.*"
import "android.text.method.ScrollingMovementMethod"
import "android.text.ClipboardManager"
import "android.speech.tts.TextToSpeech"
import "android.media.MediaScannerConnection"
import "android.app.Dialog"
import "android.view.Window"
import "android.app.ProgressDialog"
import "android.text.InputType"
import "java.net.URLEncoder"

local dlg, dlgOpcoes, dlgEditar, dlgEditarConteudo

local function fecharTodos()
  for _, d in ipairs({dlg, dlgOpcoes, dlgEditar, dlgEditarConteudo}) do
    if d then pcall(function() d.dismiss() end) end
  end
  dlg = nil
  dlgOpcoes = nil
  dlgEditar = nil
  dlgEditarConteudo = nil
end

local PLUGIN_NAME = "Document Creator"
local PLUGIN_AUTHOR = "Mezab Ali"
local PLUGIN_DESC = "Create and manage documents with ease."

local VERSION_URL = "https://raw.githubusercontent.com/sajid86665-lgtm/Document-creator/main/Virgin.Txt"
local UPDATE_CODE_URL = "https://raw.githubusercontent.com/sajid86665-lgtm/Document-creator/main/Main.lua"
local WHATS_NEW_URL = "https://raw.githubusercontent.com/sajid86665-lgtm/Document-creator/main/What%27s%20new"
local NOTIF_URL = "https://raw.githubusercontent.com/sajid86665-lgtm/Document-creator/main/Developer%20notifications"

local PLUGIN_DIR = "/storage/emulated/0/解说/Plugins/Document creator/"
local PLUGIN_PATH = PLUGIN_DIR .. "main.lua"
local VERSION_FILE = PLUGIN_DIR .. "version.txt"

local updateInProgress = false
local updateDialogShowing = false
local updateDlg = nil
local mainHandler = Handler(Looper.getMainLooper())
local handler = mainHandler
local loadingDialog = nil

local notifPrefs = service.getSharedPreferences("DocCreator_NotifPrefs", Context.MODE_PRIVATE)
local cachedNotifContent = nil

pcall(function()
    Http.setConnTimeout(60000)
    Http.setReadTimeout(60000)
end)

function trim(s)
    if s == nil then return "" end
    return tostring(s):gsub("^%s*(.-)%s*$", "%1")
end

function getNotifHash(content)
    if not content or content == "" then return "" end
    local hash = 5381
    for i = 1, #content do
        hash = (hash * 33 + string.byte(content, i)) % 2147483647
    end
    return tostring(hash)
end

function isNotificationUnread(content)
    if not content or content == "" then return false end
    local lastRead = notifPrefs.getString("last_read_hash", "")
    return getNotifHash(content) ~= lastRead
end

function markNotificationRead(content)
    if not content or content == "" then return end
    local editor = notifPrefs.edit()
    editor.putString("last_read_hash", getNotifHash(content))
    editor.apply()
end

function fetchNotificationContent(callback)
    if cachedNotifContent then
        callback(cachedNotifContent)
        return
    end
    local timestamp = tostring(os.time())
    Http.get(NOTIF_URL .. "?t=" .. timestamp, function(code, content)
        if code == 200 and content and trim(content) ~= "" then
            cachedNotifContent = content
            callback(content)
        else
            callback(nil)
        end
    end)
end

function updateNotifButton(btn)
    if not btn then return end
    fetchNotificationContent(function(content)
        mainHandler.post(Runnable({
            run = function()
                if content and isNotificationUnread(content) then
                    btn.setText("Developer Notifications (New)")
                    btn.setBackgroundColor(0xFFB71C1C)
                else
                    btn.setText("Developer Notifications")
                    btn.setBackgroundColor(0xFF1E1E1E)
                end
            end
        }))
    end)
end

function getCurrentVersion()
    local version = "1.0"
    local f = io.open(VERSION_FILE, "r")
    if f then
        local content = f:read("*a")
        f:close()
        local trimmed = trim(content)
        if trimmed ~= "" then version = trimmed end
    else
        local dir = File(PLUGIN_DIR)
        if not dir.exists() then dir.mkdirs() end
        local wf = io.open(VERSION_FILE, "w")
        if wf then wf:write(version) wf:close() end
    end
    return version
end

function showLoading(message)
    mainHandler.post(Runnable({
        run = function()
            if loadingDialog then pcall(function() loadingDialog.dismiss() end) end
            loadingDialog = LuaDialog(service)
            loadingDialog.setTitle("Please Wait")
            loadingDialog.setMessage(message or "Loading...")
            loadingDialog.setCancelable(false)
            loadingDialog.show()
        end
    }))
end

function hideLoading()
    mainHandler.post(Runnable({
        run = function()
            if loadingDialog then
                pcall(function() loadingDialog.dismiss() end)
                loadingDialog = nil
            end
        end
    }))
end

function showUpdateErrorDialog(title, message)
    mainHandler.post(Runnable({
        run = function()
            hideLoading()
            local errorDialog = LuaDialog(service)
            errorDialog.setTitle(title)
            errorDialog.setMessage(message)
            errorDialog.setButton("OK", function() errorDialog.dismiss() end)
            errorDialog.show()
        end
    }))
end

function dismissCurrentUpdateDialog()
    if updateDlg then
        pcall(function() updateDlg.dismiss() end)
        updateDlg = nil
    end
end

function checkUpdate(showToastIfNoUpdate)
    if updateInProgress then 
        if showToastIfNoUpdate then
            Toast.makeText(service, "Update check already in progress", Toast.LENGTH_SHORT).show()
        end
        return 
    end
    if updateDialogShowing then
        if showToastIfNoUpdate then
            Toast.makeText(service, "Update dialog already showing", Toast.LENGTH_SHORT).show()
        end
        return
    end
    
    local currentVer = getCurrentVersion()
    local timestamp = tostring(os.time())
    Http.get(VERSION_URL .. "?t=" .. timestamp, function(code, response)
        if code == 200 and response then
            local onlineVersion = trim(response):match("([%d%.]+)") or trim(response)
            if onlineVersion ~= "" and onlineVersion ~= currentVer then
                dismissCurrentUpdateDialog()
                fetchAndShowUpdate(onlineVersion)
            else
                mainHandler.post(Runnable({
                    run = function()
                        hideLoading()
                        if showToastIfNoUpdate then
                            Toast.makeText(service, "No update available. You are on latest version (" .. currentVer .. ")", Toast.LENGTH_LONG).show()
                        end
                    end
                }))
            end
        else
            mainHandler.post(Runnable({
                run = function()
                    hideLoading()
                    if showToastIfNoUpdate then
                        Toast.makeText(service, "Failed to check update. Check internet.", Toast.LENGTH_SHORT).show()
                    end
                end
            }))
        end
    end)
end

function fetchAndShowUpdate(onlineVersion)
    local currentVer = getCurrentVersion()
    local timestamp = tostring(os.time())
    
    Http.get(UPDATE_CODE_URL .. "?t=" .. timestamp, function(code2, mainCode)
        if code2 == 200 and mainCode and trim(mainCode) ~= "" then
            Http.get(WHATS_NEW_URL .. "?t=" .. timestamp, function(code3, whatsNewContent)
                local changeLogText = (code3 == 200 and whatsNewContent and trim(whatsNewContent) ~= "") and trim(whatsNewContent) or "No changelog available."
                
                mainHandler.post(Runnable({
                    run = function()
                        hideLoading()
                        
                        local changelogLines = {}
                        for line in string.gmatch(changeLogText, "([^\n]*)\n?") do
                            local trimmed = trim(line)
                            if trimmed ~= "" then table.insert(changelogLines, trimmed) end
                        end
                        if #changelogLines == 0 then
                            table.insert(changelogLines, "No changelog available.")
                        end
                        
                        local updateViews = {}
                        local updateLayout = {
                            ScrollView,
                            layout_width = "fill",
                            layout_height = "wrap_content",
                            {
                                LinearLayout,
                                orientation = "vertical",
                                padding = "20dp",
                                layout_width = "fill",
                                layout_height = "wrap",
                                {Button, id = "dismissBtn", text = "Dismiss update dialog",
                                 layout_width = "fill", layout_height = "wrap", layout_marginBottom = "15dp"},
                                {TextView, text = "A new version of the extension is available!",
                                 textSize = 15, textColor = "#333333", paddingBottom = "15dp"},
                                {LinearLayout, orientation = "horizontal", layout_width = "fill", layout_height = "wrap", paddingBottom = "10dp",
                                  {TextView, text = "Current Version: ", textSize = 14, textColor = "#666666", typeface = Typeface.DEFAULT_BOLD},
                                  {TextView, text = currentVer, textSize = 14, textColor = "#D32F2F", typeface = Typeface.DEFAULT_BOLD}},
                                {LinearLayout, orientation = "horizontal", layout_width = "fill", layout_height = "wrap", paddingBottom = "15dp",
                                  {TextView, text = "Server Version: ", textSize = 14, textColor = "#666666", typeface = Typeface.DEFAULT_BOLD},
                                  {TextView, text = onlineVersion, textSize = 14, textColor = "#2E7D32", typeface = Typeface.DEFAULT_BOLD}},
                                {TextView, text = "What's New:", textSize = 14, textColor = "#1976D2",
                                 typeface = Typeface.DEFAULT_BOLD, paddingBottom = "5dp"},
                                {LinearLayout, id = "changelogContainer", orientation = "vertical",
                                 layout_width = "fill", layout_height = "wrap", paddingBottom = "20dp"},
                                {Button, id = "updateBtn", text = "Update",
                                 layout_width = "fill", layout_height = "wrap", layout_marginTop = "10dp"}
                            }
                        }
                        
                        local updateAlertDlg = LuaDialog(service)
                        updateAlertDlg.setTitle("Update Available!")
                        updateAlertDlg.setView(loadlayout(updateLayout, updateViews))
                        
                        local container = updateViews.changelogContainer
                        if container then
                            for _, line in ipairs(changelogLines) do
                                local tv = TextView(service)
                                tv.setText(line)
                                tv.setTextSize(13)
                                tv.setTextColor(Color.parseColor("#444444"))
                                tv.setPadding(0, 4, 0, 4)
                                container.addView(tv)
                            end
                        end
                        
                        updateViews.updateBtn.setOnClickListener(function()
                            updateAlertDlg.dismiss()
                            updateDialogShowing = false
                            performUpdate(mainCode, onlineVersion)
                        end)
                        
                        updateViews.dismissBtn.setOnClickListener(function()
                            updateAlertDlg.dismiss()
                            updateDialogShowing = false
                            pcall(function() fecharTodos() end)
                        end)
                        
                        updateAlertDlg.setOnDismissListener(DialogInterface.OnDismissListener{
                            onDismiss = function(dialog) updateDialogShowing = false end
                        })
                        
                        updateDialogShowing = true
                        updateDlg = updateAlertDlg
                        updateAlertDlg.show()
                    end
                }))
            end)
        else
            mainHandler.post(Runnable({
                run = function()
                    hideLoading()
                    Toast.makeText(service, "Failed to fetch update code", Toast.LENGTH_SHORT).show()
                end
            }))
        end
    end)
end

function performUpdate(mainCode, onlineVersion)
    if not mainCode or trim(mainCode) == "" then
        showUpdateErrorDialog("Update Failed", "Main extension code is empty.")
        return
    end
    
    updateInProgress = true
    showLoading("Updating extension to v" .. onlineVersion .. "...")
    
    local function updateProcess()
        local success = false
        pcall(function()
            local dir = File(PLUGIN_DIR)
            if not dir.exists() then dir.mkdirs() end
        end)
        
        local f = io.open(PLUGIN_PATH, "w")
        if f then
            f:write(mainCode)
            f:close()
            success = true
        end
        
        if success then
            local vf = io.open(VERSION_FILE, "w")
            if vf then vf:write(onlineVersion) vf:close()
            else success = false end
        end
        
        if success then
            updateInProgress = false
            mainHandler.post(Runnable({
                run = function()
                    hideLoading()
                    local successDialog = LuaDialog(service)
                    successDialog.setTitle("Update Successful")
                    successDialog.setMessage("Extension successfully updated to version " .. onlineVersion .. ".\n\nClick OK to restart.")
                    successDialog.setButton("OK", function()
                        pcall(function() successDialog.dismiss() end)
                        pcall(function()
                            if loadingDialog then
                                loadingDialog.dismiss()
                                loadingDialog = nil
                            end
                        end)
                        dismissCurrentUpdateDialog()
                        updateDialogShowing = false
                        pcall(function() fecharTodos() end)

                        mainHandler.postDelayed(Runnable({
                            run = function()
                                local pluginFile = io.open(PLUGIN_PATH, "r")
                                if pluginFile then
                                    pluginFile:close()
                                    local func, err = loadfile(PLUGIN_PATH)
                                    if func then pcall(func)
                                    else Toast.makeText(service, "Error reloading: " .. tostring(err), Toast.LENGTH_SHORT).show() end
                                end
                            end
                        }), 400)
                    end)
                    successDialog.show()
                end
            }))
        else
            updateInProgress = false
            showUpdateErrorDialog("Update Failed", "Could not write files. Please check storage permission or path.")
        end
    end
    
    Thread(luajava.bindClass("java.lang.Runnable"){ run = updateProcess }).start()
end

local tts = TextToSpeech(service, function(status)
  if status ~= TextToSpeech.SUCCESS then tts = nil end
end)
local function falar(txt)
  if tts and txt and txt ~= "" then
    tts.speak(txt, TextToSpeech.QUEUE_FLUSH, nil, nil)
  end
end

local dir = "/storage/emulated/0/blind Tech hub/document creator/"
local f = File(dir)
if not f.exists() then f.mkdirs() end

local strings = {
  app_title          = "Document Creator",
  talk_dev           = "Talk to the developer",
  close              = "Close",
  back               = "Back",
  fill_fields        = "Fill name and content",
  invalid_name       = "Invalid name. Do not use: \\ / : * ? \" < > |",
  saved              = "Document saved successfully",
  error_save         = "Error saving document",
  viewing            = "Viewing: ",
  details            = "Details",
  edit_name          = "Edit Name",
  edit_content       = "Edit Content",
  share              = "Share",
  delete             = "Delete",
  close_options      = "Close options",
  new_name           = "New name",
  save               = "Save",
  cancel             = "Cancel",
  content_updated    = "Content updated",
  name_changed       = "Name changed",
  deleted            = "Document deleted",
  file_not_found     = "File not found",
  error_share        = "Error preparing file for sharing",
  advanced           = "Options",
  details_title      = "Document Details",
  detail_name        = "Name",
  detail_size        = "Size",
  detail_modified    = "Modified on",
  detail_path        = "Path",
  document_label     = "Document: ",
  no_docs            = "No documents found",
  check_updates      = "Check for Updates",
  dev_notifications  = "Developer Notifications",
}

local function T(k) return strings[k] or k end

local community_links = {
  {title = "Telegram Discussion Group", url = "https://t.me/blindtechhubp2s"},
  {title = "Blind Tech Hub", url = "https://t.me/blindtechhubq7c"},
  {title = "SP Tech Hub", url = "https://t.me/S_P_Tech_Hub"},
  {title = "Audio Tutorials", url = "https://t.me/+1Aazfn0FJ9oxZWE1"},
  {title = "Music Channel", url = "https://t.me/Noncopyrightbackgrounmusic"},
  {title = "WhatsApp - World of VI Community", url = "https://chat.whatsapp.com/Kb3QOapabwZGOgzzO8FZof"},
  {title = "WhatsApp - Blind Tech Hub Channel", url = "https://whatsapp.com/channel/0029VbAVDj23AzNYccK2KR3T"},
  {title = "YouTube Channel", url = "https://youtube.com/@blindtechhub-p2s"},
  {title = "Official Website", url = "https://blind-tech-hub.vercel.app/"},
  {title = "Official File Store", url = "https://drive.google.com/drive/folders/1gELqt9suCksO8SWvEZshmgbs_hrZLZHY"},
}

-- ====== BINARY FILE GENERATORS ======
local function xmlEscape(s)
  s = tostring(s or "")
  s = s:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;")
  s = s:gsub('"', "&quot;"):gsub("'", "&apos;")
  return s
end

local function pdfEscape(s)
  s = tostring(s or "")
  s = s:gsub("\\", "\\\\"):gsub("%(", "\\("):gsub("%)", "\\)")
  return s
end

local function createZip(zipPath, entries, storeFirstEntry)
  local FileOutputStream = luajava.bindClass("java.io.FileOutputStream")
  local ZipOutputStream = luajava.bindClass("java.util.zip.ZipOutputStream")
  local ZipEntry = luajava.bindClass("java.util.zip.ZipEntry")
  local String = luajava.bindClass("java.lang.String")
  
  local fos = FileOutputStream(zipPath)
  local zos = ZipOutputStream(fos)
  
  for idx, entry in ipairs(entries) do
    if idx == 1 and storeFirstEntry then zos:setLevel(0)
    else zos:setLevel(-1) end
    local ze = ZipEntry(entry.name)
    zos:putNextEntry(ze)
    local bytes = String(entry.content):getBytes("UTF-8")
    zos:write(bytes, 0, bytes.length)
    zos:closeEntry()
  end
  zos:close()
  fos:close()
end

local function createPdfFile(path, content)
  local lines = {}
  for line in (content .. "\n"):gmatch("([^\n]*)\n") do
    table.insert(lines, line)
  end
  if #lines == 0 then lines = {""} end
  
  local text = "BT\n/F1 12 Tf\n72 720 Td\n14 TL\n"
  for i, line in ipairs(lines) do
    if i > 1 then text = text .. "T*\n" end
    text = text .. "(" .. pdfEscape(line) .. ") Tj\n"
  end
  text = text .. "ET"
  
  local objs = {}
  objs[1] = "<< /Type /Catalog /Pages 2 0 R >>"
  objs[2] = "<< /Type /Pages /Kids [3 0 R] /Count 1 >>"
  objs[3] = "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>"
  objs[4] = "<< /Length " .. #text .. " >>\nstream\n" .. text .. "\nendstream"
  objs[5] = "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>"
  
  local pdf = "%PDF-1.4\n"
  local offsets = {}
  for i = 1, 5 do
    offsets[i] = #pdf
    pdf = pdf .. i .. " 0 obj\n" .. objs[i] .. "\nendobj\n"
  end
  local xrefPos = #pdf
  pdf = pdf .. "xref\n0 6\n0000000000 65535 f \n"
  for i = 1, 5 do
    pdf = pdf .. string.format("%010d 00000 n \n", offsets[i])
  end
  pdf = pdf .. "trailer\n<< /Size 6 /Root 1 0 R >>\nstartxref\n" .. xrefPos .. "\n%%EOF\n"
  
  local f = io.open(path, "w")
  if f then f:write(pdf) f:close() return true end
  return false
end

local function createDocxFile(path, content)
  local paragraphs = ""
  for line in (content .. "\n"):gmatch("([^\n]*)\n") do
    paragraphs = paragraphs .. "<w:p><w:r><w:t xml:space=\"preserve\">" .. xmlEscape(line) .. "</w:t></w:r></w:p>"
  end
  local ct = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/></Types>'
  local rels = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>'
  local doc = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body>' .. paragraphs .. '</w:body></w:document>'
  createZip(path, {
    {name = "[Content_Types].xml", content = ct},
    {name = "_rels/.rels", content = rels},
    {name = "word/document.xml", content = doc}
  })
  return true
end

local function createXlsxFile(path, content)
  local rows = ""
  local rowNum = 1
  for line in (content .. "\n"):gmatch("([^\n]*)\n") do
    local cells = ""
    local colNum = 0
    for cell in (line .. "\t"):gmatch("([^\t]*)\t") do
      local colLetter = string.char(65 + colNum)
      cells = cells .. '<c r="' .. colLetter .. rowNum .. '" t="inlineStr"><is><t xml:space="preserve">' .. xmlEscape(cell) .. '</t></is></c>'
      colNum = colNum + 1
    end
    rows = rows .. '<row r="' .. rowNum .. '">' .. cells .. '</row>'
    rowNum = rowNum + 1
  end
  local ct = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/></Types>'
  local rels = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>'
  local wb = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="Sheet1" sheetId="1" r:id="rId1"/></sheets></workbook>'
  local wbRels = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/></Relationships>'
  local sheet = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>' .. rows .. '</sheetData></worksheet>'
  createZip(path, {
    {name = "[Content_Types].xml", content = ct},
    {name = "_rels/.rels", content = rels},
    {name = "xl/workbook.xml", content = wb},
    {name = "xl/_rels/workbook.xml.rels", content = wbRels},
    {name = "xl/worksheets/sheet1.xml", content = sheet}
  })
  return true
end

local function createPptxFile(path, content)
  local firstLine = content:match("([^\n]*)") or "Slide"
  local ct = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/ppt/presentation.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.presentation.main+xml"/><Override PartName="/ppt/slides/slide1.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slide+xml"/></Types>'
  local rels = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="ppt/presentation.xml"/></Relationships>'
  local pres = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><p:presentation xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><p:sldIdLst><p:sldId id="256" r:id="rId1"/></p:sldIdLst><p:sldSz cx="9144000" cy="6858000"/></p:presentation>'
  local presRels = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide" Target="slides/slide1.xml"/></Relationships>'
  local slide = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><p:sld xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main" xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"><p:cSld><p:spTree><p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr/><p:sp><p:nvSpPr><p:cNvPr id="2" name="Title"/><p:cNvSpPr><a:spLocks noGrp="1"/></p:cNvSpPr><p:nvPr/></p:nvSpPr><p:spPr><a:xfrm><a:off x="457200" y="274638"/><a:ext cx="8229600" cy="1143000"/></a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom></p:spPr><p:txBody><a:bodyPr/><a:lstStyle/><a:p><a:r><a:rPr lang="en-US" dirty="0"/><a:t>' .. xmlEscape(firstLine) .. '</a:t></a:r></a:p></p:txBody></p:sp></p:spTree></p:cSld></p:sld>'
  createZip(path, {
    {name = "[Content_Types].xml", content = ct},
    {name = "_rels/.rels", content = rels},
    {name = "ppt/presentation.xml", content = pres},
    {name = "ppt/_rels/presentation.xml.rels", content = presRels},
    {name = "ppt/slides/slide1.xml", content = slide}
  })
  return true
end

local function createOdfFile(path, content, mimeType, bodyTag, paraTag, textTag)
  local manifest = '<?xml version="1.0" encoding="UTF-8"?><manifest:manifest xmlns:manifest="urn:oasis:names:tc:opendocument:xmlns:manifest:1.0" manifest:version="1.2"><manifest:file-entry manifest:full-path="/" manifest:version="1.2" manifest:media-type="' .. mimeType .. '"/><manifest:file-entry manifest:full-path="content.xml" manifest:media-type="text/xml"/><manifest:file-entry manifest:full-path="styles.xml" manifest:media-type="text/xml"/><manifest:file-entry manifest:full-path="meta.xml" manifest:media-type="text/xml"/></manifest:manifest>'
  local bodyContent = ""
  for line in (content .. "\n"):gmatch("([^\n]*)\n") do
    bodyContent = bodyContent .. '<' .. paraTag .. '><' .. textTag .. '>' .. xmlEscape(line) .. '</' .. textTag .. '></' .. paraTag .. '>'
  end
  local contentXml = '<?xml version="1.0" encoding="UTF-8"?><office:document-content xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0" xmlns:text="urn:oasis:names:tc:opendocument:xmlns:text:1.0" xmlns:table="urn:oasis:names:tc:opendocument:xmlns:table:1.0" xmlns:draw="urn:oasis:names:tc:opendocument:xmlns:drawing:1.0" office:version="1.2"><office:body><office:' .. bodyTag .. '>' .. bodyContent .. '</office:' .. bodyTag .. '></office:body></office:document-content>'
  local stylesXml = '<?xml version="1.0" encoding="UTF-8"?><office:document-styles xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0" office:version="1.2"><office:styles/></office:document-styles>'
  local metaXml = '<?xml version="1.0" encoding="UTF-8"?><office:document-meta xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0" xmlns:meta="urn:oasis:names:tc:opendocument:xmlns:meta:1.0" office:version="1.2"><office:meta><meta:generator>Document Creator</meta:generator></office:meta></office:document-meta>'
  createZip(path, {
    {name = "mimetype", content = mimeType},
    {name = "META-INF/manifest.xml", content = manifest},
    {name = "content.xml", content = contentXml},
    {name = "styles.xml", content = stylesXml},
    {name = "meta.xml", content = metaXml}
  }, true)
  return true
end

local function createOdtFile(path, content)
  return createOdfFile(path, content, "application/vnd.oasis.opendocument.text", "text", "text:p", "text:span")
end
local function createOdsFile(path, content)
  return createOdfFile(path, content, "application/vnd.oasis.opendocument.spreadsheet", "spreadsheet", "table:table-row", "text:span")
end
local function createOdpFile(path, content)
  return createOdfFile(path, content, "application/vnd.oasis.opendocument.presentation", "presentation", "draw:page", "text:span")
end
local function createOdgFile(path, content)
  return createOdfFile(path, content, "application/vnd.oasis.opendocument.graphics", "drawing", "draw:page", "text:span")
end
local function createOdbFile(path, content)
  return createOdfFile(path, content, "application/vnd.oasis.opendocument.database", "database", "text:p", "text:span")
end

local function saveDocumentFile(path, ext, content)
  if ext == ".pdf" then return createPdfFile(path, content)
  elseif ext == ".docx" then return createDocxFile(path, content)
  elseif ext == ".xlsx" then return createXlsxFile(path, content)
  elseif ext == ".pptx" then return createPptxFile(path, content)
  elseif ext == ".odt" then return createOdtFile(path, content)
  elseif ext == ".ods" then return createOdsFile(path, content)
  elseif ext == ".odp" then return createOdpFile(path, content)
  elseif ext == ".odg" then return createOdgFile(path, content)
  elseif ext == ".odb" then return createOdbFile(path, content)
  else
    local f = io.open(path, "w")
    if f then f:write(content) f:close() return true end
    return false
  end
end

local binaryExts = {
  [".pdf"] = true, [".docx"] = true, [".xlsx"] = true, [".pptx"] = true,
  [".odt"] = true, [".ods"] = true, [".odp"] = true, [".odg"] = true, [".odb"] = true
}

local formatList = {
  {label = "Text (.txt)", ext = ".txt", template = "Welcome to Document Creator!\n\nThis is a simple plain text document."},
  {label = "Markdown (.md)", ext = ".md", template = "# My Markdown\n\nWelcome to **Markdown**!\n\n## Features\n\n- **Bold** text\n- *Italic* text\n\n> Blockquote"},
  {label = "HTML (.html)", ext = ".html", template = "<!DOCTYPE html>\n<html>\n<head><title>Page</title></head>\n<body>\n<h1>Hello, World!</h1>\n<p>Content here.</p>\n</body>\n</html>"},
  {label = "CSS (.css)", ext = ".css", template = "body {\n    font-family: system-ui, sans-serif;\n    background: #f5f5f5;\n    color: #222;\n}"},
  {label = "JavaScript (.js)", ext = ".js", template = "function greet(name) {\n    return \"Hello, \" + name + \"!\";\n}\n\nconsole.log(greet(\"World\"));"},
  {label = "JSON (.json)", ext = ".json", template = "{\n    \"name\": \"Document Creator\",\n    \"version\": \"1.0\"\n}"},
  {label = "XML (.xml)", ext = ".xml", template = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<root>\n    <item>value</item>\n</root>"},
  {label = "CSV (.csv)", ext = ".csv", template = "id,name,email,age\n1,Alice,alice@example.com,25\n2,Bob,bob@example.com,30"},
  {label = "PHP (.php)", ext = ".php", template = "<?php\necho \"Hello, World!\\n\";\n?>"},
  {label = "Python (.py)", ext = ".py", template = "def greet(name):\n    return f\"Hello, {name}!\"\n\nprint(greet(\"World\"))"},
  {label = "Lua (.lua)", ext = ".lua", template = "-- Lua Starter\n\nlocal function greet(name)\n    return \"Hello, \" .. name .. \"!\"\nend\n\nprint(greet(\"World\"))\n\nlocal fruits = {\"Apple\", \"Banana\", \"Cherry\"}\nfor i, fruit in ipairs(fruits) do\n    print(i .. \". \" .. fruit)\nend"},
  {label = "Java (.java)", ext = ".java", template = "public class Main {\n    public static void main(String[] args) {\n        System.out.println(\"Hello, World!\");\n    }\n}"},
  {label = "C++ (.cpp)", ext = ".cpp", template = "#include <iostream>\n\nint main() {\n    std::cout << \"Hello, World!\" << std::endl;\n    return 0;\n}"},
  {label = "C (.c)", ext = ".c", template = "#include <stdio.h>\n\nint main() {\n    printf(\"Hello, World!\\n\");\n    return 0;\n}"},
  {label = "SQL (.sql)", ext = ".sql", template = "CREATE TABLE users (\n    id INTEGER PRIMARY KEY,\n    name VARCHAR(100)\n);\n\nSELECT * FROM users;"},
  {label = "YAML (.yaml)", ext = ".yaml", template = "app:\n  name: Document Creator\n  version: 1.0"},
  {label = "INI (.ini)", ext = ".ini", template = "[application]\nname=Document Creator\nversion=1.0"},
  {label = "Shell (.sh)", ext = ".sh", template = "#!/bin/bash\n\necho \"Hello, World!\""},
  {label = "Batch (.bat)", ext = ".bat", template = "@echo off\n\necho Hello, World!\n\npause"},
  {label = "Log (.log)", ext = ".log", template = "2024-01-15 10:23:45 INFO  Application started"},
  {label = "RTF (.rtf)", ext = ".rtf", template = "{\\rtf1\\ansi\\deff0\n{\\fonttbl{\\f0 Arial;}}\n\\f0\\fs24\nHello, World!\\par\n}"},
  {label = "TypeScript (.ts)", ext = ".ts", template = "interface User {\n    id: number;\n    name: string;\n}\n\nconst users: User[] = [];"},
  {label = "Kotlin (.kt)", ext = ".kt", template = "fun main() {\n    println(\"Hello, World!\")\n}"},
  {label = "Go (.go)", ext = ".go", template = "package main\n\nimport \"fmt\"\n\nfunc main() {\n    fmt.Println(\"Hello, World!\")\n}"},
  {label = "Ruby (.rb)", ext = ".rb", template = "def greet(name)\n  \"Hello, #{name}!\"\nend\n\nputs greet(\"World\")"},
  {label = "Rust (.rs)", ext = ".rs", template = "fn main() {\n    println!(\"Hello, World!\");\n}"},
  {label = "PDF (.pdf)", ext = ".pdf", template = "Document Creator PDF\n\nThis is a PDF document created by Document Creator.", binary = true},
  {label = "Word (.docx)", ext = ".docx", template = "Document Creator DOCX\n\nThis is a Word document.", binary = true},
  {label = "Excel (.xlsx)", ext = ".xlsx", template = "Name\tAge\tCity\nAlice\t25\tNew York\nBob\t30\tLondon", binary = true},
  {label = "PowerPoint (.pptx)", ext = ".pptx", template = "My Presentation\n\nFirst line becomes the slide title.", binary = true},
  {label = "OpenDocument Text (.odt)", ext = ".odt", template = "OpenDocument Text\n\nThis is an ODT file.", binary = true},
  {label = "OpenDocument Spreadsheet (.ods)", ext = ".ods", template = "Name\tAge\tCity\nAlice\t25\tNew York", binary = true},
  {label = "OpenDocument Presentation (.odp)", ext = ".odp", template = "My ODP Presentation", binary = true},
  {label = "OpenDocument Graphics (.odg)", ext = ".odg", template = "My Graphics Document", binary = true},
  {label = "OpenDocument Database (.odb)", ext = ".odb", template = "My Database", binary = true},
  {label = "Plain Text (.txt, empty)", ext = ".txt", template = ""},
}

local function isDocFile(name)
  for _, fmt in ipairs(formatList) do
    local ext = fmt.ext
    local pattern = ext:gsub("%.", "%%.") .. "$"
    if name:match(pattern) then return true end
  end
  return false
end

local function listarDocumentos()
  local arquivos = {}
  local d = File(dir)
  if d.exists() then
    local files = d.listFiles()
    if files then
      for _, fi in ipairs(luajava.astable(files)) do
        if fi.isFile() and isDocFile(fi.getName()) then
          table.insert(arquivos, fi.getName())
        end
      end
    end
  end
  table.sort(arquivos)
  return arquivos
end

local function listarDocumentosComInfo()
  local arquivos = {}
  local d = File(dir)
  if d.exists() then
    local files = d.listFiles()
    if files then
      for _, fi in ipairs(luajava.astable(files)) do
        if fi.isFile() and isDocFile(fi.getName()) then
          table.insert(arquivos, {
            name = fi.getName(),
            size = fi.length(),
            date = fi.lastModified(),
            path = fi.getAbsolutePath()
          })
        end
      end
    end
  end
  return arquivos
end

local function getStatistics()
  local stats = { total = 0, byFormat = {}, totalSize = 0 }
  local d = File(dir)
  if d.exists() then
    local files = d.listFiles()
    if files then
      for _, fi in ipairs(luajava.astable(files)) do
        if fi.isFile() and isDocFile(fi.getName()) then
          stats.total = stats.total + 1
          stats.totalSize = stats.totalSize + fi.length()
          local ext = fi.getName():match("(%.[^%.]+)$") or "unknown"
          stats.byFormat[ext] = (stats.byFormat[ext] or 0) + 1
        end
      end
    end
  end
  return stats
end

local function clearAllFiles()
  local confirmDlg = LuaDialog(service)
  confirmDlg.setTitle("Confirm Delete")
  local ids_c = {}
  confirmDlg.setView(loadlayout({
    LinearLayout, orientation="vertical", padding="16dp",
    background="#000000", layout_width="fill", layout_height="wrap_content",
    {TextView, text="Are you sure you want to delete ALL documents?\n\nThis action cannot be undone.",
      textColor="#FFFFFF", textSize="14sp", paddingBottom="15dp"},
    {LinearLayout, orientation="horizontal", layout_width="fill",
      {Button, id="btnYesClear", text="Delete All",
        background="#880000", textColor="#FFFFFF", layout_weight="1"},
      {Button, id="btnNoClear", text="Cancel",
        background="#333333", textColor="#FFFFFF", layout_weight="1"},
    },
  }, ids_c))
  
  ids_c.btnYesClear.onClick = function()
    local count = 0
    local d = File(dir)
    if d.exists() then
      local files = d.listFiles()
      if files then
        for _, fi in ipairs(luajava.astable(files)) do
          if fi.isFile() and isDocFile(fi.getName()) then
            fi.delete()
            count = count + 1
          end
        end
      end
    end
    confirmDlg.dismiss()
    Toast.makeText(service, count .. " documents deleted", Toast.LENGTH_SHORT).show()
    criarInterfacePrincipal()
  end
  
  ids_c.btnNoClear.onClick = function() confirmDlg.dismiss() end
  confirmDlg.show()
end

local function backupAllFiles()
  local arquivos = listarDocumentos()
  if #arquivos == 0 then
    Toast.makeText(service, "No documents to backup", Toast.LENGTH_SHORT).show()
    return
  end
  
  local backupDir = "/storage/emulated/0/blind Tech hub/backups/"
  local bDir = File(backupDir)
  if not bDir.exists() then bDir.mkdirs() end
  
  local zipName = "backup_" .. os.date("%Y%m%d_%H%M%S") .. ".zip"
  local zipPath = backupDir .. zipName
  
  local FileOutputStream = luajava.bindClass("java.io.FileOutputStream")
  local ZipOutputStream = luajava.bindClass("java.util.zip.ZipOutputStream")
  local ZipEntry = luajava.bindClass("java.util.zip.ZipEntry")
  local FileInputStream = luajava.bindClass("java.io.FileInputStream")
  local ByteArrayOutputStream = luajava.bindClass("java.io.ByteArrayOutputStream")
  
  local success = pcall(function()
    local fos = FileOutputStream(zipPath)
    local zos = ZipOutputStream(fos)
    for _, name in ipairs(arquivos) do
      local ze = ZipEntry(name)
      zos:putNextEntry(ze)
      local fis = FileInputStream(dir .. name)
      local data = ByteArrayOutputStream()
      local b = fis:read()
      while b ~= -1 do
        data:write(b)
        b = fis:read()
      end
      fis:close()
      local bytes = data:toByteArray()
      zos:write(bytes, 0, bytes.length)
      zos:closeEntry()
    end
    zos:close()
    fos:close()
  end)
  
  if success then
    Toast.makeText(service, "Backup created: " .. zipName, Toast.LENGTH_LONG).show()
    handler.postDelayed(Runnable({run=function()
      pcall(function()
        local intent = Intent(Intent.ACTION_VIEW)
        intent.setDataAndType(Uri.parse("file://" .. zipPath), "*/*")
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        service.startActivity(intent)
      end)
    end}), 300)
  else
    Toast.makeText(service, "Backup failed", Toast.LENGTH_SHORT).show()
  end
end

local function nomeValido(n)
  if not n or n:gsub("%s", "") == "" then return false end
  if n:find('[\\/:*?"<>|]') then return false end
  return true
end

local function isBinaryExt(ext) return binaryExts[ext] == true end

local function showRunResult(title, message)
    local resultDlg = LuaDialog(service)
    resultDlg.setTitle(title)
    local ids_rr = {}
    resultDlg.setView(loadlayout({
        LinearLayout, orientation="vertical", padding="16dp",
        background="#000000", layout_width="fill", layout_height="wrap_content",
        {ScrollView, layout_width="fill", layout_height="300dp",
          {TextView, id="tvResult", text=message, textColor="#FFFFFF",
           textSize="13sp", background="#111111", padding="10dp",
           layout_width="fill", layout_height="wrap_content"}
        },
        {Button, id="btnCloseResult", text="Close",
         layout_width="fill", background="#333333", textColor="#FFFFFF", layout_marginTop="10dp"}
    }, ids_rr))
    ids_rr.btnCloseResult.onClick = function() resultDlg.dismiss() end
    resultDlg.show()
end

-- ====== SEND FEEDBACK ======
local function createOverlayDialog(view)
    local dialog = Dialog(service)
    dialog.requestWindowFeature(Window.FEATURE_NO_TITLE)
    dialog.setContentView(view)
    local window = dialog.getWindow()
    if window then window.setType(2032) end
    return dialog
end

local function showFeedbackSuccessDialog(parentDialog)
    local layout = LinearLayout(service)
    layout.setOrientation(1)
    layout.setPadding(60, 60, 60, 60)
    layout.setGravity(Gravity.CENTER)
    local msgText = TextView(service)
    msgText.setText("Feedback sent successfully!")
    msgText.setTextSize(18)
    msgText.setTextColor(0xFF4CAF50)
    msgText.setGravity(Gravity.CENTER)
    msgText.setPadding(0, 0, 0, 40)
    layout.addView(msgText)
    local btnOk = Button(service)
    btnOk.setText("OK")
    btnOk.setBackgroundColor(0xFF2196F3)
    btnOk.setTextColor(0xFFFFFFFF)
    btnOk.setLayoutParams(LinearLayout.LayoutParams(-1, -2))
    layout.addView(btnOk)
    local successDialog = createOverlayDialog(layout)
    successDialog.show()
    btnOk.setOnClickListener(function()
        successDialog.dismiss()
        if parentDialog then parentDialog.dismiss() end
    end)
end

local function showSendFeedback()
    fecharTodos()
    local scroll = ScrollView(service)
    local layout = LinearLayout(service)
    layout.setOrientation(1)
    layout.setPadding(40, 40, 40, 40)
    layout.setBackgroundColor(0xFF000000)
    
    local title = TextView(service)
    title.setText("Send Feedback to Developer")
    title.setTextSize(20)
    title.setGravity(Gravity.CENTER)
    title.setTextColor(0xFF2196F3)
    title.setPadding(0, 0, 0, 20)
    layout.addView(title)
    
    local editName = EditText(service)
    editName.setHint("Enter Name")
    editName.setTextColor(0xFFFFFFFF)
    editName.setHintTextColor(0xFF888888)
    layout.addView(editName)
    
    local editWa = EditText(service)
    editWa.setHint("WhatsApp Number (Optional)")
    editWa.setInputType(InputType.TYPE_CLASS_PHONE)
    editWa.setTextColor(0xFFFFFFFF)
    editWa.setHintTextColor(0xFF888888)
    layout.addView(editWa)
    
    local editMsg = EditText(service)
    editMsg.setHint("Enter Feedback Message")
    editMsg.setTextColor(0xFFFFFFFF)
    editMsg.setHintTextColor(0xFF888888)
    editMsg.setMinLines(4)
    editMsg.setGravity(Gravity.TOP)
    layout.addView(editMsg)
    
    local btnSend = Button(service)
    btnSend.setText("SEND FEEDBACK")
    btnSend.setBackgroundColor(0xFF2196F3)
    btnSend.setTextColor(0xFFFFFFFF)
    local pSend = LinearLayout.LayoutParams(-1, -2)
    pSend.topMargin = 15
    btnSend.setLayoutParams(pSend)
    layout.addView(btnSend)
    
    local btnBack = Button(service)
    btnBack.setText("GO BACK")
    btnBack.setBackgroundColor(0xFFF44336)
    btnBack.setTextColor(0xFFFFFFFF)
    local pBack = LinearLayout.LayoutParams(-1, -2)
    pBack.topMargin = 10
    btnBack.setLayoutParams(pBack)
    layout.addView(btnBack)
    
    scroll.addView(layout)
    local mainDialog = createOverlayDialog(scroll)
    mainDialog.show()
    
    btnBack.setOnClickListener(function()
        mainDialog.dismiss()
        criarInterfacePrincipal()
    end)
    
    btnSend.setOnClickListener(function()
        local name = tostring(editName.getText() or "")
        local wa = tostring(editWa.getText() or "")
        local msg = tostring(editMsg.getText() or "")
        
        if msg == "" then
            Toast.makeText(service, "Please enter feedback message", Toast.LENGTH_SHORT).show()
            falar("Please enter feedback message")
            return
        end
        if #msg > 5000 then
            Toast.makeText(service, "Feedback message exceeds 5000 characters limit", Toast.LENGTH_SHORT).show()
            falar("Feedback message exceeds 5000 characters limit")
            return
        end
        
        local pd = ProgressDialog(service)
        pd.setMessage("Sending please wait...")
        pd.setCancelable(false)
        local pdWindow = pd.getWindow()
        if pdWindow then pdWindow.setType(2032) end
        pd.show()
        falar("Sending please wait")
        
        local BOT_TOKEN = "8420475618:AAFq7fOsb7IQQWzQxD_L1wcO8wrYK4YwP14"
        local CHAT_ID = "8787166303"
        local VERCEL_URL = "https://send-feedback-dusky.vercel.app/api"
        local formattedName = (name ~= "" and name or "Anonymous")
        local fullText = "New Feedback Received:\nName: " .. formattedName
        if wa ~= "" then fullText = fullText .. "\nWhatsApp: " .. wa end
        fullText = fullText .. "\nFeedback: " .. msg
        
        local encodedToken = URLEncoder.encode(BOT_TOKEN, "UTF-8")
        local encodedChatId = URLEncoder.encode(CHAT_ID, "UTF-8")
        local encodedText = URLEncoder.encode(fullText, "UTF-8")
        local postData = "bot_token=" .. encodedToken .. "&chat_id=" .. encodedChatId .. "&text=" .. encodedText
        
        Http.post(VERCEL_URL, postData, function(code, content)
            pcall(function() pd.dismiss() end)
            if tonumber(code) == 200 then
                falar("Feedback sent successfully")
                editMsg.setText("")
                showFeedbackSuccessDialog(mainDialog)
            else
                local errCode = tostring(code or "Unknown")
                falar("Failed to send. Error code " .. errCode)
                Toast.makeText(service, "Error (" .. errCode .. "): " .. tostring(content), Toast.LENGTH_LONG).show()
            end
        end)
    end)
end

-- ====== DAILY QUOTE (public API, no file needed) ======
local function showDailyQuote()
    fecharTodos()
    showLoading("Fetching quote...")
    
    Http.get("https://zenquotes.io/api/random", function(code, content)
        mainHandler.post(Runnable({
            run = function()
                hideLoading()
                local quoteText = "Could not fetch quote. Please check your internet connection."
                local authorText = ""
                
                if code == 200 and content then
                    pcall(function()
                        local data = cjson.decode(content)
                        if data and data[1] then
                            quoteText = data[1].q or quoteText
                            authorText = data[1].a or ""
                        end
                    end)
                end
                
                local fullText = '"' .. quoteText .. '"'
                if authorText ~= "" then
                    fullText = fullText .. "\n\n— " .. authorText
                end
                
                local ids_q = {}
                dlg = LuaDialog(service)
                dlg.setView(loadlayout({
                    LinearLayout, orientation="vertical", padding="20dp",
                    background="#000000", layout_width="fill", layout_height="wrap_content",
                    {TextView, text="Daily Quote", textSize="20sp",
                     textColor="#FFCC00", gravity="center", paddingBottom="15dp"},
                    {TextView, text=fullText, textColor="#FFFFFF",
                     textSize="16sp", paddingBottom="20dp"},
                    {Button, id="btnAnotherQuote", text="New Quote",
                     layout_width="fill", background="#2E7D32", textColor="#FFFFFF",
                     layout_marginBottom="6dp"},
                    {Button, id="btnCopyQuote", text="Copy Quote",
                     layout_width="fill", background="#1565C0", textColor="#FFFFFF",
                     layout_marginBottom="6dp"},
                    {Button, id="btnShareQuote", text="Share Quote",
                     layout_width="fill", background="#1565C0", textColor="#FFFFFF",
                     layout_marginBottom="6dp"},
                    {Button, id="btnBackQuote", text="Back",
                     layout_width="fill", background="#333333", textColor="#FFFFFF"},
                }, ids_q))
                dlg.setCancelable(false)
                
                ids_q.btnAnotherQuote.onClick = function()
                    dlg.dismiss()
                    showDailyQuote()
                end
                ids_q.btnCopyQuote.onClick = function()
                    pcall(function()
                        local cm = service.getSystemService(Context.CLIPBOARD_SERVICE)
                        cm.setText(fullText)
                        Toast.makeText(service, "Quote copied to clipboard", Toast.LENGTH_SHORT).show()
                    end)
                end
                ids_q.btnShareQuote.onClick = function()
                    pcall(function()
                        local intent = Intent(Intent.ACTION_SEND)
                        intent.setType("text/plain")
                        intent.putExtra(Intent.EXTRA_TEXT, fullText)
                        local chooser = Intent.createChooser(intent, "Share Quote")
                        chooser.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        service.startActivity(chooser)
                    end)
                end
                ids_q.btnBackQuote.onClick = function()
                    dlg.dismiss()
                    criarInterfacePrincipal()
                end
                dlg.show()
            end
        }))
    end)
end

-- ====== DICTIONARY LOOKUP (public API, no file needed) ======
local function lookupWord(word)
    showLoading('Looking up "' .. word .. '"...')
    local url = "https://api.dictionaryapi.dev/api/v2/entries/en/" .. word
    
    Http.get(url, function(code, content)
        mainHandler.post(Runnable({
            run = function()
                hideLoading()
                local resultText = ""
                
                if code == 200 and content then
                    pcall(function()
                        local data = cjson.decode(content)
                        if data and data[1] then
                            local entry = data[1]
                            resultText = "Word: " .. (entry.word or word) .. "\n"
                            if entry.phonetic then
                                resultText = resultText .. "Pronunciation: " .. entry.phonetic .. "\n"
                            end
                            resultText = resultText .. "\n"
                            
                            if entry.meanings then
                                for i, m in ipairs(entry.meanings) do
                                    resultText = resultText .. "[" .. (m.partOfSpeech or "?") .. "]\n"
                                    if m.definitions then
                                        for j, def in ipairs(m.definitions) do
                                            resultText = resultText .. "  " .. j .. ". " .. (def.definition or "") .. "\n"
                                            if def.example then
                                                resultText = resultText .. "     Example: " .. def.example .. "\n"
                                            end
                                        end
                                    end
                                    resultText = resultText .. "\n"
                                end
                            end
                        end
                    end)
                end
                
                if resultText == "" then
                    resultText = "Word not found: " .. word .. "\n\nPlease check the spelling and try again."
                end
                
                local ids_r = {}
                dlg = LuaDialog(service)
                dlg.setView(loadlayout({
                    LinearLayout, orientation="vertical", padding="16dp",
                    background="#000000", layout_width="fill", layout_height="fill",
                    {TextView, text="Dictionary", textSize="20sp",
                     textColor="#FFCC00", gravity="center", paddingBottom="10dp"},
                    {ScrollView, layout_width="fill", layout_height="0dp", layout_weight="1",
                      {TextView, text=resultText, textColor="#FFFFFF",
                       textSize="14sp", background="#111111", padding="12dp",
                       layout_width="fill", layout_height="wrap_content"}
                    },
                    {Button, id="btnCopyDef", text="Copy Definition",
                     layout_width="fill", background="#1565C0", textColor="#FFFFFF",
                     layout_marginTop="8dp", layout_marginBottom="6dp"},
                    {Button, id="btnAnotherWord", text="Look Up Another Word",
                     layout_width="fill", background="#2E7D32", textColor="#FFFFFF",
                     layout_marginBottom="6dp"},
                    {Button, id="btnBackDef", text="Back",
                     layout_width="fill", background="#333333", textColor="#FFFFFF"},
                }, ids_r))
                dlg.setCancelable(false)
                
                ids_r.btnCopyDef.onClick = function()
                    pcall(function()
                        local cm = service.getSystemService(Context.CLIPBOARD_SERVICE)
                        cm.setText(resultText)
                        Toast.makeText(service, "Copied to clipboard", Toast.LENGTH_SHORT).show()
                    end)
                end
                ids_r.btnAnotherWord.onClick = function()
                    dlg.dismiss()
                    showDictionary()
                end
                ids_r.btnBackDef.onClick = function()
                    dlg.dismiss()
                    criarInterfacePrincipal()
                end
                dlg.show()
            end
        }))
    end)
end

local function showDictionary()
    fecharTodos()
    local ids_d = {}
    dlg = LuaDialog(service)
    dlg.setView(loadlayout({
        LinearLayout, orientation="vertical", padding="16dp",
        background="#000000", layout_width="fill", layout_height="wrap_content",
        {TextView, text="Dictionary Lookup", textSize="20sp",
         textColor="#FFCC00", gravity="center", paddingBottom="12dp"},
        {TextView, text="Enter any English word to see its meaning, pronunciation, and examples.",
         textColor="#AAAAAA", textSize="13sp", paddingBottom="12dp"},
        {EditText, id="etWord", hint="Enter a word",
         textColor="#FFFFFF", background="#222222",
         layout_width="fill", layout_height="wrap_content",
         inputType="text"},
        {Button, id="btnLookup", text="Look Up",
         layout_width="fill", background="#1565C0", textColor="#FFFFFF",
         layout_marginTop="10dp", layout_marginBottom="6dp"},
        {Button, id="btnBackDict", text="Back",
         layout_width="fill", background="#333333", textColor="#FFFFFF"},
    }, ids_d))
    dlg.setCancelable(false)
    
    ids_d.btnLookup.onClick = function()
        local word = tostring(ids_d.etWord.getText()):gsub("^%s*(.-)%s*$", "%1")
        if word == "" then
            Toast.makeText(service, "Please enter a word", Toast.LENGTH_SHORT).show()
            return
        end
        dlg.dismiss()
        lookupWord(word)
    end
    
    ids_d.btnBackDict.onClick = function()
        dlg.dismiss()
        criarInterfacePrincipal()
    end
    dlg.show()
end

local function criarNovaFile()
  fecharTodos()
  local ids_nf = {}
  dlg = LuaDialog(service)
  dlg.setView(loadlayout({
    LinearLayout, orientation="vertical", padding="16dp",
    background="#000000", layout_width="fill", layout_height="fill",

    {TextView, text="Create New File", textSize="18sp",
      textColor="#FFCC00", gravity="center", paddingBottom="10dp"},

    {TextView, text="Choose format:", textColor="#FFFFFF", textSize="13sp", paddingBottom="4dp"},

    {Spinner, id="spFormat", layout_width="fill", background="#222222"},

    {LinearLayout, orientation="horizontal", layout_width="fill", layout_marginTop="6dp",
      {Button, id="btnTemplate", text="Insert Template",
        background="#2E7D32", textColor="#FFFFFF", layout_weight="1", textSize="14sp"},
      {Button, id="btnRun", text="Run",
        background="#1565C0", textColor="#FFFFFF", layout_weight="1", textSize="14sp"},
    },

    {EditText, id="etTitulo", hint="Enter file title",
      textColor="#FFFFFF", background="#222222",
      layout_width="fill", layout_height="wrap_content",
      inputType="text", layout_marginTop="10dp"},

    {EditText, id="etConteudoNovo", hint="Write your content",
      textColor="#FFFFFF", background="#222222",
      layout_width="fill", layout_height="0dp", layout_weight="1",
      minLines=8, gravity="top", layout_marginTop="10dp"},

    {LinearLayout, orientation="horizontal", layout_width="fill", layout_marginTop="10dp",
      {Button, id="btnCriarNovo", text="Create",
        background="#FF6600", textColor="#FFFFFF", layout_weight="1"},
      {Button, id="btnCancelNovo", text="Cancel",
        background="#333333", textColor="#FFFFFF", layout_weight="1"},
    },
  }, ids_nf))
  dlg.setCancelable(false)

  local labels = {}
  for _, fmt in ipairs(formatList) do table.insert(labels, fmt.label) end
  local adapter = ArrayAdapter(service, android.R.layout.simple_spinner_item, labels)
  adapter.setDropDownViewResource(android.R.layout.simple_spinner_dropdown_item)
  ids_nf.spFormat.setAdapter(adapter)

  ids_nf.btnTemplate.onClick = function()
    local pos = ids_nf.spFormat.getSelectedItemPosition() + 1
    local fmt = formatList[pos]
    if fmt and fmt.template and fmt.template ~= "" then
      ids_nf.etConteudoNovo.setText(fmt.template)
      Toast.makeText(service, "Template inserted for " .. fmt.label, Toast.LENGTH_SHORT).show()
    else
      Toast.makeText(service, "No template available for this format", Toast.LENGTH_SHORT).show()
    end
  end

  ids_nf.btnRun.onClick = function()
    local pos = ids_nf.spFormat.getSelectedItemPosition() + 1
    local fmt = formatList[pos] or formatList[1]
    local code = tostring(ids_nf.etConteudoNovo.getText())

    if code == "" or code:gsub("%s", "") == "" then
      Toast.makeText(service, "Content is empty. Nothing to run.", Toast.LENGTH_SHORT).show()
      return
    end

    if fmt.ext == ".lua" then
      local output = {}
      local originalPrint = print
      print = function(...)
        local args = {...}
        local parts = {}
        for i = 1, #args do parts[#parts + 1] = tostring(args[i]) end
        table.insert(output, table.concat(parts, "\t"))
      end
      local func, compileErr = load(code)
      if not func then
        print = originalPrint
        showRunResult("Lua Compile Error", "Syntax error:\n\n" .. tostring(compileErr))
        return
      end
      local ok, runtimeErr = pcall(func)
      print = originalPrint
      if ok then
        if #output == 0 then
          showRunResult("Lua Output", "(no output)\n\nCode ran successfully.")
        else
          showRunResult("Lua Output", table.concat(output, "\n"))
        end
      else
        local outText = (#output > 0) and ("Output before error:\n" .. table.concat(output, "\n") .. "\n\n") or ""
        showRunResult("Lua Runtime Error", outText .. "Error:\n" .. tostring(runtimeErr))
      end
      return
    end

    if fmt.ext == ".html" then
      local tempPath = dir .. "_preview_" .. os.time() .. ".html"
      local wf = io.open(tempPath, "w")
      if wf then wf:write(code) wf:close() end
      pcall(function()
        local intent = Intent(Intent.ACTION_VIEW)
        intent.setDataAndType(Uri.parse("file://" .. tempPath), "text/html")
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        service.startActivity(intent)
      end)
      Toast.makeText(service, "Opening HTML preview in browser", Toast.LENGTH_SHORT).show()
      return
    end

    if isBinaryExt(fmt.ext) then
      local tempPath = dir .. "_preview_" .. os.time() .. fmt.ext
      local ok = saveDocumentFile(tempPath, fmt.ext, code)
      if ok then
        pcall(function()
          local intent = Intent(Intent.ACTION_VIEW)
          intent.setDataAndType(Uri.parse("file://" .. tempPath), "*/*")
          intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
          service.startActivity(intent)
        end)
        Toast.makeText(service, "Opening " .. fmt.ext .. " preview", Toast.LENGTH_SHORT).show()
      else
        Toast.makeText(service, "Could not create preview file", Toast.LENGTH_SHORT).show()
      end
      return
    end

    local tempPath = dir .. "_preview_" .. os.time() .. fmt.ext
    local wf = io.open(tempPath, "w")
    if wf then
      wf:write(code)
      wf:close()
      showRunResult("Preview Saved", "This format (" .. fmt.ext .. ") cannot be executed inside the app.\n\nPreview file saved at:\n" .. tempPath)
    else
      Toast.makeText(service, "Could not save preview file", Toast.LENGTH_SHORT).show()
    end
  end

  ids_nf.btnCriarNovo.onClick = function()
    local pos = ids_nf.spFormat.getSelectedItemPosition() + 1
    local fmt = formatList[pos] or formatList[1]
    local n = tostring(ids_nf.etTitulo.getText()):gsub("^%s*(.-)%s*$", "%1")
    local c = tostring(ids_nf.etConteudoNovo.getText()):gsub("^%s*(.-)%s*$", "%1")

    if n == "" or c == "" then
      Toast.makeText(service, T("fill_fields"), 1).show()
      falar(T("fill_fields"))
      return
    end
    if not nomeValido(n) then
      Toast.makeText(service, T("invalid_name"), 1).show()
      falar(T("invalid_name"))
      return
    end

    local fullPath = dir .. n .. fmt.ext
    local ok, err = pcall(function()
      return saveDocumentFile(fullPath, fmt.ext, c)
    end)
    if ok then
      Toast.makeText(service, T("saved"), 1).show()
      falar(T("saved"))
      dlg.dismiss()
      criarInterfacePrincipal()
    else
      Toast.makeText(service, T("error_save")..": "..tostring(err), 1).show()
      falar(T("error_save"))
    end
  end

  ids_nf.btnCancelNovo.onClick = function()
    dlg.dismiss()
    criarInterfacePrincipal()
  end

  dlg.show()
end

local function mostrarSobre()
  fecharTodos()
  
  local aboutText = 
    "APP INFORMATION\n" ..
    "────────────────────\n" ..
    "Name: Document Creator\n" ..
    "Current Version: " .. getCurrentVersion() .. "\n" ..
    "Last Updated: " .. os.date("%d %B %Y") .. "\n\n" ..
    
    "DEVELOPER\n" ..
    "────────────────────\n" ..
    "Name: Mezab Ali\n" ..
    "Role: Plugin Developer\n" ..
    "Contact: WhatsApp +91 9118141191\n\n" ..
    
    "ABOUT THIS APP\n" ..
    "────────────────────\n" ..
    "Document Creator is a powerful file creation tool that " ..
    "supports 36+ formats including text, code, and office " ..
    "documents (PDF, DOCX, XLSX, PPTX, ODT, ODS, ODP, ODG, ODB).\n\n" ..
    "Features include:\n" ..
    "- Create files in multiple formats\n" ..
    "- Inbuilt starter templates\n" ..
    "- Run Lua and HTML code directly\n" ..
    "- Search and sort saved files\n" ..
    "- Font size control and copy\n" ..
    "- Backup all files as ZIP\n" ..
    "- Auto update system\n" ..
    "- Developer notifications\n" ..
    "- Send feedback to developer\n" ..
    "- Daily quote and dictionary lookup\n\n" ..
    
    "ABOUT UPDATES\n" ..
    "────────────────────\n" ..
    "This app uses an automatic update system. When a new " ..
    "version is available, you will be notified at startup " ..
    "and can update directly from within the app.\n\n" ..
    "You can also manually check for updates from the Menu.\n\n" ..
    
    "ABOUT DEVELOPER NOTIFICATIONS\n" ..
    "────────────────────\n" ..
    "Developer notifications let the developer send you " ..
    "important messages and links. Unread notifications " ..
    "appear with a red indicator on the menu.\n\n" ..
    
    "Thank you for using Document Creator!"
  
  local ids_ab = {}
  dlg = LuaDialog(service)
  dlg.setView(loadlayout({
    LinearLayout, orientation="vertical", padding="16dp",
    background="#000000", layout_width="fill", layout_height="fill",
    
    {TextView, text="About", textSize="22sp", textColor="#FFCC00",
     gravity="center", paddingBottom="12dp"},
    
    {ScrollView, layout_width="fill", layout_height="0dp", layout_weight="1",
      {TextView, id="tvAbout", text=aboutText,
       textColor="#FFFFFF", textSize="13sp",
       background="#111111", padding="14dp",
       layout_width="fill", layout_height="wrap_content"}
    },
    
    {Button, id="btnBackAb", text="Back",
     layout_width="fill", background="#333333", textColor="#FFFFFF",
     layout_marginTop="10dp"},
  }, ids_ab))
  dlg.setCancelable(false)
  ids_ab.btnBackAb.onClick = function()
    dlg.dismiss()
    criarInterfacePrincipal()
  end
  dlg.show()
end

local function mostrarMenu()
  fecharTodos()
  local ids_m = {}
  dlg = LuaDialog(service)
  dlg.setView(loadlayout({
    ScrollView, layout_width="fill", layout_height="wrap_content",
    {LinearLayout, orientation="vertical", padding="16dp",
     background="#000000", layout_width="fill", layout_height="wrap_content",
    
    {TextView, text="Settings & More", textSize="18sp",
      textColor="#FFCC00", gravity="center", paddingBottom="12dp"},

    {Button, id="btnSendFeedback", text="Send Feedback",
      layout_width="fill", background="#FF6600", textColor="#FFFFFF",
      layout_marginBottom="6dp"},

    {Button, id="btnDailyQuote", text="Daily Quote",
      layout_width="fill", background="#2E7D32", textColor="#FFFFFF",
      layout_marginBottom="6dp"},

    {Button, id="btnDictionary", text="Dictionary Lookup",
      layout_width="fill", background="#1565C0", textColor="#FFFFFF",
      layout_marginBottom="6dp"},

    {Button, id="btnCheckUpdate", text=T("check_updates"),
      layout_width="fill", background="#1E1E1E", textColor="#FFFFFF",
      layout_marginBottom="6dp"},

    {Button, id="btnDevNotifications", text=T("dev_notifications"),
      layout_width="fill", background="#1E1E1E", textColor="#FFFFFF",
      layout_marginBottom="6dp"},

    {Button, id="btnTalkDev", text=T("talk_dev"),
      layout_width="fill", background="#1E1E1E", textColor="#FFFFFF",
      layout_marginBottom="6dp"},

    {Button, id="btnBackup", text="Backup All Files",
      layout_width="fill", background="#1E1E1E", textColor="#FFFFFF",
      layout_marginBottom="6dp"},

    {Button, id="btnClearAll", text="Clear All Files",
      layout_width="fill", background="#880000", textColor="#FFFFFF",
      layout_marginBottom="6dp"},

    {Button, id="btnBackMore", text="Back",
      layout_width="fill", background="#333333", textColor="#FFFFFF"},
    }
  }, ids_m))
  dlg.setCancelable(false)

  updateNotifButton(ids_m.btnDevNotifications)

  ids_m.btnSendFeedback.onClick = function() showSendFeedback() end
  ids_m.btnDailyQuote.onClick = function() showDailyQuote() end
  ids_m.btnDictionary.onClick = function() showDictionary() end
  ids_m.btnCheckUpdate.onClick = function() checkUpdate(true) end
  ids_m.btnDevNotifications.onClick = function() showDeveloperNotifications() end
  ids_m.btnTalkDev.onClick = function()
    fecharTodos()
    handler.postDelayed(Runnable({run=function()
      pcall(function()
        local url = "https://wa.me/919118141191"
        local intent = Intent(Intent.ACTION_VIEW, Uri.parse(url))
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        service.startActivity(intent)
      end)
    end}), 100)
  end
  ids_m.btnBackup.onClick = function() backupAllFiles() end
  ids_m.btnClearAll.onClick = function() clearAllFiles() end
  ids_m.btnBackMore.onClick = function()
    dlg.dismiss()
    criarInterfacePrincipal()
  end

  dlg.show()
end

local function compartilhar(nome)
  local arquivo = File(dir .. nome)
  if not arquivo.exists() then
    Toast.makeText(service, T("file_not_found"), 1).show()
    return
  end
  fecharTodos()
  MediaScannerConnection.scanFile(service, {arquivo.getAbsolutePath()}, nil,
    luajava.createProxy("android.media.MediaScannerConnection$OnScanCompletedListener", {
      onScanCompleted = function(path, uri)
        if uri == nil then
          Toast.makeText(service, T("error_share"), 1).show()
          return
        end
        local intent = Intent(Intent.ACTION_SEND)
        intent.setType("*/*")
        intent.putExtra(Intent.EXTRA_STREAM, uri)
        intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        local chooser = Intent.createChooser(intent, T("share"))
        chooser.setFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        service.startActivity(chooser)
      end
    })
  )
end

local function mostrarDetalhes(nome, onBack)
  fecharTodos()
  local arquivo = File(dir .. nome)
  if not arquivo.exists() then
    Toast.makeText(service, T("file_not_found"), 1).show()
    return
  end
  local ids_det = {}
  dlg = LuaDialog(service)
  dlg.setView(loadlayout({
    LinearLayout, orientation="vertical", padding="16dp",
    background="#000000", layout_width="fill", layout_height="wrap_content",
    {TextView, text=T("details_title"), textSize="16sp", textColor="#FFCC00", gravity="center", paddingBottom="10dp"},
    {TextView, text=T("detail_name")..": "..nome, textColor="#FFFFFF", textSize="14sp", paddingBottom="4dp"},
    {TextView, text=T("detail_size")..": "..arquivo.length().." bytes", textColor="#FFFFFF", textSize="14sp", paddingBottom="4dp"},
    {TextView, text=T("detail_modified")..": "..os.date("%d/%m/%Y %H:%M:%S", math.floor(arquivo.lastModified()/1000)),
      textColor="#FFFFFF", textSize="14sp", paddingBottom="4dp"},
    {TextView, text=T("detail_path")..": "..arquivo.getAbsolutePath(), textColor="#AAAAAA", textSize="13sp", paddingBottom="8dp"},
    {Button, id="btnBackDet", text=T("back"),
      layout_width="fill", background="#333333", textColor="#FFFFFF"},
  }, ids_det))
  dlg.setCancelable(false)
  ids_det.btnBackDet.onClick = function()
    dlg.dismiss()
    if onBack then onBack() end
  end
  dlg.show()
end

local function editarNome(nome, onBack)
  fecharTodos()
  local baseName = nome:gsub("%.[^%.]+$", "")
  local ids_en = {}
  dlgEditar = LuaDialog(service)
  dlgEditar.setView(loadlayout({
    LinearLayout, orientation="vertical", padding="16dp",
    background="#000000", layout_width="fill", layout_height="wrap_content",
    {TextView, text=T("edit_name"), textSize="16sp", textColor="#FFCC00", gravity="center", paddingBottom="8dp"},
    {EditText, id="etNovoNome", text=baseName, hint=T("new_name"),
      textColor="#FFFFFF", background="#222222", layout_width="fill"},
    {LinearLayout, orientation="horizontal", layout_width="fill",
      {Button, id="btnSaveNome", text=T("save"), background="#FF6600", textColor="#FFFFFF", layout_weight="1"},
      {Button, id="btnCancelNome", text=T("cancel"), background="#333333", textColor="#FFFFFF", layout_weight="1"},
    },
  }, ids_en))
  dlgEditar.setCancelable(false)

  ids_en.btnSaveNome.onClick = function()
    local n = tostring(ids_en.etNovoNome.getText()):gsub("^%s*(.-)%s*$", "%1")
    if not nomeValido(n) then
      Toast.makeText(service, T("invalid_name"), 1).show()
      falar(T("invalid_name"))
      return
    end
    local ext = nome:match("(%.[^%.]+)$") or ".txt"
    File(dir .. nome).renameTo(File(dir .. n .. ext))
    Toast.makeText(service, T("name_changed"), 1).show()
    falar(T("name_changed"))
    dlgEditar.dismiss()
    if onBack then onBack() end
  end

  ids_en.btnCancelNome.onClick = function()
    dlgEditar.dismiss()
    if onBack then onBack() end
  end
  dlgEditar.show()
end

local function editarConteudo(nome, onBack)
  fecharTodos()
  local ext = nome:match("(%.[^%.]+)$") or ".txt"
  if isBinaryExt(ext) then
    Toast.makeText(service, "Binary formats cannot be edited as text.", Toast.LENGTH_LONG).show()
    if onBack then onBack() end
    return
  end
  
  local txt = ""
  local arq = io.open(dir .. nome)
  if arq then txt = arq:read("*a"); arq:close() end

  local ids_ec = {}
  dlgEditarConteudo = LuaDialog(service)
  dlgEditarConteudo.setView(loadlayout({
    LinearLayout, orientation="vertical", padding="10dp",
    background="#000000", layout_width="fill", layout_height="fill",
    {TextView, text=T("edit_content"), textSize="15sp", textColor="#FFCC00", gravity="center", paddingBottom="6dp"},
    {ScrollView, layout_width="fill", layout_height="0dp", layout_weight="1",
      {EditText, id="etConteudoNovo", text=txt, textColor="#FFFFFF", background="#222222",
        layout_width="fill", layout_height="wrap_content", minLines=10, gravity="top"}
    },
    {LinearLayout, orientation="horizontal", layout_width="fill",
      {Button, id="btnSaveConteudo", text=T("save"), background="#FF6600", textColor="#FFFFFF", layout_weight="1"},
      {Button, id="btnCancelConteudo", text=T("cancel"), background="#333333", textColor="#FFFFFF", layout_weight="1"},
    },
  }, ids_ec))
  dlgEditarConteudo.setCancelable(false)

  ids_ec.btnSaveConteudo.onClick = function()
    local fi = io.open(dir .. nome, "w")
    fi:write(tostring(ids_ec.etConteudoNovo.getText()))
    fi:close()
    Toast.makeText(service, T("content_updated"), 1).show()
    falar(T("content_updated"))
    dlgEditarConteudo.dismiss()
    if onBack then onBack() end
  end

  ids_ec.btnCancelConteudo.onClick = function()
    dlgEditarConteudo.dismiss()
    if onBack then onBack() end
  end
  dlgEditarConteudo.show()
end

local function criarVisualizador(nome)
  fecharTodos()
  local ext = nome:match("(%.[^%.]+)$") or ".txt"
  
  if isBinaryExt(ext) then
    local arquivo = File(dir .. nome)
    if not arquivo.exists() then
      Toast.makeText(service, T("file_not_found"), 1).show()
      return
    end
    local ids_vis = {}
    dlg = LuaDialog(service)
    dlg.setView(loadlayout({
      LinearLayout, orientation="vertical", padding="14dp",
      background="#000000", layout_width="fill", layout_height="wrap_content",
      {TextView, text=T("viewing")..nome, textSize="15sp", textColor="#FFCC00", gravity="center", paddingBottom="10dp"},
      {TextView, text="Binary format: " .. ext, textColor="#FFFFFF", textSize="14sp", paddingBottom="6dp"},
      {TextView, text="Open with an external app like Word, Excel, PowerPoint, LibreOffice, WPS Office, or Google Docs.",
        textColor="#AAAAAA", textSize="13sp", paddingBottom="12dp"},
      {Button, id="btnOpenExt", text="Open with External App",
        layout_width="fill", background="#1565C0", textColor="#FFFFFF", layout_marginBottom="6dp"},
      {Button, id="btnOpcoes", text=T("advanced"),
        layout_width="fill", background="#1E1E1E", textColor="#FFFFFF", layout_marginBottom="6dp"},
      {Button, id="btnVoltarVis", text=T("back"),
        layout_width="fill", background="#333333", textColor="#FFFFFF"},
    }, ids_vis))
    dlg.setCancelable(false)
    
    ids_vis.btnOpenExt.onClick = function()
      MediaScannerConnection.scanFile(service, {arquivo.getAbsolutePath()}, nil,
        luajava.createProxy("android.media.MediaScannerConnection$OnScanCompletedListener", {
          onScanCompleted = function(path, uri)
            if uri then
              pcall(function()
                local intent = Intent(Intent.ACTION_VIEW)
                intent.setDataAndType(uri, "*/*")
                intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                service.startActivity(intent)
              end)
            end
          end
        })
      )
    end
    
    ids_vis.btnOpcoes.onClick = function()
      local ids_op = {}
      dlgOpcoes = LuaDialog(service)
      dlgOpcoes.setView(loadlayout({
        LinearLayout, orientation="vertical", padding="14dp",
        background="#000000", layout_width="fill", layout_height="wrap_content",
        {TextView, text=T("document_label")..nome, textSize="14sp", textColor="#FFCC00", gravity="center", paddingBottom="8dp"},
        {Button, id="btnVerDet",    text=T("details"),      layout_width="fill", background="#1E1E1E", textColor="#FFFFFF"},
        {Button, id="btnEditNome",  text=T("edit_name"),    layout_width="fill", background="#1E1E1E", textColor="#FFFFFF"},
        {Button, id="btnShare",     text=T("share"),        layout_width="fill", background="#1E1E1E", textColor="#FFFFFF"},
        {Button, id="btnDelete",    text=T("delete"),       layout_width="fill", background="#880000", textColor="#FFFFFF"},
        {Button, id="btnCloseOpts", text=T("close_options"),layout_width="fill", background="#333333", textColor="#FFFFFF"},
      }, ids_op))
      dlgOpcoes.setCancelable(false)
      ids_op.btnVerDet.onClick = function() mostrarDetalhes(nome, function() criarVisualizador(nome) end) end
      ids_op.btnEditNome.onClick = function() editarNome(nome, function() criarListaDocumentos() end) end
      ids_op.btnShare.onClick = function() compartilhar(nome) end
      ids_op.btnDelete.onClick = function()
        File(dir .. nome).delete()
        Toast.makeText(service, T("deleted"), 1).show()
        dlgOpcoes.dismiss()
        criarListaDocumentos()
      end
      ids_op.btnCloseOpts.onClick = function()
        dlgOpcoes.dismiss()
        criarVisualizador(nome)
      end
      dlgOpcoes.show()
    end
    
    ids_vis.btnVoltarVis.onClick = function()
      dlg.dismiss()
      criarListaDocumentos()
    end
    dlg.show()
    return
  end
  
  local txt = ""
  local arq = io.open(dir .. nome)
  if arq then txt = arq:read("*a"); arq:close()
  else txt = T("file_not_found") end

  local ids_vis = {}
  local currentFontSize = 15
  dlg = LuaDialog(service)
  dlg.setView(loadlayout({
    LinearLayout, orientation="vertical", padding="14dp",
    background="#000000", layout_width="fill", layout_height="fill",
    {TextView, text=T("viewing")..nome, textSize="15sp", textColor="#FFCC00", gravity="center", paddingBottom="6dp"},
    
    {LinearLayout, orientation="horizontal", layout_width="fill", paddingBottom="6dp",
      {Button, id="btnFontDown", text="A-",
        background="#1E1E1E", textColor="#FFFFFF", layout_weight="1", textSize="14sp"},
      {Button, id="btnFontUp", text="A+",
        background="#1E1E1E", textColor="#FFFFFF", layout_weight="1", textSize="14sp"},
      {Button, id="btnCopy", text="Copy",
        background="#1565C0", textColor="#FFFFFF", layout_weight="1", textSize="14sp"},
      {Button, id="btnOpcoes", text=T("advanced"),
        background="#1E1E1E", textColor="#FFFFFF", layout_weight="1", textSize="14sp"},
    },
    
    {ScrollView, layout_width="fill", layout_height="0dp", layout_weight="1",
      {TextView, id="tvConteudo", text=txt, textSize="15sp",
        textColor="#FFFFFF", background="#111111", padding="10dp",
        layout_width="fill", layout_height="wrap_content"}
    },
    {Button, id="btnVoltarVis", text=T("back"),
      layout_width="fill", background="#333333", textColor="#FFFFFF"},
  }, ids_vis))
  dlg.setCancelable(false)

  ids_vis.btnFontDown.onClick = function()
    currentFontSize = math.max(10, currentFontSize - 2)
    ids_vis.tvConteudo.setTextSize(currentFontSize)
  end
  
  ids_vis.btnFontUp.onClick = function()
    currentFontSize = math.min(30, currentFontSize + 2)
    ids_vis.tvConteudo.setTextSize(currentFontSize)
  end
  
  ids_vis.btnCopy.onClick = function()
    pcall(function()
      local cm = service.getSystemService(Context.CLIPBOARD_SERVICE)
      cm.setText(txt)
      Toast.makeText(service, "Copied to clipboard", Toast.LENGTH_SHORT).show()
    end)
  end

  ids_vis.btnOpcoes.onClick = function()
    local ids_op = {}
    dlgOpcoes = LuaDialog(service)
    dlgOpcoes.setView(loadlayout({
      LinearLayout, orientation="vertical", padding="14dp",
      background="#000000", layout_width="fill", layout_height="wrap_content",
      {TextView, text=T("document_label")..nome, textSize="14sp", textColor="#FFCC00", gravity="center", paddingBottom="8dp"},
      {Button, id="btnVerDet",    text=T("details"),      layout_width="fill", background="#1E1E1E", textColor="#FFFFFF"},
      {Button, id="btnEditNome",  text=T("edit_name"),    layout_width="fill", background="#1E1E1E", textColor="#FFFFFF"},
      {Button, id="btnEditCont",  text=T("edit_content"), layout_width="fill", background="#1E1E1E", textColor="#FFFFFF"},
      {Button, id="btnShare",     text=T("share"),        layout_width="fill", background="#1E1E1E", textColor="#FFFFFF"},
      {Button, id="btnDelete",    text=T("delete"),       layout_width="fill", background="#880000", textColor="#FFFFFF"},
      {Button, id="btnCloseOpts", text=T("close_options"),layout_width="fill", background="#333333", textColor="#FFFFFF"},
    }, ids_op))
    dlgOpcoes.setCancelable(false)
    ids_op.btnVerDet.onClick = function() mostrarDetalhes(nome, function() criarVisualizador(nome) end) end
    ids_op.btnEditNome.onClick = function() editarNome(nome, function() criarListaDocumentos() end) end
    ids_op.btnEditCont.onClick = function() editarConteudo(nome, function() criarListaDocumentos() end) end
    ids_op.btnShare.onClick = function() compartilhar(nome) end
    ids_op.btnDelete.onClick = function()
      File(dir .. nome).delete()
      Toast.makeText(service, T("deleted"), 1).show()
      dlgOpcoes.dismiss()
      criarListaDocumentos()
    end
    ids_op.btnCloseOpts.onClick = function()
      dlgOpcoes.dismiss()
      criarVisualizador(nome)
    end
    dlgOpcoes.show()
  end
  
  ids_vis.btnVoltarVis.onClick = function()
    dlg.dismiss()
    criarListaDocumentos()
  end
  dlg.show()
end

local function criarListaDocumentos()
  fecharTodos()
  local ids_lst = {}
  local currentSort = "name"
  local currentSearch = ""
  
  dlg = LuaDialog(service)
  dlg.setView(loadlayout({
    LinearLayout, orientation="vertical", padding="14dp",
    background="#000000", layout_width="fill", layout_height="fill",
    {TextView, text="Recent Files", textSize="18sp", textColor="#FFCC00", gravity="center", paddingBottom="8dp"},
    
    {EditText, id="etSearch", hint="Search files...",
      textColor="#FFFFFF", background="#222222",
      layout_width="fill", layout_height="wrap_content",
      inputType="text", layout_marginBottom="6dp"},
    
    {LinearLayout, orientation="horizontal", layout_width="fill", paddingBottom="6dp",
      {Button, id="btnSortName", text="By Name",
        background="#333333", textColor="#FFFFFF", layout_weight="1", textSize="13sp"},
      {Button, id="btnSortDate", text="By Date",
        background="#1E1E1E", textColor="#FFFFFF", layout_weight="1", textSize="13sp"},
      {Button, id="btnSortSize", text="By Size",
        background="#1E1E1E", textColor="#FFFFFF", layout_weight="1", textSize="13sp"},
    },
    
    {ScrollView, layout_width="fill", layout_height="0dp", layout_weight="1",
      {LinearLayout, id="llDocs", orientation="vertical", layout_width="fill"}
    },
    {Button, id="btnVoltarLst", text=T("back"),
      layout_width="fill", background="#333333", textColor="#FFFFFF"},
  }, ids_lst))
  dlg.setCancelable(false)
  
  local function refreshList()
    local allFiles = listarDocumentosComInfo()
    local filtered = {}
    for _, f in ipairs(allFiles) do
      if currentSearch == "" or f.name:lower():find(currentSearch:lower(), 1, true) then
        table.insert(filtered, f)
      end
    end
    
    if currentSort == "name" then
      table.sort(filtered, function(a, b) return a.name < b.name end)
    elseif currentSort == "date" then
      table.sort(filtered, function(a, b) return a.date > b.date end)
    elseif currentSort == "size" then
      table.sort(filtered, function(a, b) return a.size > b.size end)
    end
    
    ids_lst.llDocs.removeAllViews()
    
    if #filtered == 0 then
      local tv = TextView(service)
      tv.setText(T("no_docs"))
      tv.setTextColor(0xFFAAAAAA)
      tv.setGravity(17)
      tv.setPadding(8, 20, 8, 20)
      ids_lst.llDocs.addView(tv)
    else
      for _, f in ipairs(filtered) do
        local b = Button(service)
        local sizeKb = math.floor(f.size / 1024)
        b.setText(f.name .. "\n(" .. sizeKb .. " KB)")
        b.setBackgroundColor(0xFF111111)
        b.setTextColor(0xFFFFFFFF)
        local n = f.name
        b.onClick = function() criarVisualizador(n) end
        ids_lst.llDocs.addView(b)
      end
    end
  end
  
  ids_lst.btnSortName.onClick = function()
    currentSort = "name"
    ids_lst.btnSortName.setBackgroundColor(0xFF1565C0)
    ids_lst.btnSortDate.setBackgroundColor(0xFF1E1E1E)
    ids_lst.btnSortSize.setBackgroundColor(0xFF1E1E1E)
    refreshList()
  end
  
  ids_lst.btnSortDate.onClick = function()
    currentSort = "date"
    ids_lst.btnSortDate.setBackgroundColor(0xFF1565C0)
    ids_lst.btnSortName.setBackgroundColor(0xFF1E1E1E)
    ids_lst.btnSortSize.setBackgroundColor(0xFF1E1E1E)
    refreshList()
  end
  
  ids_lst.btnSortSize.onClick = function()
    currentSort = "size"
    ids_lst.btnSortSize.setBackgroundColor(0xFF1565C0)
    ids_lst.btnSortName.setBackgroundColor(0xFF1E1E1E)
    ids_lst.btnSortDate.setBackgroundColor(0xFF1E1E1E)
    refreshList()
  end
  
  ids_lst.etSearch.addTextChangedListener(luajava.createProxy("android.text.TextWatcher", {
    afterTextChanged = function(s)
      currentSearch = tostring(s)
      refreshList()
    end,
    beforeTextChanged = function() end,
    onTextChanged = function() end
  }))
  
  ids_lst.btnVoltarLst.onClick = function()
    dlg.dismiss()
    criarInterfacePrincipal()
  end
  
  ids_lst.btnSortName.setBackgroundColor(0xFF1565C0)
  refreshList()
  
  dlg.show()
end

local function mostrarDialogoComunidade()
  fecharTodos()
  local commDlg = LuaDialog(service)
  
  local mainLayout = LinearLayout(service)
  mainLayout.setOrientation(LinearLayout.VERTICAL)
  mainLayout.setPadding(16, 16, 16, 16)
  mainLayout.setBackgroundColor(0xFF000000)
  
  local title = TextView(service)
  title.setText("Community Links")
  title.setTextColor(0xFFFFCC00)
  title.setTextSize(20)
  title.setGravity(Gravity.CENTER)
  title.setPadding(0, 0, 0, 16)
  mainLayout.addView(title)
  
  local scroll = ScrollView(service)
  local scrollParams = LinearLayout.LayoutParams(LayoutParams.MATCH_PARENT, 0)
  scrollParams.weight = 1
  scroll.setLayoutParams(scrollParams)
  
  local innerLayout = LinearLayout(service)
  innerLayout.setOrientation(LinearLayout.VERTICAL)
  innerLayout.setLayoutParams(LinearLayout.LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT))
  
  for _, link in ipairs(community_links) do
    local btn = Button(service)
    btn.setText(link.title)
    btn.setBackgroundColor(0xFF1E1E1E)
    btn.setTextColor(0xFFFFFFFF)
    btn.setPadding(16, 16, 16, 16)
    local url = link.url
    btn.onClick = function()
      commDlg.dismiss()
      handler.postDelayed(Runnable({run=function()
        pcall(function()
          local intent = Intent(Intent.ACTION_VIEW, Uri.parse(url))
          intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
          service.startActivity(intent)
        end)
      end}), 200)
    end
    innerLayout.addView(btn)
    local sep = View(service)
    sep.setBackgroundColor(0xFF333333)
    sep.setLayoutParams(LinearLayout.LayoutParams(LayoutParams.MATCH_PARENT, 1))
    innerLayout.addView(sep)
  end
  
  scroll.addView(innerLayout)
  mainLayout.addView(scroll)
  
  local closeBtn = Button(service)
  closeBtn.setText("Back")
  closeBtn.setBackgroundColor(0xFF333333)
  closeBtn.setTextColor(0xFFFFFFFF)
  closeBtn.setPadding(16, 12, 16, 12)
  closeBtn.onClick = function()
    commDlg.dismiss()
    criarInterfacePrincipal()
  end
  mainLayout.addView(closeBtn)
  
  commDlg.setView(mainLayout)
  commDlg.setCancelable(true)
  commDlg.show()
end

function showDeveloperNotifications()
    fetchNotificationContent(function(content)
        if not content then
            mainHandler.post(Runnable({
                run = function()
                    Toast.makeText(service, "No notifications available or network error.", Toast.LENGTH_SHORT).show()
                end
            }))
            return
        end
        
        mainHandler.post(Runnable({
            run = function()
                markNotificationRead(content)
                local notifDlg = LuaDialog(service)
                local layout = {
                    LinearLayout, orientation = "vertical", padding = "16dp",
                    background = "#000000", layout_width = "fill", layout_height = "fill",
                    {ScrollView, layout_width = "fill", layout_height = "0dp", layout_weight = "1",
                      {LinearLayout, id = "notifContainer", orientation = "vertical", layout_width = "fill", layout_height = "wrap"}
                    },
                    {Button, id = "btnCloseNotif", text = "Close",
                     layout_width = "fill", background = "#333333", textColor = "#FFFFFF"}
                }
                local views = {}
                notifDlg.setView(loadlayout(layout, views))
                notifDlg.setTitle("Developer Notifications")
                notifDlg.setCancelable(false)

                local container = views.notifContainer
                local text = content
                local pos = 1
                local pattern = "%[([^%]]+)%]%s*%(\"([^\"]+)\"%)"
                while true do
                    local s, e, label, link = string.find(text, pattern, pos)
                    if not s then
                        local remaining = string.sub(text, pos)
                        if remaining ~= "" then
                            local tv = TextView(service)
                            tv.setText(remaining)
                            tv.setTextColor(0xFFFFFFFF)
                            tv.setTextSize(14)
                            tv.setPadding(0, 4, 0, 4)
                            container.addView(tv)
                        end
                        break
                    else
                        local before = string.sub(text, pos, s - 1)
                        if before ~= "" then
                            local tv = TextView(service)
                            tv.setText(before)
                            tv.setTextColor(0xFFFFFFFF)
                            tv.setTextSize(14)
                            tv.setPadding(0, 4, 0, 4)
                            container.addView(tv)
                        end
                        local btn = Button(service)
                        btn.setText(label)
                        btn.setBackgroundColor(0xFF1E1E1E)
                        btn.setTextColor(0xFFFFFFFF)
                        btn.setPadding(16, 12, 16, 12)
                        local urlLink = link
                        btn.onClick = function()
                            fecharTodos()
                            notifDlg.dismiss()
                            dismissCurrentUpdateDialog()
                            pcall(function()
                                local intent = Intent(Intent.ACTION_VIEW, Uri.parse(urlLink))
                                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                service.startActivity(intent)
                            end)
                        end
                        container.addView(btn)
                        pos = e + 1
                    end
                end

                views.btnCloseNotif.onClick = function()
                    notifDlg.dismiss()
                    if dlg then pcall(function() criarInterfacePrincipal() end) end
                end

                notifDlg.show()
            end
        }))
    end)
end

function criarInterfacePrincipal()
  fecharTodos()

  local ids_main = {}
  dlg = LuaDialog(service)
  
  dlg.setView(loadlayout({
    LinearLayout, orientation="vertical", padding="0dp",
    background="#000000", layout_width="fill", layout_height="fill",
    
    {LinearLayout, orientation="horizontal", layout_width="fill",
     padding="16dp", gravity="center_vertical",
      {TextView, text=T("app_title"), textSize="22sp",
        textColor="#FFFFFF", layout_weight="1"},
      {Button, id="btnMenu", text="Menu",
        background="#1E1E1E", textColor="#FFFFFF", textSize="13sp",
        layout_width="wrap_content"},
    },
    
    {LinearLayout, orientation="vertical", padding="20dp",
     layout_width="fill", layout_height="0dp", layout_weight="1",
     
      {Button, id="btnCreateNew", text="Create New File",
        layout_width="fill", layout_height="wrap_content",
        background="#FF6600", textColor="#FFFFFF", textSize="16sp",
        layout_marginBottom="10dp"},

      {Button, id="btnRecent", text="Recent Files",
        layout_width="fill", layout_height="wrap_content",
        background="#1E1E1E", textColor="#FFFFFF", textSize="16sp",
        layout_marginBottom="10dp"},

      {Button, id="btnAbout", text="About",
        layout_width="fill", layout_height="wrap_content",
        background="#1E1E1E", textColor="#FFFFFF", textSize="16sp",
        layout_marginBottom="10dp"},

      {Button, id="btnCommunity", text="Community Links",
        layout_width="fill", layout_height="wrap_content",
        background="#1E1E1E", textColor="#FFFFFF", textSize="16sp",
        layout_marginBottom="10dp"},

      {View, layout_width="fill", layout_height="0dp", layout_weight="1"},

      {Button, id="btnFechar", text=T("close"),
        layout_width="fill", layout_height="wrap_content",
        background="#333333", textColor="#FFFFFF", textSize="15sp"},
    },
  }, ids_main))
  dlg.setCancelable(false)

  ids_main.btnCreateNew.onClick = function() criarNovaFile() end
  ids_main.btnRecent.onClick = function() criarListaDocumentos() end
  ids_main.btnAbout.onClick = function() mostrarSobre() end
  ids_main.btnCommunity.onClick = function() mostrarDialogoComunidade() end
  ids_main.btnMenu.onClick = function() mostrarMenu() end
  ids_main.btnFechar.onClick = function() fecharTodos() end

  dlg.show()
end

function startupFlow()
    local checkDlg = LuaDialog(service)
    checkDlg.setTitle("Checking for Updates")
    checkDlg.setMessage("Please wait, checking for updates...")
    checkDlg.setCancelable(false)
    checkDlg.show()
    
    local currentVer = getCurrentVersion()
    local timestamp = tostring(os.time())
    
    Http.get(VERSION_URL .. "?t=" .. timestamp, function(code, response)
        if code == 200 and response then
            local onlineVersion = trim(response):match("([%d%.]+)") or trim(response)
            if onlineVersion ~= "" and onlineVersion ~= currentVer then
                mainHandler.post(Runnable({
                    run = function()
                        pcall(function() checkDlg.dismiss() end)
                        Toast.makeText(service, "Update available! v" .. onlineVersion, Toast.LENGTH_LONG).show()
                    end
                }))
                fetchAndShowUpdate(onlineVersion)
            else
                mainHandler.post(Runnable({
                    run = function()
                        pcall(function() checkDlg.dismiss() end)
                        Toast.makeText(service, "No update available. You are on latest version (" .. currentVer .. ")", Toast.LENGTH_LONG).show()
                        criarInterfacePrincipal()
                        handler.postDelayed(Runnable({
                            run = function()
                                fetchNotificationContent(function(content)
                                    if content and isNotificationUnread(content) then
                                        showDeveloperNotifications()
                                    end
                                end)
                            end
                        }), 1500)
                    end
                }))
            end
        else
            mainHandler.post(Runnable({
                run = function()
                    pcall(function() checkDlg.dismiss() end)
                    Toast.makeText(service, "Could not check for updates. Loading app...", Toast.LENGTH_SHORT).show()
                    criarInterfacePrincipal()
                    handler.postDelayed(Runnable({
                        run = function()
                            fetchNotificationContent(function(content)
                                if content and isNotificationUnread(content) then
                                    showDeveloperNotifications()
                                end
                            end)
                        end
                    }), 1500)
                end
            }))
        end
    end)
end

startupFlow()