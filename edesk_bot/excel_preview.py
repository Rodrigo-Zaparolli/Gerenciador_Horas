import sys
import json
import base64
import re
import math

from datetime import datetime, date, time
from io import BytesIO
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

try:
    import openpyxl
    from openpyxl.styles.colors import COLOR_INDEX
    from openpyxl.utils import get_column_letter, range_boundaries
except ImportError:
    openpyxl = None


# ============================================================
# CONFIGURAÇÃO
# ============================================================

DEFAULT_SHEET = "Dados"
DEFAULT_RANGE = "AG5:AL11"

# Aumenta a resolução sem alterar a proporção da tabela.
SCALE = 1.35


# ============================================================
# LOG
# ============================================================

def log(msg):
    print(
        f"[ExcelPreview] {msg}",
        file=sys.stderr,
        flush=True,
    )


# ============================================================
# RESPOSTA PARA O FLUTTER
# ============================================================

def enviar_resposta(dados):
    print(
        json.dumps(
            dados,
            ensure_ascii=False,
        ),
        flush=True,
    )


# ============================================================
# REFERÊNCIA EXCEL
# ============================================================

def interpretar_referencia(referencia):

    texto = str(
        referencia or ""
    ).strip()

    if texto.startswith("="):
        texto = texto[1:]

    sheet = DEFAULT_SHEET
    endereco = texto or DEFAULT_RANGE

    if "!" in endereco:

        sheet, endereco = endereco.rsplit(
            "!",
            1,
        )

        sheet = (
            sheet
            .strip()
            .strip("'")
            .replace(
                "''",
                "'",
            )
        )

    endereco = (
        endereco
        .replace("$", "")
        .strip()
        .upper()
    )

    if not re.fullmatch(
        r"[A-Z]{1,3}\d+:[A-Z]{1,3}\d+",
        endereco,
    ):
        raise ValueError(
            f"Intervalo inválido: {referencia}"
        )

    return (
        sheet or DEFAULT_SHEET,
        endereco,
    )


# ============================================================
# COR
# ============================================================

def rgb_hex(
    valor,
    padrao,
):

    try:

        texto = (
            str(valor or "")
            .replace("#", "")
        )

        texto = texto[-6:]

        if len(texto) != 6:
            return padrao

        return (
            int(texto[0:2], 16),
            int(texto[2:4], 16),
            int(texto[4:6], 16),
        )

    except Exception:
        return padrao


def obter_cor(
    color,
    padrao=(255, 255, 255),
):

    if color is None:
        return padrao

    try:

        # ----------------------------------------------------
        # RGB
        # ----------------------------------------------------

        if (
            color.type == "rgb"
            and isinstance(
                color.rgb,
                str,
            )
        ):

            return rgb_hex(
                color.rgb,
                padrao,
            )

        # ----------------------------------------------------
        # INDEXED
        # ----------------------------------------------------

        if color.type == "indexed":

            indice = int(
                color.indexed
            )

            if (
                0
                <= indice
                < len(COLOR_INDEX)
            ):

                return rgb_hex(
                    COLOR_INDEX[indice],
                    padrao,
                )

        # ----------------------------------------------------
        # FALLBACK
        # ----------------------------------------------------

        valor = getattr(
            color,
            "rgb",
            None,
        )

        if isinstance(
            valor,
            str,
        ):

            return rgb_hex(
                valor,
                padrao,
            )

    except Exception:
        pass

    return padrao


# ============================================================
# FONTE
# ============================================================

def fonte_excel(cell):

    tamanho_excel = float(
        cell.font.sz or 11
    )

    tamanho = max(
        8,
        int(
            round(
                tamanho_excel
                * 96
                / 72
                * SCALE
            )
        ),
    )

    pasta = Path(
        r"C:\Windows\Fonts"
    )

    # --------------------------------------------------------
    # CALIBRI PRIMEIRO
    # --------------------------------------------------------

    if (
        cell.font.bold
        and cell.font.italic
    ):

        fontes = [
            "calibriz.ttf",
            "arialbi.ttf",
        ]

    elif cell.font.bold:

        fontes = [
            "calibrib.ttf",
            "arialbd.ttf",
            "segoeuib.ttf",
        ]

    elif cell.font.italic:

        fontes = [
            "calibrii.ttf",
            "ariali.ttf",
        ]

    else:

        fontes = [
            "calibri.ttf",
            "arial.ttf",
            "segoeui.ttf",
        ]

    for nome in fontes:

        arquivo = (
            pasta
            / nome
        )

        if arquivo.exists():

            try:

                return (
                    ImageFont
                    .truetype(
                        str(arquivo),
                        tamanho,
                    )
                )

            except Exception:
                pass

    return ImageFont.load_default()


