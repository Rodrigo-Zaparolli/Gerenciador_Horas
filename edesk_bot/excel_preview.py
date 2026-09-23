import sys
import json
import base64
import time
from pathlib import Path
from io import BytesIO

import pythoncom
import win32com.client
from PIL import ImageGrab


# ================================================================
# CONFIGURAÇÕES
# ================================================================

SHEET_NAME = "Dados"
RANGE_ADDRESS = "AG5:AL11"


# ================================================================
# LOG
# ================================================================

def log(msg):
    print(
        f"[ExcelPreview] {msg}",
        file=sys.stderr,
        flush=True,
    )


# ================================================================
# CAPTURA INTERVALO DO EXCEL
# ================================================================

def capturar_intervalo(worksheet):
    log(
        f"Capturando intervalo "
        f"{SHEET_NAME}!{RANGE_ADDRESS}"
    )

    intervalo = worksheet.Range(
        RANGE_ADDRESS
    )

    log(
        f"Intervalo encontrado: "
        f"{intervalo.Address}"
    )

    # ------------------------------------------------------------
    # COPIA COMO IMAGEM
    # ------------------------------------------------------------

    log("Executando CopyPicture...")

    intervalo.CopyPicture(
        Appearance=1,
        Format=2,
    )

    log("CopyPicture concluído.")

    # ------------------------------------------------------------
    # AGUARDA IMAGEM NO CLIPBOARD
    # ------------------------------------------------------------

    imagem = None

    for tentativa in range(30):

        time.sleep(0.2)

        try:

            imagem = ImageGrab.grabclipboard()

            if imagem is not None:

                log(
                    "Imagem encontrada no clipboard "
                    f"(tentativa {tentativa + 1})"
                )

                break

        except Exception as erro:

            log(
                "Erro clipboard "
                f"(tentativa {tentativa + 1}): "
                f"{erro}"
            )

    if imagem is None:

        raise Exception(
            "O Excel não colocou uma imagem "
            "no clipboard."
        )

    log(
        f"Imagem capturada: "
        f"{imagem.width}x{imagem.height}"
    )

    # ------------------------------------------------------------
    # DEBUG
    # ------------------------------------------------------------

    debug_dir = (
        Path(__file__).resolve().parent
        / "debug"
    )

    debug_dir.mkdir(
        parents=True,
        exist_ok=True,
    )

    debug_file = (
        debug_dir
        / "excel_preview.png"
    )

    imagem.save(
        debug_file,
        format="PNG",
    )

    log(
        f"Imagem DEBUG salva em: "
        f"{debug_file}"
    )

    # ------------------------------------------------------------
    # PNG
    # ------------------------------------------------------------

    buffer = BytesIO()

    imagem.save(
        buffer,
        format="PNG",
    )

    imagem_bytes = buffer.getvalue()

    log(
        f"PNG gerado: "
        f"{len(imagem_bytes)} bytes"
    )

    # ------------------------------------------------------------
    # BASE64
    # ------------------------------------------------------------

    imagem_base64 = base64.b64encode(
        imagem_bytes
    ).decode("utf-8")

    log(
        f"Base64 gerado: "
        f"{len(imagem_base64)} caracteres"
    )

    return imagem_base64


# ================================================================
# RESPOSTA JSON
# ================================================================

def enviar_resposta(dados):

    print(
        json.dumps(
            dados,
            ensure_ascii=False,
        ),
        flush=True,
    )


# ================================================================
# MAIN
# ================================================================

