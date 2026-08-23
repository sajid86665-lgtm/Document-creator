require "import"
import "android.widget.*"
import "android.view.*"
import "android.view.ViewGroup$LayoutParams"
import "android.graphics.Typeface"
import "android.text.method.ScrollingMovementMethod"
import "android.content.Context"
import "android.speech.tts.TextToSpeech"
import "java.io.File"
import "com.androlua.LuaDialog"
import "android.content.Intent"
import "android.net.Uri"
import "android.os.Environment"
import "android.media.MediaScannerConnection"
import "android.widget.Toast"
import "android.os.*"

-- ====== TTS ======
local tts = TextToSpeech(service, function(status)
  if status ~= TextToSpeech.SUCCESS then tts = nil end
end)
local function falar(txt)
  if tts and txt and txt ~= "" then
    tts.speak(txt, TextToSpeech.QUEUE_FLUSH, nil, nil)
  end
end

-- ====== PASTA DE DOCUMENTOS ======
local dir = "/storage/emulated/0/blind Tech hub/document creator/"
local f = File(dir)
if not f.exists() then f.mkdirs() end

-- ====== STRINGS (only English) ======
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
  created_by         = "Document List — Valter Fernando",
  viewing            = "Viewing: ",
  doc_options        = "Document Options",
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
}

local function T(k)
  return strings[k] or k
end

-- ====== COMMUNITY LINKS ======
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

local handler = Handler(Looper.getMainLooper())

-- ====== DIÁLOGOS ATIVOS ======
local dlg, dlgOpcoes, dlgEditar, dlgEditarConteudo

local function fecharTodos()
  for _, d in ipairs({dlg, dlgOpcoes, dlgEditar, dlgEditarConteudo}) do
    if d then pcall(function() d.dismiss() end) end
  end
end

-- ====== LISTAR DOCUMENTOS ======
local function listarDocumentos()
  local arquivos = {}
  local d = File(dir)
  if d.exists() then
    local files = d.listFiles()
    if files then
      for _, fi in ipairs(luajava.astable(files)) do
        if fi.isFile() and fi.getName():match("%.txt$") then
          table.insert(arquivos, fi.getName())
        end
      end
    end
  end
  table.sort(arquivos)
  return arquivos
end

-- ====== VALIDAÇÃO DO NOME ======
local function nomeValido(n)
  if not n or n:gsub("%s", "") == "" then return false end
  if n:find('[\\/:*?"<>|]') then return false end
  return true
end

-- ====== COMPARTILHAR ======
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

-- ====== DETALHES ======
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