# ============================================================
# LARGURA DAS COLUNAS
# ============================================================

def largura_coluna(
    worksheet,
    coluna,
):

    letra = get_column_letter(
        coluna
    )

    dimensao = (
        worksheet
        .column_dimensions[
            letra
        ]
    )

    if dimensao.hidden:
        return 0

    largura = (
        dimensao.width
    )

    if largura is None:
        largura = 8.43

    largura = float(
        largura
    )

    # --------------------------------------------------------
    # Conversão aproximada usada pelo Excel.
    # --------------------------------------------------------

    pixels = int(
        math.floor(
            (
                (
                    256
                    * largura
                )
                + math.floor(
                    128 / 7
                )
            )
            / 256
            * 7
        )
    )

    return max(
        1,
        int(
            round(
                pixels
                * SCALE
            )
        ),
    )


# ============================================================
# ALTURA DAS LINHAS
# ============================================================

def altura_linha(
    worksheet,
    linha,
):

    dimensao = (
        worksheet
        .row_dimensions[
            linha
        ]
    )

    if dimensao.hidden:
        return 0

    altura = (
        dimensao.height
    )

    if altura is None:

        altura = (
            worksheet
            .sheet_format
            .defaultRowHeight
            or 15
        )

    return max(
        1,
        int(
            round(
                float(altura)
                * 96
                / 72
                * SCALE
            )
        ),
    )


# ============================================================
# CASAS DECIMAIS DE PERCENTUAL
# ============================================================

def casas_percentual(
    formato,
):

    antes = (
        formato
        .split(
            "%",
            1,
        )[0]
    )

    if "." not in antes:
        return 0

    decimal = (
        antes
        .rsplit(
            ".",
            1,
        )[1]
    )

    return sum(
        1
        for caractere in decimal
        if caractere in "0#"
    )


# ============================================================
# TEXTO DA CÉLULA
# ============================================================

def texto_celula(
    cell,
):

    valor = cell.value

    if valor is None:
        return ""

    # ========================================================
    # DATA + HORA
    # ========================================================

    if isinstance(
        valor,
        datetime,
    ):

        formato = str(
            cell.number_format
            or ""
        ).lower()

        tem_data = any(
            item in formato
            for item in (
                "d",
                "y",
            )
        )

        tem_hora = any(
            item in formato
            for item in (
                "h:",
                "hh",
                ":mm",
                ":ss",
            )
        )

        if (
            tem_data
            and tem_hora
        ):

            return valor.strftime(
                "%d/%m/%Y %H:%M"
            )

        if (
            tem_hora
            and not tem_data
        ):

            return valor.strftime(
                "%H:%M"
            )

        # ----------------------------------------------------
        # CORREÇÃO PRINCIPAL DAS DATAS
        # ----------------------------------------------------

        return valor.strftime(
            "%d/%m/%Y"
        )

    # ========================================================
    # DATA
    # ========================================================

    if isinstance(
        valor,
        date,
    ):

        return valor.strftime(
            "%d/%m/%Y"
        )

    # ========================================================
    # HORA
    # ========================================================

    if isinstance(
        valor,
        time,
    ):

        return valor.strftime(
            "%H:%M"
        )

    # ========================================================
    # BOOLEAN
    # ========================================================

    if isinstance(
        valor,
        bool,
    ):

        return (
            "VERDADEIRO"
            if valor
            else "FALSO"
        )

    # ========================================================
    # NÚMEROS
    # ========================================================

    if isinstance(
        valor,
        (
            int,
            float,
        ),
    ):

        formato = str(
            cell.number_format
            or ""
        )

        # ----------------------------------------------------
        # PERCENTUAL
        # ----------------------------------------------------

        if "%" in formato:

            casas = (
                casas_percentual(
                    formato
                )
            )

            texto = (
                f"{valor * 100:.{casas}f}%"
            )

            return texto.replace(
                ".",
                ",",
            )

        # ----------------------------------------------------
        # INTEIRO
        # ----------------------------------------------------

        if (
            isinstance(
                valor,
                float,
            )
            and valor.is_integer()
        ):

            return str(
                int(valor)
            )

        return str(
            valor
        ).replace(
            ".",
            ",",
        )

    return str(
        valor
    )


