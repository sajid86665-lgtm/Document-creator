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
import "android.speech.tts.TextToSpeech"
import "android.media.MediaScannerConnection"

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
local PLUGIN_AUTHOR = "sajid86665"
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
        if wf then
            wf:write(version)
            wf:close()
        end
    end
    return version
end

function showLoading(message)
    mainHandler.post(Runnable({
        run = function()
            if loadingDialog then
                pcall(function() loadingDialog.dismiss() end)
            end
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
            errorDialog.setButton("OK", function()
                errorDialog.dismiss()
            end)
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
                            if trimmed ~= "" then
                                table.insert(changelogLines, trimmed)
                            end
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
                                {
                                    Button,
                                    id = "dismissBtn",
                                    text = "Dismiss update dialog",
                                    layout_width = "fill",
                                    layout_height = "wrap",
                                    layout_marginBottom = "15dp"
                                },
                                {
                                    TextView,
                                    text = "A new version of the extension is available!",
                                    textSize = 15,
                                    textColor = "#333333",
                                    paddingBottom = "15dp"
                                },
                                {
                                    LinearLayout,
                                    orientation = "horizontal",
                                    layout_width = "fill",
                                    layout_height = "wrap",
                                    paddingBottom = "10dp",
                                    {
                                        TextView,
                                        text = "Current Version: ",
                                        textSize = 14,
                                        textColor = "#666666",
                                        typeface = Typeface.DEFAULT_BOLD
                                    },
                                    {
                                        TextView,
                                        text = currentVer,
                                        textSize = 14,
                                        textColor = "#D32F2F",
                                        typeface = Typeface.DEFAULT_BOLD
                                    }
                                },
                                {
                                    LinearLayout,
                                    orientation = "horizontal",
                                    layout_width = "fill",
                                    layout_height = "wrap",
                                    paddingBottom = "15dp",
                                    {
                                        TextView,
                                        text = "Server Version: ",
                                        textSize = 14,
                                        textColor = "#666666",
                                        typeface = Typeface.DEFAULT_BOLD
                                    },
                                    {
                                        TextView,
                                        text = onlineVersion,
                                        textSize = 14,
                                        textColor = "#2E7D32",
                                        typeface = Typeface.DEFAULT_BOLD
                                    }
                                },
                                {
                                    TextView,
                                    text = "What's New:",
                                    textSize = 14,
                                    textColor = "#1976D2",
                                    typeface = Typeface.DEFAULT_BOLD,
                                    paddingBottom = "5dp"
                                },
                                {
                                    LinearLayout,
                                    id = "changelogContainer",
                                    orientation = "vertical",
                                    layout_width = "fill",
                                    layout_height = "wrap",
                                    paddingBottom = "20dp"
                                },
                                {
                                    Button,
                                    id = "updateBtn",
                                    text = "Update",
                                    layout_width = "fill",
                                    layout_height = "wrap",
                                    layout_marginTop = "10dp"
                                }
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
                            onDismiss = function(dialog)
                                updateDialogShowing = false
                            end
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
        else
            local tempPath = PLUGIN_PATH .. ".temp_update"
            local tf = io.open(tempPath, "w")
            if tf then
                tf:write(mainCode)
                tf:close()
                pcall(function() os.remove(PLUGIN_PATH) end)
                local renameOk = pcall(function() os.rename(tempPath, PLUGIN_PATH) end)
                if renameOk then
                    success = true
                else
                    pcall(function() os.remove(tempPath) end)
                end
            end
        end
        
        if success then
            local vf = io.open(VERSION_FILE, "w")
            if vf then
                vf:write(onlineVersion)
                vf:close()
            else
                success = false
            end
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
                                    if func then
                                        pcall(func)
                                    else
                                        Toast.makeText(service, "Error reloading: " .. tostring(err), Toast.LENGTH_SHORT).show()
                                    end
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
    
    Thread(luajava.bindClass("java.lang.Runnable"){
        run = updateProcess
    }).start()
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
  join_community     = "Join our official community",
  back               = "Back",
  name_doc           = "Document name",
  content_doc        = "Write your document",
  create_txt         = "Create TXT Document",
  view_docs          = "View Documents",
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
  advanced           = "Advanced Settings",
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

local function T(k)
  return strings[k] or k
end

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

local formatList = {
  {label = "Text (.txt)", ext = ".txt", template = "Welcome to Document Creator!\n\nThis is a simple plain text document.\nYou can write notes, ideas, drafts, or reminders here.\n\nExample todo list:\n- Buy groceries\n- Call mom\n- Finish project\n- Read a book\n\nHave a great day!"},
  {label = "Markdown (.md)", ext = ".md", template = "# My First Markdown Document\n\nWelcome to **Markdown**!\n\n## Features\n\n- **Bold** text\n- *Italic* text\n- [Links](https://example.com)\n\n## Code Example\n\n```\nprint(\"Hello, World!\")\n```\n\n> Blockquote: Markdown is easy to learn!"},
  {label = "HTML (.html)", ext = ".html", template = "<!DOCTYPE html>\n<html lang=\"en\">\n<head>\n    <meta charset=\"UTF-8\">\n    <title>My Web Page</title>\n    <style>\n        body { font-family: Arial, sans-serif; max-width: 800px; margin: 40px auto; padding: 20px; background: #f5f5f5; }\n        h1 { color: #1976D2; }\n        button { padding: 10px 20px; background: #1976D2; color: white; border: none; border-radius: 5px; cursor: pointer; }\n    </style>\n</head>\n<body>\n    <h1>Hello, World!</h1>\n    <p>This is a complete HTML document.</p>\n    <button onclick=\"alert('Clicked!')\">Click Me</button>\n    <script>console.log(\"Page loaded\");</script>\n</body>\n</html>"},
  {label = "CSS (.css)", ext = ".css", template = "* { margin: 0; padding: 0; box-sizing: border-box; }\n\nbody {\n    font-family: system-ui, sans-serif;\n    background: #f5f5f5;\n    color: #222;\n    line-height: 1.6;\n    padding: 20px;\n}\n\n.container {\n    max-width: 800px;\n    margin: 0 auto;\n    background: white;\n    padding: 30px;\n    border-radius: 8px;\n    box-shadow: 0 2px 8px rgba(0, 0, 0, 0.1);\n}\n\nh1 { color: #1976D2; margin-bottom: 16px; }"},
  {label = "JavaScript (.js)", ext = ".js", template = "function greet(name) {\n    return \"Hello, \" + name + \"!\";\n}\n\nfunction factorial(n) {\n    if (n <= 1) return 1;\n    return n * factorial(n - 1);\n}\n\nconst users = [\"Alice\", \"Bob\", \"Charlie\"];\nusers.forEach(user => console.log(greet(user)));\n\nconsole.log(\"5! =\", factorial(5));"},
  {label = "JSON (.json)", ext = ".json", template = "{\n    \"name\": \"Document Creator\",\n    \"version\": \"1.0\",\n    \"author\": \"sajid86665\",\n    \"features\": [\"Create documents\", \"Multiple formats\", \"Auto update\"]\n}"},
  {label = "XML (.xml)", ext = ".xml", template = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<catalog>\n    <book id=\"bk101\">\n        <author>Gambardella, Matthew</author>\n        <title>XML Developer's Guide</title>\n        <price>44.95</price>\n    </book>\n</catalog>"},
  {label = "CSV (.csv)", ext = ".csv", template = "id,name,email,age,city\n1,Alice Smith,alice@example.com,25,New York\n2,Bob Johnson,bob@example.com,30,London\n3,Charlie Brown,charlie@example.com,35,Tokyo"},
  {label = "PHP (.php)", ext = ".php", template = "<?php\nclass Greeter {\n    private $name;\n    public function __construct($name) { $this->name = $name; }\n    public function greet() { return \"Hello, \" . $this->name . \"!\"; }\n}\n\n$greeter = new Greeter(\"World\");\necho $greeter->greet() . \"\\n\";\n\n$fruits = [\"Apple\", \"Banana\", \"Cherry\"];\nforeach ($fruits as $index => $fruit) {\n    echo ($index + 1) . \". \" . $fruit . \"\\n\";\n}\n?>"},
  {label = "Python (.py)", ext = ".py", template = "#!/usr/bin/env python3\n\ndef greet(name):\n    return f\"Hello, {name}!\"\n\ndef fibonacci(n):\n    a, b = 0, 1\n    result = []\n    for _ in range(n):\n        result.append(a)\n        a, b = b, a + b\n    return result\n\nif __name__ == \"__main__\":\n    print(greet(\"World\"))\n    print(\"Fibonacci:\", fibonacci(10))"},
  {label = "Lua (.lua)", ext = ".lua", template = "-- Lua Starter Template - Runnable example\n\nlocal function greet(name)\n    return \"Hello, \" .. name .. \"!\"\nend\n\nlocal fruits = {\"Apple\", \"Banana\", \"Cherry\"}\n\nfor i, fruit in ipairs(fruits) do\n    print(i .. \". \" .. fruit)\nend\n\nlocal function fibonacci(n)\n    local a, b = 0, 1\n    local result = {}\n    for i = 1, n do\n        table.insert(result, a)\n        a, b = b, a + b\n    end\n    return result\nend\n\nprint(greet(\"World\"))\nprint(\"Fibonacci: \" .. table.concat(fibonacci(10), \", \"))"},
  {label = "Java (.java)", ext = ".java", template = "public class Main {\n    public static void main(String[] args) {\n        System.out.println(\"Hello, World!\");\n        for (int i = 1; i <= 5; i++) {\n            System.out.println(\"Count: \" + i);\n        }\n        System.out.println(\"Sum: \" + add(10, 20));\n    }\n    public static int add(int a, int b) { return a + b; }\n}"},
  {label = "C++ (.cpp)", ext = ".cpp", template = "#include <iostream>\n#include <vector>\n#include <string>\n\nint add(int a, int b) { return a + b; }\n\nint main() {\n    std::cout << \"Hello, World!\" << std::endl;\n    std::vector<std::string> fruits = {\"Apple\", \"Banana\", \"Cherry\"};\n    for (const auto& fruit : fruits) {\n        std::cout << \"- \" << fruit << std::endl;\n    }\n    std::cout << \"Sum: \" << add(10, 20) << std::endl;\n    return 0;\n}"},
  {label = "C (.c)", ext = ".c", template = "#include <stdio.h>\n\nint add(int a, int b) { return a + b; }\n\nint main() {\n    printf(\"Hello, World!\\n\");\n    for (int i = 1; i <= 5; i++) {\n        printf(\"Count: %d\\n\", i);\n    }\n    printf(\"Sum: %d\\n\", add(10, 20));\n    return 0;\n}"},
  {label = "SQL (.sql)", ext = ".sql", template = "CREATE TABLE users (\n    id INTEGER PRIMARY KEY,\n    name VARCHAR(100) NOT NULL,\n    email VARCHAR(100) UNIQUE,\n    age INTEGER\n);\n\nINSERT INTO users (name, email, age) VALUES\n('Alice Smith', 'alice@example.com', 25),\n('Bob Johnson', 'bob@example.com', 30);\n\nSELECT * FROM users;\nSELECT name, email FROM users WHERE age > 25 ORDER BY age DESC;"},
  {label = "YAML (.yaml)", ext = ".yaml", template = "app:\n  name: Document Creator\n  version: 1.0\n  author: sajid86665\n\nserver:\n  host: localhost\n  port: 8080\n  ssl: false\n\ndatabase:\n  driver: mysql\n  host: localhost\n  name: myapp_db\n\nfeatures:\n  - auto_update\n  - developer_notifications\n  - multiple_formats"},
  {label = "INI (.ini)", ext = ".ini", template = "; INI Configuration File\n\n[application]\nname=Document Creator\nversion=1.0\nauthor=sajid86665\n\n[server]\nhost=localhost\nport=8080\nssl=false\n\n[features]\nauto_update=true\ndeveloper_notifications=true"},
  {label = "Shell (.sh)", ext = ".sh", template = "#!/bin/bash\n\necho \"Hello, World!\"\n\nNAME=\"Alice\"\nAGE=25\n\necho \"Name: $NAME\"\necho \"Age: $AGE\"\n\nfor i in {1..5}; do\n    echo \"Count: $i\"\ndone\n\nif [ \"$AGE\" -gt 18 ]; then\n    echo \"$NAME is an adult\"\nfi"},
  {label = "Batch (.bat)", ext = ".bat", template = "@echo off\nREM Batch Script\n\necho Hello, World!\n\nset NAME=Alice\nset AGE=25\n\necho Name: %NAME%\necho Age: %AGE%\n\nfor /L %%i in (1,1,5) do (\n    echo Count: %%i\n)\n\npause"},
  {label = "Log (.log)", ext = ".log", template = "2024-01-15 10:23:45 INFO  Application started successfully\n2024-01-15 10:23:46 INFO  Loading configuration\n2024-01-15 10:23:47 INFO  Database connection established\n2024-01-15 10:24:12 INFO  User logged in: alice@example.com\n2024-01-15 10:25:30 WARN  High memory usage detected: 85%\n2024-01-15 10:27:42 ERROR Failed to connect to API: timeout"},
  {label = "RTF (.rtf)", ext = ".rtf", template = "{\\rtf1\\ansi\\deff0\n{\\fonttbl{\\f0 Arial;}}\n\\f0\\fs24\nHello, World!\\par\n\\par\nThis is an RTF document.\\par\n\\b Bold\\b0  and \\i italic\\i0  styles supported.\\par\n}"},
  {label = "TypeScript (.ts)", ext = ".ts", template = "interface User {\n    id: number;\n    name: string;\n    email: string;\n}\n\nfunction greet(user: User): string {\n    return `Hello, ${user.name}!`;\n}\n\nconst users: User[] = [\n    { id: 1, name: \"Alice\", email: \"alice@example.com\" },\n    { id: 2, name: \"Bob\", email: \"bob@example.com\" }\n];\n\nusers.forEach(user => console.log(greet(user)));"},
  {label = "Kotlin (.kt)", ext = ".kt", template = "fun greet(name: String): String {\n    return \"Hello, $name!\"\n}\n\nfun main() {\n    println(greet(\"World\"))\n    val fruits = listOf(\"Apple\", \"Banana\", \"Cherry\")\n    for ((index, fruit) in fruits.withIndex()) {\n        println(\"${index + 1}. $fruit\")\n    }\n}"},
  {label = "Go (.go)", ext = ".go", template = "package main\n\nimport \"fmt\"\n\nfunc greet(name string) string {\n    return \"Hello, \" + name + \"!\"\n}\n\nfunc main() {\n    fmt.Println(greet(\"World\"))\n    fruits := []string{\"Apple\", \"Banana\", \"Cherry\"}\n    for i, fruit := range fruits {\n        fmt.Printf(\"%d. %s\\n\", i+1, fruit)\n    }\n}"},
  {label = "Ruby (.rb)", ext = ".rb", template = "def greet(name)\n  \"Hello, #{name}!\"\nend\n\nputs greet(\"World\")\n\nfruits = [\"Apple\", \"Banana\", \"Cherry\"]\nfruits.each_with_index do |fruit, index|\n  puts \"#{index + 1}. #{fruit}\"\nend"},
  {label = "Rust (.rs)", ext = ".rs", template = "fn greet(name: &str) -> String {\n    format!(\"Hello, {}!\", name)\n}\n\nfn main() {\n    println!(\"{}\", greet(\"World\"));\n    let fruits = vec![\"Apple\", \"Banana\", \"Cherry\"];\n    for (i, fruit) in fruits.iter().enumerate() {\n        println!(\"{}. {}\", i + 1, fruit);\n    }\n}"},
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

local function nomeValido(n)
  if not n or n:gsub("%s", "") == "" then return false end
  if n:find('[\\/:*?"<>|]') then return false end
  return true
end

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
         layout_width="fill", background="#333333", textColor="#FFFFFF",
         layout_marginTop="10dp"}
    }, ids_rr))
    ids_rr.btnCloseResult.onClick = function()
        resultDlg.dismiss()
    end
    resultDlg.show()
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

    {TextView, text="Choose format:", textColor="#FFFFFF", textSize="13sp",
      paddingBottom="4dp"},

    {Spinner, id="spFormat",
      layout_width="fill", background="#222222"},

    {LinearLayout, orientation="horizontal", layout_width="fill",
      layout_marginTop="6dp",
      {Button, id="btnTemplate", text="Insert Template",
        background="#2E7D32", textColor="#FFFFFF", layout_weight="1",
        textSize="14sp"},
      {Button, id="btnRun", text="Run",
        background="#1565C0", textColor="#FFFFFF", layout_weight="1",
        textSize="14sp"},
    },

    {EditText, id="etTitulo", hint="Enter file title",
      textColor="#FFFFFF", background="#222222",
      layout_width="fill", layout_height="wrap_content",
      inputType="text", layout_marginTop="10dp"},

    {EditText, id="etConteudoNovo", hint="Write your content",
      textColor="#FFFFFF", background="#222222",
      layout_width="fill", layout_height="0dp", layout_weight="1",
      minLines=8, gravity="top", layout_marginTop="10dp"},

    {LinearLayout, orientation="horizontal", layout_width="fill",
      layout_marginTop="10dp",
      {Button, id="btnCriarNovo", text="Create",
        background="#FF6600", textColor="#FFFFFF", layout_weight="1"},
      {Button, id="btnCancelNovo", text="Cancel",
        background="#333333", textColor="#FFFFFF", layout_weight="1"},
    },
  }, ids_nf))
  dlg.setCancelable(false)

  local labels = {}
  for _, fmt in ipairs(formatList) do
    table.insert(labels, fmt.label)
  end
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
        for i = 1, #args do
          parts[#parts + 1] = tostring(args[i])
        end
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
          showRunResult("Lua Output", "(no output)\n\nCode ran successfully without any print statements.")
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
      if wf then
        wf:write(code)
        wf:close()
      end
      pcall(function()
        local intent = Intent(Intent.ACTION_VIEW)
        intent.setDataAndType(Uri.parse("file://" .. tempPath), "text/html")
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        service.startActivity(intent)
      end)
      Toast.makeText(service, "Opening HTML preview in browser", Toast.LENGTH_SHORT).show()
      return
    end

    local tempPath = dir .. "_preview_" .. os.time() .. fmt.ext
    local wf = io.open(tempPath, "w")
    if wf then
      wf:write(code)
      wf:close()
      showRunResult(
        "Preview Saved",
        "This format (" .. fmt.ext .. ") cannot be executed inside the app.\n\n" ..
        "Preview file saved at:\n" .. tempPath .. "\n\n" ..
        "You can open it with an external app or copy the code into an IDE to test it."
      )
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

    local ok, err = pcall(function()
      local fi = io.open(dir .. n .. fmt.ext, "w")
      fi:write(c)
      fi:close()
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
  local ids_ab = {}
  dlg = LuaDialog(service)
  dlg.setView(loadlayout({
    LinearLayout, orientation="vertical", padding="20dp",
    background="#000000", layout_width="fill", layout_height="wrap_content",
    {TextView, text="About", textSize="20sp",
      textColor="#FFCC00", gravity="center", paddingBottom="15dp"},
    {TextView, text="Plugin: "..PLUGIN_NAME, textColor="#FFFFFF",
      textSize="14sp", paddingBottom="6dp"},
    {TextView, text="Version: "..getCurrentVersion(), textColor="#FFFFFF",
      textSize="14sp", paddingBottom="6dp"},
    {TextView, text="Author: "..PLUGIN_AUTHOR, textColor="#FFFFFF",
      textSize="14sp", paddingBottom="6dp"},
    {TextView, text="Description:", textColor="#AAAAAA",
      textSize="13sp", paddingBottom="4dp"},
    {TextView, text=PLUGIN_DESC, textColor="#FFFFFF",
      textSize="14sp", paddingBottom="10dp"},
    {TextView, text="Storage path:", textColor="#AAAAAA",
      textSize="12sp", paddingBottom="2dp"},
    {TextView, text=dir, textColor="#88CCFF",
      textSize="12sp", paddingBottom="15dp"},
    {Button, id="btnBackAb", text="Back",
      layout_width="fill", background="#333333", textColor="#FFFFFF"},
  }, ids_ab))
  dlg.setCancelable(false)
  ids_ab.btnBackAb.onClick = function()
    dlg.dismiss()
    criarInterfacePrincipal()
  end
  dlg.show()
end

local function mostrarMais()
  fecharTodos()
  local ids_m = {}
  dlg = LuaDialog(service)
  dlg.setView(loadlayout({
    LinearLayout, orientation="vertical", padding="16dp",
    background="#000000", layout_width="fill", layout_height="wrap_content",
    {TextView, text="More Options", textSize="18sp",
      textColor="#FFCC00", gravity="center", paddingBottom="12dp"},

    {Button, id="btnCheckUpdate", text=T("check_updates"),
      layout_width="fill", background="#1E1E1E", textColor="#FFFFFF",
      layout_marginBottom="6dp"},

    {Button, id="btnDevNotifications", text=T("dev_notifications"),
      layout_width="fill", background="#1E1E1E", textColor="#FFFFFF",
      layout_marginBottom="6dp"},

    {Button, id="btnTalkDev", text=T("talk_dev"),
      layout_width="fill", background="#1E1E1E", textColor="#FFFFFF",
      layout_marginBottom="6dp"},

    {Button, id="btnBackMore", text="Back",
      layout_width="fill", background="#333333", textColor="#FFFFFF"},
  }, ids_m))
  dlg.setCancelable(false)

  updateNotifButton(ids_m.btnDevNotifications)

  ids_m.btnCheckUpdate.onClick = function()
    checkUpdate(true)
  end

  ids_m.btnDevNotifications.onClick = function()
    showDeveloperNotifications()
  end

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
    {TextView, text=T("details_title"), textSize="16sp",
      textColor="#FFCC00", gravity="center", paddingBottom="10dp"},
    {TextView, text=T("detail_name")..": "..nome,
      textColor="#FFFFFF", textSize="14sp", paddingBottom="4dp"},
    {TextView, text=T("detail_size")..": "..arquivo.length().." bytes",
      textColor="#FFFFFF", textSize="14sp", paddingBottom="4dp"},
    {TextView, text=T("detail_modified")..": "..os.date("%d/%m/%Y %H:%M:%S", math.floor(arquivo.lastModified()/1000)),
      textColor="#FFFFFF", textSize="14sp", paddingBottom="4dp"},
    {TextView, text=T("detail_path")..": "..arquivo.getAbsolutePath(),
      textColor="#AAAAAA", textSize="13sp", paddingBottom="8dp"},
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
    {TextView, text=T("edit_name"), textSize="16sp",
      textColor="#FFCC00", gravity="center", paddingBottom="8dp"},
    {EditText, id="etNovoNome",
      text=baseName,
      hint=T("new_name"),
      textColor="#FFFFFF", background="#222222", layout_width="fill"},
    {LinearLayout, orientation="horizontal", layout_width="fill",
      {Button, id="btnSaveNome", text=T("save"),
        background="#FF6600", textColor="#FFFFFF", layout_weight="1"},
      {Button, id="btnCancelNome", text=T("cancel"),
        background="#333333", textColor="#FFFFFF", layout_weight="1"},
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
  local txt = ""
  local arq = io.open(dir .. nome)
  if arq then txt = arq:read("*a"); arq:close() end

  local ids_ec = {}
  dlgEditarConteudo = LuaDialog(service)
  dlgEditarConteudo.setView(loadlayout({
    LinearLayout, orientation="vertical", padding="10dp",
    background="#000000", layout_width="fill", layout_height="fill",
    {TextView, text=T("edit_content"), textSize="15sp",
      textColor="#FFCC00", gravity="center", paddingBottom="6dp"},
    {ScrollView, layout_width="fill", layout_height="0dp", layout_weight="1",
      {EditText, id="etConteudoNovo", text=txt,
        textColor="#FFFFFF", background="#222222",
        layout_width="fill", layout_height="wrap_content",
        minLines=10, gravity="top"}
    },
    {LinearLayout, orientation="horizontal", layout_width="fill",
      {Button, id="btnSaveConteudo", text=T("save"),
        background="#FF6600", textColor="#FFFFFF", layout_weight="1"},
      {Button, id="btnCancelConteudo", text=T("cancel"),
        background="#333333", textColor="#FFFFFF", layout_weight="1"},
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
  local txt = ""
  local arq = io.open(dir .. nome)
  if arq then txt = arq:read("*a"); arq:close()
  else txt = T("file_not_found") end

  local ids_vis = {}
  dlg = LuaDialog(service)
  dlg.setView(loadlayout({
    LinearLayout, orientation="vertical", padding="14dp",
    background="#000000", layout_width="fill", layout_height="fill",
    {TextView, text=T("viewing")..nome, textSize="15sp",
      textColor="#FFCC00", gravity="center", paddingBottom="6dp"},
    {Button, id="btnOpcoes", text=T("advanced"),
      layout_width="fill", background="#1E1E1E", textColor="#FFFFFF"},
    {ScrollView, layout_width="fill", layout_height="0dp", layout_weight="1",
      {TextView, id="tvConteudo", text=txt, textSize="15sp",
        textColor="#FFFFFF", background="#111111", padding="10dp",
        layout_width="fill", layout_height="wrap_content"}
    },
    {Button, id="btnVoltarVis", text=T("back"),
      layout_width="fill", background="#333333", textColor="#FFFFFF"},
  }, ids_vis))
  dlg.setCancelable(false)

  ids_vis.btnOpcoes.onClick = function()
    local function mostrarMenuOpcoes(nome)
      fecharTodos()
      local ids_op = {}
      dlgOpcoes = LuaDialog(service)
      dlgOpcoes.setView(loadlayout({
        LinearLayout, orientation="vertical", padding="14dp",
        background="#000000", layout_width="fill", layout_height="wrap_content",
        {TextView, text=T("document_label")..nome, textSize="14sp",
          textColor="#FFCC00", gravity="center", paddingBottom="8dp"},
        {Button, id="btnVerDet",    text=T("details"),      layout_width="fill", background="#1E1E1E", textColor="#FFFFFF"},
        {Button, id="btnEditNome",  text=T("edit_name"),    layout_width="fill", background="#1E1E1E", textColor="#FFFFFF"},
        {Button, id="btnEditCont",  text=T("edit_content"), layout_width="fill", background="#1E1E1E", textColor="#FFFFFF"},
        {Button, id="btnShare",     text=T("share"),        layout_width="fill", background="#1E1E1E", textColor="#FFFFFF"},
        {Button, id="btnDelete",    text=T("delete"),       layout_width="fill", background="#880000", textColor="#FFFFFF"},
        {Button, id="btnCloseOpts", text=T("close_options"),layout_width="fill", background="#333333", textColor="#FFFFFF"},
      }, ids_op))
      dlgOpcoes.setCancelable(false)

      ids_op.btnVerDet.onClick = function()
        mostrarDetalhes(nome, function() criarVisualizador(nome) end)
      end
      ids_op.btnEditNome.onClick = function()
        editarNome(nome, function() criarListaDocumentos() end)
      end
      ids_op.btnEditCont.onClick = function()
        editarConteudo(nome, function() criarListaDocumentos() end)
      end
      ids_op.btnShare.onClick = function()
        compartilhar(nome)
      end
      ids_op.btnDelete.onClick = function()
        File(dir .. nome).delete()
        Toast.makeText(service, T("deleted"), 1).show()
        falar(T("deleted"))
        dlgOpcoes.dismiss()
        criarListaDocumentos()
      end
      ids_op.btnCloseOpts.onClick = function()
        dlgOpcoes.dismiss()
        criarVisualizador(nome)
      end
      dlgOpcoes.show()
    end
    mostrarMenuOpcoes(nome)
  end
  ids_vis.btnVoltarVis.onClick = function()
    dlg.dismiss()
    criarListaDocumentos()
  end
  dlg.show()
end

local function criarListaDocumentos()
  fecharTodos()
  local arquivos = listarDocumentos()
  local ids_lst = {}

  dlg = LuaDialog(service)
  dlg.setView(loadlayout({
    LinearLayout, orientation="vertical", padding="14dp",
    background="#000000", layout_width="fill", layout_height="fill",
    {TextView, text="Recent Files", textSize="18sp",
      textColor="#FFCC00", gravity="center", paddingBottom="8dp"},
    {ScrollView, layout_width="fill", layout_height="0dp", layout_weight="1",
      {LinearLayout, id="llDocs", orientation="vertical", layout_width="fill"}
    },
    {Button, id="btnVoltarLst", text=T("back"),
      layout_width="fill", background="#333333", textColor="#FFFFFF"},
  }, ids_lst))
  dlg.setCancelable(false)

  if #arquivos == 0 then
    local tv = TextView(service)
    tv.setText(T("no_docs"))
    tv.setTextColor(0xFFAAAAAA)
    tv.setGravity(17)
    tv.setPadding(8,20,8,20)
    ids_lst.llDocs.addView(tv)
  else
    for _, nome in ipairs(arquivos) do
      local b = Button(service)
      b.setText(nome)
      b.setBackgroundColor(0xFF111111)
      b.setTextColor(0xFFFFFFFF)
      local n = nome
      b.onClick = function()
        criarVisualizador(n)
      end
      ids_lst.llDocs.addView(b)
    end
  end

  ids_lst.btnVoltarLst.onClick = function()
    dlg.dismiss()
    criarInterfacePrincipal()
  end
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
                    LinearLayout,
                    orientation = "vertical",
                    padding = "16dp",
                    background = "#000000",
                    layout_width = "fill",
                    layout_height = "fill",
                    {
                        ScrollView,
                        layout_width = "fill",
                        layout_height = "0dp",
                        layout_weight = "1",
                        {
                            LinearLayout,
                            id = "notifContainer",
                            orientation = "vertical",
                            layout_width = "fill",
                            layout_height = "wrap"
                        }
                    },
                    {
                        Button,
                        id = "btnCloseNotif",
                        text = "Close",
                        layout_width = "fill",
                        background = "#333333",
                        textColor = "#FFFFFF"
                    }
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
                    if dlg then
                        pcall(function() criarInterfacePrincipal() end)
                    end
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
    LinearLayout, orientation="vertical", padding="20dp",
    background="#000000", layout_width="fill", layout_height="fill",

    {TextView, text=T("app_title"), textSize="22sp",
      textColor="#FFFFFF", gravity="center", paddingBottom="20dp"},

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

    {Button, id="btnMore", text="More (Updates, Notifications)",
      layout_width="fill", layout_height="wrap_content",
      background="#1E1E1E", textColor="#FFFFFF", textSize="16sp",
      layout_marginBottom="20dp"},

    {View, layout_width="fill", layout_height="0dp", layout_weight="1"},

    {Button, id="btnFechar", text=T("close"),
      layout_width="fill", layout_height="wrap_content",
      background="#333333", textColor="#FFFFFF", textSize="15sp"},
  }, ids_main))
  dlg.setCancelable(false)

  ids_main.btnCreateNew.onClick = function()
    criarNovaFile()
  end

  ids_main.btnRecent.onClick = function()
    criarListaDocumentos()
  end

  ids_main.btnAbout.onClick = function()
    mostrarSobre()
  end

  ids_main.btnCommunity.onClick = function()
    mostrarDialogoComunidade()
  end

  ids_main.btnMore.onClick = function()
    mostrarMais()
  end

  ids_main.btnFechar.onClick = function()
    fecharTodos()
  end

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