def main():

    pythoncom.CoInitialize()

    excel = None
    workbook = None
    worksheet = None

    try:

        log("ExcelPreview iniciado.")

        # ========================================================
        # LÊ COMANDOS CONTINUAMENTE
        # ========================================================

        for linha in sys.stdin:

            linha = linha.strip()

            if not linha:
                continue

            try:

                comando = json.loads(
                    linha
                )

            except Exception as erro:

                log(
                    f"JSON inválido: {erro}"
                )

                enviar_resposta({
                    "ok": False,
                    "erro": (
                        "JSON inválido: "
                        f"{erro}"
                    ),
                })

                continue

            acao = comando.get(
                "acao"
            )

            # ====================================================
            # ABRIR EXCEL
            # ====================================================

            if acao == "open":

                caminho_excel = comando.get(
                    "path"
                )

                if not caminho_excel:

                    raise Exception(
                        "Campo 'path' não informado."
                    )

                caminho = Path(
                    caminho_excel
                )

                if not caminho.exists():

                    raise FileNotFoundError(
                        "Arquivo Excel não encontrado: "
                        f"{caminho}"
                    )

                log(
                    f"Abrindo Excel: {caminho}"
                )

                # ------------------------------------------------
                # INICIA EXCEL
                # ------------------------------------------------

                excel = (
                    win32com.client.DispatchEx(
                        "Excel.Application"
                    )
                )

                excel.Visible = True
                excel.DisplayAlerts = False
                excel.ScreenUpdating = True
                excel.EnableEvents = False
                excel.UserControl = True

                log("Excel iniciado.")

                # ------------------------------------------------
                # ABRE WORKBOOK
                # ------------------------------------------------

                workbook = (
                    excel.Workbooks.Open(
                        str(caminho),
                        UpdateLinks=0,
                        ReadOnly=False,
                        AddToMru=False,
                    )
                )

                log(
                    "Arquivo aberto."
                )

                # ------------------------------------------------
                # ATIVA JANELA
                # ------------------------------------------------

                try:

                    janela = workbook.Windows(1)

                    janela.Visible = True
                    janela.Activate()

                    log(
                        "Janela do Workbook ativada."
                    )

                except Exception as erro:

                    log(
                        "Aviso ao ativar janela: "
                        f"{erro}"
                    )

                # ------------------------------------------------
                # ATIVA WORKBOOK
                # ------------------------------------------------

                try:

                    workbook.Activate()

                except Exception:

                    pass

                # ------------------------------------------------
                # PLANILHA
                # ------------------------------------------------

                worksheet = workbook.Worksheets(
                    SHEET_NAME
                )

                worksheet.Activate()

                log(
                    f"Aba ativada: "
                    f"{worksheet.Name}"
                )

                time.sleep(1)

                # ------------------------------------------------
                # PRIMEIRA CAPTURA
                # ------------------------------------------------

                imagem_base64 = (
                    capturar_intervalo(
                        worksheet
                    )
                )

                enviar_resposta({
                    "ok": True,
                    "acao": "open",
                    "imagemBase64": (
                        imagem_base64
                    ),
                    "sheet": SHEET_NAME,
                    "range": RANGE_ADDRESS,
                })

                log(
                    "Excel pronto para "
                    "atualizações."
                )

            # ====================================================
            # ATUALIZAR IMAGEM
            # ====================================================

            elif acao == "refresh":

                if workbook is None:
                    raise Exception(
                        "Workbook ainda não foi aberto."
                    )

                if worksheet is None:
                    raise Exception(
                        "Planilha ainda não foi aberta."
                    )

                log(
                    "Solicitada atualização "
                    "da imagem."
                )

                # ------------------------------------------------
                # ATUALIZA
                # ------------------------------------------------

                try:

                    workbook.Activate()

                except Exception:

                    pass

                try:

                    worksheet.Activate()

                except Exception:

                    pass

                time.sleep(0.2)

                imagem_base64 = (
                    capturar_intervalo(
                        worksheet
                    )
                )

                enviar_resposta({
                    "ok": True,
                    "acao": "refresh",
                    "imagemBase64": (
                        imagem_base64
                    ),
                    "sheet": SHEET_NAME,
                    "range": RANGE_ADDRESS,
                })

                log(
                    "Imagem atualizada."
                )

            # ====================================================
            # FECHAR
            # ====================================================

            elif acao == "close":

                log(
                    "Solicitado fechamento."
                )

                break

            # ====================================================
            # COMANDO DESCONHECIDO
            # ====================================================

            else:

                enviar_resposta({
                    "ok": False,
                    "erro": (
                        "Ação desconhecida: "
                        f"{acao}"
                    ),
                })

    except Exception as erro:

        log(
            f"ERRO: "
            f"{type(erro).__name__}: "
            f"{erro}"
        )

        enviar_resposta({
            "ok": False,
            "erro": str(erro),
        })

    finally:

        # ========================================================
        # FECHA WORKBOOK
        # ========================================================

        try:

            if workbook is not None:

                workbook.Close(
                    SaveChanges=False
                )

                log(
                    "Workbook fechado."
                )

        except Exception as erro:

            log(
                "Erro ao fechar workbook: "
                f"{erro}"
            )

        # ========================================================
        # FECHA EXCEL
        # ========================================================

        try:

            if excel is not None:

                excel.Quit()

                log(
                    "Excel encerrado."
                )

        except Exception as erro:

            log(
                "Erro ao encerrar Excel: "
                f"{erro}"
            )

        # ========================================================
        # FINALIZA COM
        # ========================================================

        try:

            pythoncom.CoUninitialize()

        except Exception:

            pass

        log(
            "ExcelPreview finalizado."
        )


# ================================================================
# EXECUÇÃO
# ================================================================

if __name__ == "__main__":
    main()