; ============================================================
; GERENCIADOR DE HORAS
; Instalador / Atualizador Windows
; Versão: 1.0.2
; Build Flutter: 3
; ============================================================

#define MyAppName "Gerenciador de Horas"
#define MyAppVersion "1.0.2"
#define MyAppPublisher "Rodrigo Zaparolli"
#define MyAppExeName "gerenciador_horas.exe"

#define DoubleAmp(Value) StringChange(Value, "&", "&&")
#define EscapeConstArgument(Value) StringChange(StringChange(StringChange(Value, "%", "%25"), ",", "%2c"), "}", "%7d")

[Setup]

; ============================================================
; IDENTIFICAÇÃO DO APLICATIVO
; ============================================================
;
; IMPORTANTE:
; O AppId deve permanecer SEMPRE igual entre todas as versões.
;
; É através dele que o Inno Setup reconhece que uma versão
; anterior do Gerenciador de Horas já está instalada.
; ============================================================

AppId={{141A2CB7-C319-4CCD-A75E-5ACBAB989829}

AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}

; ============================================================
; DIRETÓRIO DE INSTALAÇÃO
; ============================================================

DefaultDirName={autopf}\{#MyAppName}

UninstallDisplayIcon={app}\{#MyAppExeName}

; ============================================================
; ÍCONE DO INSTALADOR
; ============================================================

SetupIconFile=..\assets\images\Logo.ico

; ============================================================
; ARQUITETURA
; ============================================================

ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible

; ============================================================
; CONFIGURAÇÕES DA INSTALAÇÃO
; ============================================================

DisableProgramGroupPage=yes

; O aplicativo será instalado em Program Files.
; Portanto, o instalador solicitará privilégios administrativos.
PrivilegesRequired=admin

; ============================================================
; ARQUIVO DO INSTALADOR
; ============================================================
;
; IMPORTANTE:
; Este nome deve ser exatamente o mesmo utilizado no
; installerUrl do version.json publicado no GitHub.
;
; Resultado:
;
; Gerenciador_de_Horas_Setup_v1.0.2.exe
; ============================================================

OutputBaseFilename=Gerenciador_de_Horas_Setup_v1.0.2

; Diretório onde o instalador será gerado.
OutputDir=Output

; ============================================================
; COMPRESSÃO
; ============================================================

SolidCompression=yes
Compression=lzma2

; ============================================================
; INTERFACE
; ============================================================

WizardStyle=modern dark

; ============================================================
; ATUALIZAÇÃO
; ============================================================
;
; Permite que o instalador solicite o fechamento do aplicativo
; caso ele esteja aberto durante uma atualização.
; ============================================================

CloseApplications=yes

; Não tenta reiniciar automaticamente aplicações fechadas
; pelo instalador.
RestartApplications=no

; ============================================================
; IDIOMA
; ============================================================

[Languages]

Name: "brazilianportuguese"; \
MessagesFile: "compiler:Languages\BrazilianPortuguese.isl"

; ============================================================
; TAREFAS OPCIONAIS
; ============================================================

[Tasks]

Name: "desktopicon"; \
Description: "{cm:CreateDesktopIcon}"; \
GroupDescription: "{cm:AdditionalIcons}"; \
Flags: unchecked

; ============================================================
; ARQUIVOS DO FLUTTER
; ============================================================

[Files]

Source: "D:\APP\gerenciador_horas\build\windows\x64\runner\Release\*"; \
DestDir: "{app}"; \
Excludes: "*.pdb,*.lib,*.exp"; \
Flags: ignoreversion recursesubdirs createallsubdirs

; ============================================================
; PYTHON PORTÁTIL
; ============================================================
;
; Copia todo o ambiente Python portátil preparado para
; a integração com o Promob E-Desk.
;
; Inclui:
;
; - Python 3.14
; - bibliotecas Python
; - Playwright
; - Chromium
; - FFMPEG
; - PyAutoGUI
; - Pillow
; - PyMuPDF
; - pywin32
; - demais dependências
;
; No computador de destino:
;
; {app}\python\python.exe
;
; O Chromium portátil ficará em:
;
; {app}\python\ms-playwright
;
; O aplicativo configura automaticamente:
;
; PLAYWRIGHT_BROWSERS_PATH={app}\python\ms-playwright
;
; Portanto, o computador de destino não precisa possuir
; Python ou Playwright instalados separadamente.
; ============================================================

Source: "D:\APP\gerenciador_horas\python\*"; \
DestDir: "{app}\python"; \
Flags: ignoreversion recursesubdirs createallsubdirs

; ============================================================
; SCRIPTS DA INTEGRAÇÃO E-DESK
; ============================================================
;
; Copia todos os scripts Python utilizados pelo aplicativo.
;
; No computador de destino:
;
; {app}\edesk_bot
; ============================================================

Source: "D:\APP\gerenciador_horas\edesk_bot\*.py"; \
DestDir: "{app}\edesk_bot"; \
Flags: ignoreversion

; Os dados de execução são criados vazios no destino. Não distribua
; perfis autenticados, logs, capturas ou arquivos de diagnóstico locais.
[Dirs]
Name: "{app}\edesk_bot\perfil"; Permissions: users-modify
Name: "{app}\edesk_bot\logs"; Permissions: users-modify
Name: "{app}\edesk_bot\screenshots"; Permissions: users-modify

; ============================================================
; ATALHOS
; ============================================================

[Icons]

; Atalho no Menu Iniciar.
Name: "{autoprograms}\{#MyAppName}"; \
Filename: "{app}\{#MyAppExeName}"; \
IconFilename: "{app}\{#MyAppExeName}"

; Atalho opcional na Área de Trabalho.
Name: "{autodesktop}\{#MyAppName}"; \
Filename: "{app}\{#MyAppExeName}"; \
IconFilename: "{app}\{#MyAppExeName}"; \
Tasks: desktopicon

; ============================================================
; EXECUÇÃO APÓS A INSTALAÇÃO
; ============================================================

[Run]

; Em uma instalação manual, oferece abrir o aplicativo.
;
; Em uma futura atualização silenciosa usando /VERYSILENT,
; skipifsilent impede que esta seção abra o aplicativo
; automaticamente.
Filename: "{app}\{#MyAppExeName}"; \
Description: "{cm:LaunchProgram,{#DoubleAmp(MyAppName)}}"; \
Flags: nowait postinstall skipifsilent