# ============================================================
# MESCLAGENS
# ============================================================

def mapa_mesclagens(
    worksheet,
    min_col,
    min_row,
    max_col,
    max_row,
):

    resultado = {}

    for faixa in (
        worksheet
        .merged_cells
        .ranges
    ):

        # ----------------------------------------------------
        # Ignora mesclagens fora do intervalo.
        # ----------------------------------------------------

        if (
            faixa.max_col
            < min_col
            or faixa.min_col
            > max_col
            or faixa.max_row
            < min_row
            or faixa.min_row
            > max_row
        ):
            continue

        ancora = (
            faixa.min_row,
            faixa.min_col,
        )

        for linha in range(
            faixa.min_row,
            faixa.max_row + 1,
        ):

            for coluna in range(
                faixa.min_col,
                faixa.max_col + 1,
            ):

                resultado[
                    (
                        linha,
                        coluna,
                    )
                ] = (
                    ancora,
                    faixa.min_col,
                    faixa.min_row,
                    faixa.max_col,
                    faixa.max_row,
                )

    return resultado


# ============================================================
# FORMATAÇÃO CONDICIONAL
# DATA BAR
# ============================================================

def valor_cfvo(
    objeto,
    valores,
    minimo,
):

    tipo = str(
        getattr(
            objeto,
            "type",
            "",
        )
        or ""
    ).lower()

    bruto = getattr(
        objeto,
        "val",
        None,
    )

    valor_minimo = min(
        valores
    )

    valor_maximo = max(
        valores
    )

    if tipo in (
        "min",
        "minnum",
    ):
        return valor_minimo

    if tipo in (
        "max",
        "maxnum",
    ):
        return valor_maximo

    try:

        numero = float(
            bruto
        )

    except Exception:

        return (
            valor_minimo
            if minimo
            else valor_maximo
        )

    # --------------------------------------------------------
    # PERCENTUAL DO INTERVALO
    # --------------------------------------------------------

    if tipo == "percent":

        return (
            valor_minimo
            + (
                valor_maximo
                - valor_minimo
            )
            * numero
            / 100
        )

    return numero