-- ====== EDITAR NOME ======
local function editarNome(nome, onBack)
  fecharTodos()
  local ids_en = {}
  dlgEditar = LuaDialog(service)
  dlgEditar.setView(loadlayout({
    LinearLayout, orientation="vertical", padding="16dp",
    background="#000000", layout_width="fill", layout_height="wrap_content",
    {TextView, text=T("edit_name"), textSize="16sp",
      textColor="#FFCC00", gravity="center", paddingBottom="8dp"},
    {EditText, id="etNovoNome",
      text=nome:gsub("%.txt$",""),
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
    File(dir .. nome).renameTo(File(dir .. n .. ".txt"))
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

-- ====== EDITAR CONTEÚDO ======
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

-- declaração antecipada
local criarVisualizador
local criarListaDocumentos
local criarInterfacePrincipal

-- ====== MENU OPÇÕES DO DOCUMENTO ======
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

-- ====== VISUALIZADOR ======
criarVisualizador = function(nome)
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
    {Button, id="btnOpcoes", text="⚙ "..T("advanced"),
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
    mostrarMenuOpcoes(nome)
  end
  ids_vis.btnVoltarVis.onClick = function()
    dlg.dismiss()
    criarListaDocumentos()
  end
  dlg.show()
end

-- ====== LISTA DE DOCUMENTOS ======
criarListaDocumentos = function()
  fecharTodos()
  local arquivos = listarDocumentos()
  local ids_lst = {}

  dlg = LuaDialog(service)
  dlg.setView(loadlayout({
    LinearLayout, orientation="vertical", padding="14dp",
    background="#000000", layout_width="fill", layout_height="fill",
    {TextView, text=T("created_by"), textSize="16sp",
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

-- ====== COMMUNITY DIALOG ======
local function mostrarDialogoComunidade()
  fecharTodos()
  local commDlg = LuaDialog(service)
  
  -- Create a vertical layout for all links
  local mainLayout = LinearLayout(service)
  mainLayout.setOrientation(LinearLayout.VERTICAL)
  mainLayout.setPadding(16, 16, 16, 16)
  mainLayout.setBackgroundColor(0xFF000000)
  
  -- Title
  local title = TextView(service)
  title.setText("Community Links")
  title.setTextColor(0xFFFFCC00)
  title.setTextSize(20)
  title.setGravity(Gravity.CENTER)
  title.setPadding(0, 0, 0, 16)
  mainLayout.addView(title)
  
  -- ScrollView to hold all buttons
  local scroll = ScrollView(service)
  local scrollParams = LinearLayout.LayoutParams(LayoutParams.MATCH_PARENT, 0)
  scrollParams.weight = 1
  scroll.setLayoutParams(scrollParams)
  
  local innerLayout = LinearLayout(service)
  innerLayout.setOrientation(LinearLayout.VERTICAL)
  innerLayout.setLayoutParams(LinearLayout.LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT))
  
  -- Add all links as buttons
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
    
    -- Add a thin separator
    local sep = View(service)
    sep.setBackgroundColor(0xFF333333)
    sep.setLayoutParams(LinearLayout.LayoutParams(LayoutParams.MATCH_PARENT, 1))
    innerLayout.addView(sep)
  end
  
  scroll.addView(innerLayout)
  mainLayout.addView(scroll)
  
  -- Close button
  local closeBtn = Button(service)
  closeBtn.setText("Close")
  closeBtn.setBackgroundColor(0xFF333333)
  closeBtn.setTextColor(0xFFFFFFFF)
  closeBtn.setPadding(16, 12, 16, 12)
  closeBtn.onClick = function()
    commDlg.dismiss()
  end
  mainLayout.addView(closeBtn)
  
  commDlg.setView(mainLayout)
  commDlg.setCancelable(true)
  commDlg.show()
end

-- ====== INTERFACE PRINCIPAL ======
criarInterfacePrincipal = function()
  fecharTodos()

  local ids_main = {}
  dlg = LuaDialog(service)
  dlg.setView(loadlayout({
    LinearLayout, orientation="vertical", padding="16dp",
    background="#000000", layout_width="fill", layout_height="fill",

    -- título (changed to Document Creator)
    {TextView, text=T("app_title"), textSize="20sp",
      textColor="#FFFFFF", gravity="center", paddingBottom="8dp"},

    -- nome
    {EditText, id="etNome", hint=T("name_doc"),
      textColor="#FFFFFF", background="#222222",
      layout_width="fill", layout_height="wrap_content",
      inputType="text"},

    -- conteúdo
    {EditText, id="etConteudo", hint=T("content_doc"),
      textColor="#FFFFFF", background="#222222",
      layout_width="fill", layout_height="0dp", layout_weight="1",
      minLines=6, gravity="top"},

    -- criar TXT
    {Button, id="btnCriar", text=T("create_txt"),
      layout_width="fill", background="#FF6600", textColor="#FFFFFF"},

    -- visualizar
    {Button, id="btnVisualizar", text=T("view_docs"),
      layout_width="fill", background="#1E1E1E", textColor="#FFFFFF"},

    -- dev
    {Button, id="btnDev", text=T("talk_dev"),
      layout_width="fill", background="#1E1E1E", textColor="#FFFFFF"},

    -- Join + Close horizontal
    {LinearLayout, orientation="horizontal", layout_width="fill",
      {Button, id="btnJoinCommunity", text=T("join_community"),
        background="#1E1E1E", textColor="#FFFFFF", layout_weight="1"},
      {Button, id="btnFechar", text=T("close"),
        background="#333333", textColor="#FFFFFF", layout_weight="1"},
    },

  }, ids_main))
  dlg.setCancelable(false)

  -- ====== CRIAR TXT ======
  ids_main.btnCriar.onClick = function()
    local n = tostring(ids_main.etNome.getText()):gsub("^%s*(.-)%s*$", "%1")
    local c = tostring(ids_main.etConteudo.getText()):gsub("^%s*(.-)%s*$", "%1")

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
      local fi = io.open(dir .. n .. ".txt", "w")
      fi:write(c)
      fi:close()
    end)
    if ok then
      Toast.makeText(service, T("saved"), 1).show()
      falar(T("saved"))
    else
      Toast.makeText(service, T("error_save")..": "..tostring(err), 1).show()
      falar(T("error_save"))
    end
  end

  -- ====== VISUALIZAR ======
  ids_main.btnVisualizar.onClick = function()
    criarListaDocumentos()
  end

  -- ====== DEV ======
  ids_main.btnDev.onClick = function()
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

  -- ====== JOIN COMMUNITY ======
  ids_main.btnJoinCommunity.onClick = function()
    mostrarDialogoComunidade()
  end

  -- ====== FECHAR ======
  ids_main.btnFechar.onClick = function()
    fecharTodos()
  end

  dlg.show()
end

-- ====== INICIAR ======
criarInterfacePrincipal()