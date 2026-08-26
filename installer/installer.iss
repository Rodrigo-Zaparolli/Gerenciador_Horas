; ============================================================
; INSTALADOR - GERENCIADOR DE HORAS E PROJETOS
; ============================================================

#define MyAppName "Gerenciador de Horas e Projetos"
#define MyAppVersion "1.0.0"
#define MyAppPublisher "Rodrigo Zaparolli"
#define MyAppExeName "gerenciador_horas.exe"

[Setup]

; ------------------------------------------------------------
; Identificação do aplicativo
; ------------------------------------------------------------

AppId={{8D4E2F6A-9A5B-4D8F-B2E7-6C1A9F3D52B8}

AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}

; ------------------------------------------------------------
; Pasta de instalação
; ------------------------------------------------------------

DefaultDirName={autopf}\{#MyAppName}

DefaultGroupName={#MyAppName}

; ------------------------------------------------------------
; Arquivo do instalador
; ------------------------------------------------------------

OutputDir=.

OutputBaseFilename=Gerenciador_Horas_Projetos_v{#MyAppVersion}_Setup

Compression=lzma
SolidCompression=yes

; ------------------------------------------------------------
; Arquitetura
; ------------------------------------------------------------

ArchitecturesAllowed=x64
ArchitecturesInstallIn64BitMode=x64

; ------------------------------------------------------------
; Permissões
; ------------------------------------------------------------

PrivilegesRequired=admin

; ------------------------------------------------------------
; Interface
; ------------------------------------------------------------

WizardStyle=modern

DisableProgramGroupPage=yes

; ------------------------------------------------------------
; Ícone do aplicativo
; ------------------------------------------------------------

SetupIconFile=..\assets\images\Logo.png

UninstallDisplayIcon={app}\{#MyAppExeName}

; ------------------------------------------------------------
; Informações de desinstalação
; ------------------------------------------------------------

Uninstallable=yes

; ------------------------------------------------------------
; Atalhos
; ------------------------------------------------------------

Name: "{autoprograms}\{#MyAppName}"; \
    Filename: "{app}\{#MyAppExeName}"; \
    WorkingDir: "{app}"; \
    IconFilename: "{app}\{#MyAppExeName}"

Name: "{autodesktop}\{#MyAppName}"; \
    Filename: "{app}\{#MyAppExeName}"; \
    WorkingDir: "{app}"; \
    IconFilename: "{app}\{#MyAppExeName}"; \
    Tasks: desktopicon

; ------------------------------------------------------------
; Tarefas opcionais
; ------------------------------------------------------------

[Tasks]

Name: "desktopicon"; \
    Description: "Criar um atalho na Área de Trabalho"; \
    GroupDescription: "Atalhos adicionais:"

; ------------------------------------------------------------
; Arquivos do Flutter
; ------------------------------------------------------------

[Files]

Source: "..\build\windows\x64\runner\Release\*"; \
    DestDir: "{app}"; \
    Flags: ignoreversion recursesubdirs createallsubdirs

; ------------------------------------------------------------
; Execução após instalação
; ------------------------------------------------------------

[Run]

Filename: "{app}\{#MyAppExeName}"; \
    Description: "Executar {#MyAppName}"; \
    Flags: nowait postinstall skipifsilent

; ------------------------------------------------------------
; Atualização / instalação sobre versão anterior
; ------------------------------------------------------------

[UninstallDelete]

Type: filesandordirs; \
    Name: "{app}"