def coletar_data_bars(
    worksheet,
):

    resultado = {}

    try:

        formatacoes = (
            worksheet
            .conditional_formatting
        )

    except Exception:

        return resultado

    # ========================================================
    # PERCORRE AS REGRAS
    # ========================================================

    for item in formatacoes:

        try:

            faixas = list(
                item.sqref.ranges
            )

            regras = (
                item.rules
            )

        except Exception:

            continue

        for regra in regras:

            if str(
                getattr(
                    regra,
                    "type",
                    "",
                )
            ) != "dataBar":

                continue

            data_bar = getattr(
                regra,
                "dataBar",
                None,
            )

            if data_bar is None:
                continue

            cor = obter_cor(
                getattr(
                    data_bar,
                    "color",
                    None,
                ),
                (
                    99,
                    190,
                    123,
                ),
            )

            mostrar_valor = (
                getattr(
                    data_bar,
                    "showValue",
                    None,
                )
                is not False
            )

            # =================================================
            # FAIXAS DA REGRA
            # =================================================

            for faixa in faixas:

                (
                    min_col,
                    min_row,
                    max_col,
                    max_row,
                ) = range_boundaries(
                    str(faixa)
                )

                valores = []

                for linha in range(
                    min_row,
                    max_row + 1,
                ):

                    for coluna in range(
                        min_col,
                        max_col + 1,
                    ):

                        valor = (
                            worksheet
                            .cell(
                                row=linha,
                                column=coluna,
                            )
                            .value
                        )

                        if (
                            isinstance(
                                valor,
                                (
                                    int,
                                    float,
                                ),
                            )
                            and not isinstance(
                                valor,
                                bool,
                            )
                        ):

                            valores.append(
                                float(valor)
                            )

                if not valores:
                    continue

                cfvo = list(
                    getattr(
                        data_bar,
                        "cfvo",
                        [],
                    )
                    or []
                )

                if len(cfvo) >= 2:

                    minimo = valor_cfvo(
                        cfvo[0],
                        valores,
                        True,
                    )

                    maximo = valor_cfvo(
                        cfvo[1],
                        valores,
                        False,
                    )

                else:

                    minimo = min(
                        valores
                    )

                    maximo = max(
                        valores
                    )

                # ------------------------------------------------
                # Percentuais positivos começam visualmente em 0.
                # ------------------------------------------------

                if minimo > 0:
                    minimo = 0.0

                amplitude = (
                    maximo
                    - minimo
                )

                if abs(
                    amplitude
                ) < 0.0000001:

                    amplitude = 1.0

                # =================================================
                # GUARDA A BARRA DE CADA CÉLULA
                # =================================================

                for linha in range(
                    min_row,
                    max_row + 1,
                ):

                    for coluna in range(
                        min_col,
                        max_col + 1,
                    ):

                        cell = (
                            worksheet
                            .cell(
                                row=linha,
                                column=coluna,
                            )
                        )

                        valor = (
                            cell.value
                        )

                        if not isinstance(
                            valor,
                            (
                                int,
                                float,
                            ),
                        ):

                            continue

                        if isinstance(
                            valor,
                            bool,
                        ):

                            continue

                        proporcao = (
                            (
                                float(valor)
                                - minimo
                            )
                            / amplitude
                        )

                        proporcao = max(
                            0.0,
                            min(
                                1.0,
                                proporcao,
                            ),
                        )

                        resultado[
                            (
                                linha,
                                coluna,
                            )
                        ] = {
                            "ratio": proporcao,
                            "color": cor,
                            "show": mostrar_valor,
                        }

    return resultado


# ============================================================
# BORDAS
# ============================================================

def espessura_borda(
    estilo,
):

    if not estilo:
        return 0

    estilo = str(
        estilo
    )

    if estilo in (
        "thick",
        "double",
    ):

        return max(
            3,
            int(
                round(
                    3
                    * SCALE
                )
            ),
        )

    if estilo.startswith(
        "medium"
    ):

        return max(
            2,
            int(
                round(
                    2
                    * SCALE
                )
            ),
        )

    return max(
        1,
        int(
            round(
                SCALE
            )
        ),
    )


def desenhar_borda(
    draw,
    coordenadas,
    lado,
):

    if (
        lado is None
        or not lado.style
    ):
        return

    cor = obter_cor(
        lado.color,
        (
            0,
            0,
            0,
        ),
    )

    draw.line(
        coordenadas,
        fill=cor,
        width=espessura_borda(
            lado.style
        ),
    )


# ============================================================
# TEXTO
# ============================================================

def desenhar_texto(
    draw,
    cell,
    texto,
    retangulo,
):

    if not texto:
        return

    (
        x0,
        y0,
        x1,
        y1,
    ) = retangulo

    fonte = fonte_excel(
        cell
    )

    cor = obter_cor(
        cell.font.color,
        (
            0,
            0,
            0,
        ),
    )

    bbox = draw.textbbox(
        (
            0,
            0,
        ),
        texto,
        font=fonte,
    )

    largura_texto = (
        bbox[2]
        - bbox[0]
    )

    altura_texto = (
        bbox[3]
        - bbox[1]
    )

    horizontal = str(
        cell.alignment.horizontal
        or "general"
    ).lower()

    vertical = str(
        cell.alignment.vertical
        or "bottom"
    ).lower()

    # ========================================================
    # GENERAL DO EXCEL
    # ========================================================

    if horizontal == "general":

        if (
            isinstance(
                cell.value,
                (
                    int,
                    float,
                    datetime,
                    date,
                    time,
                ),
            )
            and not isinstance(
                cell.value,
                bool,
            )
        ):

            horizontal = "right"

        else:

            horizontal = "left"

    margem = max(
        3,
        int(
            round(
                4
                * SCALE
            )
        ),
    )

    # ========================================================
    # HORIZONTAL
    # ========================================================

    if horizontal in (
        "center",
        "centercontinuous",
        "distributed",
    ):

        tx = (
            x0
            + (
                (
                    x1
                    - x0
                )
                - largura_texto
            )
            // 2
        )

    elif horizontal == "right":

        tx = (
            x1
            - largura_texto
            - margem
        )

    else:

        tx = (
            x0
            + margem
        )

    # ========================================================
    # VERTICAL
    # ========================================================

    if vertical == "center":

        ty = (
            y0
            + (
                (
                    y1
                    - y0
                )
                - altura_texto
            )
            // 2
            - bbox[1]
        )

    elif vertical == "top":

        ty = (
            y0
            + margem
            - bbox[1]
        )

    else:

        ty = (
            y1
            - altura_texto
            - margem
            - bbox[1]
        )

    draw.text(
        (
            max(
                x0 + 1,
                tx,
            ),
            max(
                y0 + 1,
                ty,
            ),
        ),
        texto,
        font=fonte,
        fill=cor,
    )


# ============================================================
# RENDERIZA INTERVALO
# ============================================================

def renderizar_intervalo(
    caminho,
    nome_aba,
    endereco,
):

    if openpyxl is None:

        raise RuntimeError(
            "Biblioteca openpyxl não instalada. "
            "Execute: py -m pip install openpyxl pillow"
        )

    log(
        "Abrindo XLSM com openpyxl..."
    )

    # ========================================================
    # ABRE XLSM
    # ========================================================

    workbook = (
        openpyxl
        .load_workbook(
            caminho,
            data_only=True,
            read_only=False,
            keep_vba=True,
        )
    )

    try:

        # ====================================================
        # LOCALIZA PLANILHA
        # ====================================================

        worksheet = None

        for aba in (
            workbook
            .worksheets
        ):

            if (
                aba.title.casefold()
                ==
                nome_aba.casefold()
            ):

                worksheet = aba
                break

        if worksheet is None:

            raise RuntimeError(
                f"Aba '{nome_aba}' não encontrada."
            )

        # ====================================================
        # INTERVALO
        # ====================================================

        (
            min_col,
            min_row,
            max_col,
            max_row,
        ) = range_boundaries(
            endereco
        )

        log(
            "Intervalo: "
            f"{worksheet.title}!"
            f"{endereco}"
        )

        # ====================================================
        # DIMENSÕES
        # ====================================================

        larguras = []

        for coluna in range(
            min_col,
            max_col + 1,
        ):

            larguras.append(
                largura_coluna(
                    worksheet,
                    coluna,
                )
            )

        alturas = []

        for linha in range(
            min_row,
            max_row + 1,
        ):

            alturas.append(
                altura_linha(
                    worksheet,
                    linha,
                )
            )

        # ====================================================
        # POSIÇÕES
        # ====================================================

        pos_x = [0]

        for largura in larguras:

            pos_x.append(
                pos_x[-1]
                + largura
            )

        pos_y = [0]

        for altura in alturas:

            pos_y.append(
                pos_y[-1]
                + altura
            )

        largura_total = max(
            1,
            pos_x[-1],
        )

        altura_total = max(
            1,
            pos_y[-1],
        )

        log(
            "Imagem: "
            f"{largura_total}x"
            f"{altura_total}"
        )

        # ====================================================
        # IMAGEM
        # ====================================================

        imagem = Image.new(
            "RGB",
            (
                largura_total,
                altura_total,
            ),
            "white",
        )

        draw = ImageDraw.Draw(
            imagem
        )

        # ====================================================
        # MESCLAGENS
        # ====================================================

        mesclagens = (
            mapa_mesclagens(
                worksheet,
                min_col,
                min_row,
                max_col,
                max_row,
            )
        )

        # ====================================================
        # DATA BARS
        # ====================================================

        data_bars = (
            coletar_data_bars(
                worksheet
            )
        )

        log(
            "Data bars encontradas: "
            f"{len(data_bars)}"
        )

        # ====================================================
        # DESENHA CÉLULAS
        # ====================================================

        for linha in range(
            min_row,
            max_row + 1,
        ):

            for coluna in range(
                min_col,
                max_col + 1,
            ):

                merge = (
                    mesclagens
                    .get(
                        (
                            linha,
                            coluna,
                        )
                    )
                )

                # =============================================
                # MESCLADA
                # =============================================

                if merge:

                    (
                        ancora,
                        merge_min_col,
                        merge_min_row,
                        merge_max_col,
                        merge_max_row,
                    ) = merge

                    # -----------------------------------------
                    # Só desenha a célula âncora.
                    # -----------------------------------------

                    if (
                        linha,
                        coluna,
                    ) != ancora:

                        continue

                    cell = (
                        worksheet
                        .cell(
                            row=merge_min_row,
                            column=merge_min_col,
                        )
                    )

                    col_inicio = max(
                        merge_min_col,
                        min_col,
                    )

                    linha_inicio = max(
                        merge_min_row,
                        min_row,
                    )

                    col_fim = min(
                        merge_max_col,
                        max_col,
                    )

                    linha_fim = min(
                        merge_max_row,
                        max_row,
                    )

                    x0 = pos_x[
                        col_inicio
                        - min_col
                    ]

                    y0 = pos_y[
                        linha_inicio
                        - min_row
                    ]

                    x1 = pos_x[
                        col_fim
                        - min_col
                        + 1
                    ]

                    y1 = pos_y[
                        linha_fim
                        - min_row
                        + 1
                    ]

                # =============================================
                # NORMAL
                # =============================================

                else:

                    cell = (
                        worksheet
                        .cell(
                            row=linha,
                            column=coluna,
                        )
                    )

                    x0 = pos_x[
                        coluna
                        - min_col
                    ]

                    y0 = pos_y[
                        linha
                        - min_row
                    ]

                    x1 = pos_x[
                        coluna
                        - min_col
                        + 1
                    ]

                    y1 = pos_y[
                        linha
                        - min_row
                        + 1
                    ]

                # =============================================
                # FUNDO
                # =============================================

                fundo = (
                    255,
                    255,
                    255,
                )

                try:

                    if (
                        cell.fill
                        and
                        cell.fill.fill_type
                    ):

                        fundo = obter_cor(
                            cell.fill.fgColor,
                            fundo,
                        )

                except Exception:
                    pass

                draw.rectangle(
                    (
                        x0,
                        y0,
                        x1,
                        y1,
                    ),
                    fill=fundo,
                )

                # =============================================
                # DATA BAR
                # =============================================

                barra = (
                    data_bars
                    .get(
                        (
                            cell.row,
                            cell.column,
                        )
                    )
                )

                if (
                    barra
                    and barra[
                        "ratio"
                    ] > 0
                ):

                    margem_barra = max(
                        1,
                        int(
                            round(
                                2
                                * SCALE
                            )
                        ),
                    )

                    largura_util = max(
                        0,
                        (
                            x1
                            - x0
                            - (
                                margem_barra
                                * 2
                            )
                        ),
                    )

                    largura_barra = int(
                        round(
                            largura_util
                            * barra[
                                "ratio"
                            ]
                        )
                    )

                    cor_barra = (
                        barra[
                            "color"
                        ]
                    )

                    # -----------------------------------------
                    # Interior mais claro, semelhante ao Excel.
                    # -----------------------------------------

                    cor_clara = tuple(
                        int(
                            round(
                                componente
                                + (
                                    255
                                    - componente
                                )
                                * 0.68
                            )
                        )
                        for componente
                        in cor_barra
                    )

                    if largura_barra > 0:

                        draw.rectangle(
                            (
                                x0
                                + margem_barra,

                                y0
                                + margem_barra,

                                x0
                                + margem_barra
                                + largura_barra,

                                y1
                                - margem_barra,
                            ),
                            fill=cor_clara,
                            outline=cor_barra,
                            width=max(
                                1,
                                int(
                                    round(
                                        SCALE
                                    )
                                ),
                            ),
                        )

                # =============================================
                # TEXTO
                # =============================================

                texto = (
                    texto_celula(
                        cell
                    )
                )

                if (
                    not barra
                    or barra[
                        "show"
                    ]
                ):

                    desenhar_texto(
                        draw,
                        cell,
                        texto,
                        (
                            x0,
                            y0,
                            x1,
                            y1,
                        ),
                    )

                # =============================================
                # BORDAS
                # =============================================

                desenhar_borda(
                    draw,
                    (
                        x0,
                        y0,
                        x0,
                        y1,
                    ),
                    cell.border.left,
                )

                desenhar_borda(
                    draw,
                    (
                        x0,
                        y0,
                        x1,
                        y0,
                    ),
                    cell.border.top,
                )

                desenhar_borda(
                    draw,
                    (
                        x1 - 1,
                        y0,
                        x1 - 1,
                        y1,
                    ),
                    cell.border.right,
                )

                desenhar_borda(
                    draw,
                    (
                        x0,
                        y1 - 1,
                        x1,
                        y1 - 1,
                    ),
                    cell.border.bottom,
                )

        # ====================================================
        # PNG
        # ====================================================

        buffer = BytesIO()

        imagem.save(
            buffer,
            format="PNG",
        )

        png = (
            buffer
            .getvalue()
        )

        # ====================================================
        # DEBUG
        # ====================================================

        debug_dir = (
            Path(__file__)
            .resolve()
            .parent
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

        debug_file.write_bytes(
            png
        )

        log(
            "PNG DEBUG salvo em: "
            f"{debug_file}"
        )

        log(
            "PNG gerado: "
            f"{len(png)} bytes"
        )

        # ====================================================
        # BASE64
        # ====================================================

        imagem_base64 = (
            base64
            .b64encode(
                png
            )
            .decode(
                "utf-8"
            )
        )

        return (
            imagem_base64,
            worksheet.title,
        )

    finally:

        workbook.close()


# ============================================================
# MAIN
# ============================================================

def main():

    log(
        "ExcelPreview iniciado - "
        "OPENPYXL/PILLOW CORRIGIDO."
    )

    caminho_atual = None
    sheet_atual = DEFAULT_SHEET
    range_atual = DEFAULT_RANGE

    for linha in sys.stdin:

        linha = linha.strip()

        if not linha:
            continue

        try:

            comando = json.loads(
                linha
            )

            acao = str(
                comando.get(
                    "acao",
                    "",
                )
            ).lower()

            # =================================================
            # CLOSE
            # =================================================

            if acao == "close":

                enviar_resposta({
                    "ok": True,
                    "acao": "close",
                })

                break

            # =================================================
            # OPEN
            # =================================================

            if acao == "open":

                caminho_atual = Path(
                    str(
                        comando.get(
                            "path"
                        )
                        or ""
                    )
                )

                if not caminho_atual.exists():

                    raise FileNotFoundError(
                        "Arquivo não encontrado: "
                        f"{caminho_atual}"
                    )

            # =================================================
            # VALIDA AÇÃO
            # =================================================

            if acao not in (
                "open",
                "refresh",
            ):

                enviar_resposta({
                    "ok": False,
                    "erro": (
                        "Ação desconhecida: "
                        f"{acao}"
                    ),
                })

                continue

            if caminho_atual is None:

                raise RuntimeError(
                    "Arquivo ainda não foi aberto."
                )

            # =================================================
            # REFERÊNCIA
            # =================================================

            referencia = (
                comando.get(
                    "intervalo"
                )
                or comando.get(
                    "range"
                )
                or comando.get(
                    "rangeAddress"
                )
            )

            if referencia:

                (
                    sheet_atual,
                    range_atual,
                ) = interpretar_referencia(
                    referencia
                )

            log(
                "Arquivo: "
                f"{caminho_atual}"
            )

            log(
                "Intervalo: "
                f"{sheet_atual}!"
                f"{range_atual}"
            )

            # =================================================
            # RENDERIZA
            # =================================================

            (
                imagem_base64,
                nome_real_aba,
            ) = renderizar_intervalo(
                caminho_atual,
                sheet_atual,
                range_atual,
            )

            sheet_atual = (
                nome_real_aba
            )

            # =================================================
            # RETORNO PARA FLUTTER
            # =================================================

            enviar_resposta({
                "ok": True,
                "acao": acao,
                "imagemBase64": (
                    imagem_base64
                ),
                "sheet": (
                    sheet_atual
                ),
                "range": (
                    range_atual
                ),
            })

            log(
                "Preview gerado com sucesso."
            )

        except Exception as erro:

            log(
                "ERRO: "
                f"{type(erro).__name__}: "
                f"{erro}"
            )

            enviar_resposta({
                "ok": False,
                "erro": str(
                    erro
                ),
            })

    log(
        "ExcelPreview finalizado."
    )


# ============================================================
# EXECUÇÃO
# ============================================================

if __name__ == "__main__":
    main()