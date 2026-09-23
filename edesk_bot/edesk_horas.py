import sys
import json
import time
import html
import re
import os

from pathlib import Path
from urllib.parse import (
    urlparse,
    parse_qs,
    unquote,
    urlencode,
)

from playwright.sync_api import sync_playwright

from config import (
    PROFILE_DIR,
    SCREENSHOTS_DIR,
    LOGS_DIR,
)


# ================================================================
# CAMINHOS
# ================================================================

BASE_DIR = Path(__file__).resolve().parent

PROFILE_PATH = BASE_DIR / PROFILE_DIR
SCREENSHOTS_PATH = BASE_DIR / SCREENSHOTS_DIR
LOGS_PATH = BASE_DIR / LOGS_DIR

PROFILE_PATH.mkdir(
    parents=True,
    exist_ok=True,
)

SCREENSHOTS_PATH.mkdir(
    parents=True,
    exist_ok=True,
)

LOGS_PATH.mkdir(
    parents=True,
    exist_ok=True,
)


# ================================================================
# LOG
# ================================================================

def log(mensagem):

    print(
        f"[E-Desk][Horas] {mensagem}",
        flush=True,
    )


# ================================================================
# REQUEST
# ================================================================

def carregar_request():

    if len(sys.argv) < 2:

        raise RuntimeError(
            "Nenhum arquivo request.json foi informado."
        )

    request_path = Path(
        sys.argv[1]
    )

    log(
        f"Request recebido: {request_path}"
    )

    if not request_path.exists():

        raise RuntimeError(
            f"Request não encontrado: {request_path}"
        )

    with request_path.open(
        "r",
        encoding="utf-8",
    ) as arquivo:

        dados = json.load(
            arquivo
        )

    # ============================================================
    # DIAGNÓSTICO DO REQUEST
    # ============================================================

    log("")
    log(
        "============================================================"
    )
    log(
        "CONTEÚDO COMPLETO DO REQUEST.JSON"
    )
    log(
        "============================================================"
    )

    try:

        log(
            json.dumps(
                dados,
                ensure_ascii=False,
                indent=2,
            )
        )

    except Exception as erro:

        log(
            f"Não foi possível exibir o JSON formatado: {erro}"
        )

        log(
            str(dados)
        )

    log(
        "============================================================"
    )

    # ============================================================
    # DIAGNÓSTICO DAS HORAS
    #
    # Novo formato:
    #
    # trabalhos:
    #   - solicitacao
    #   - idTrabalho
    #   - horas
    #
    # Também mantém compatibilidade com:
    #
    # horas:
    #   [...]
    # ============================================================

    trabalhos = dados.get(
        "trabalhos",
        [],
    )

    if isinstance(
        trabalhos,
        list,
    ) and trabalhos:

        log("")
        log(
            "============================================================"
        )
        log(
            "DADOS DE TRABALHOS RECEBIDOS"
        )
        log(
            "============================================================"
        )

        log(
            f"Quantidade de trabalhos: {len(trabalhos)}"
        )

        for indice_trabalho, trabalho in enumerate(
            trabalhos,
            start=1,
        ):

            log("")
            log(
                f"================ TRABALHO {indice_trabalho} ================"
            )

            if not isinstance(
                trabalho,
                dict,
            ):

                log(
                    f"Registro inválido: {trabalho}"
                )

                continue

            solicitacao = str(
                trabalho.get(
                    "solicitacao",
                    "",
                )
                or ""
            ).strip()

            id_trabalho = str(
                trabalho.get(
                    "idTrabalho",
                    trabalho.get(
                        "id_trabalho",
                        "",
                    ),
                )
                or ""
            ).strip()

            horas_trabalho = trabalho.get(
                "horas",
                [],
            )

            if not isinstance(
                horas_trabalho,
                list,
            ):

                horas_trabalho = []

            log(
                f"SOLICITAÇÃO: {solicitacao or '[NÃO INFORMADA]'}"
            )

            log(
                f"ID TRABALHO: {id_trabalho or '[NÃO INFORMADO]'}"
            )

            log(
                f"Quantidade de horas: {len(horas_trabalho)}"
            )

            for indice_hora, hora in enumerate(
                horas_trabalho,
                start=1,
            ):

                log("")
                log(
                    f"---------------- HORA {indice_hora} ----------------"
                )

                if not isinstance(
                    hora,
                    dict,
                ):

                    log(
                        f"Registro inválido: {hora}"
                    )

                    continue

                try:

                    log(
                        json.dumps(
                            hora,
                            ensure_ascii=False,
                            indent=2,
                        )
                    )

                except Exception:

                    log(
                        str(hora)
                    )

                descritivo = obter_descritivo_hora(
                    hora
                )

                if descritivo:

                    log(
                        f"DESCRITIVO: {descritivo}"
                    )

                else:

                    log(
                        "DESCRITIVO: NÃO INFORMADO"
                    )

        log(
            "============================================================"
        )
        log("")

    else:

        # ========================================================
        # COMPATIBILIDADE COM REQUEST ANTIGO
        # ========================================================

        horas = dados.get(
            "horas",
            [],
        )

        log("")
        log(
            "============================================================"
        )
        log(
            "DADOS DE HORAS RECEBIDOS"
        )
        log(
            "============================================================"
        )

        log(
            f"Tipo de 'horas': {type(horas).__name__}"
        )

        if isinstance(
            horas,
            list,
        ):

            log(
                f"Quantidade de registros em 'horas': {len(horas)}"
            )

            for indice, hora in enumerate(
                horas,
                start=1,
            ):

                log("")
                log(
                    f"---------------- HORA {indice} ----------------"
                )

                log(
                    f"Tipo do registro: {type(hora).__name__}"
                )

                try:

                    log(
                        json.dumps(
                            hora,
                            ensure_ascii=False,
                            indent=2,
                        )
                    )

                except Exception:

                    log(
                        str(hora)
                    )

                if isinstance(
                    hora,
                    dict,
                ):

                    descritivo = obter_descritivo_hora(
                        hora
                    )

                    if descritivo:

                        log(
                            f"DESCRITIVO: {descritivo}"
                        )

                    else:

                        log(
                            "DESCRITIVO: NÃO INFORMADO"
                        )

        else:

            log(
                "O campo 'horas' NÃO é uma lista."
            )

            log(
                f"Valor recebido: {horas}"
            )

        log(
            "============================================================"
        )
        log("")

    return dados


# ================================================================
# DADOS DO REQUEST
# ================================================================

def obter_url(dados):

    url = str(
        dados.get(
            "url",
            "",
        )
    ).strip()

    if not url:

        raise RuntimeError(
            "A URL do E-Desk não foi informada."
        )

    return url


def extrair_id_trabalho(dados):

    return str(
        dados.get(
            "idTrabalho",
            "",
        )
    ).strip()


def extrair_solicitacao(dados):

    return str(
        dados.get(
            "solicitacao",
            "",
        )
    ).strip()


def extrair_horas(dados):

    horas = dados.get(
        "horas",
        [],
    )

    if not isinstance(
        horas,
        list,
    ):

        return []

    return horas


# ================================================================
# EXTRAIR TRABALHOS
#
# NOVO FORMATO:
#
# {
#   "trabalhos": [
#       {
#           "solicitacao": "2262412",
#           "idTrabalho": "18",
#           "horas": [...]
#       },
#       {
#           "solicitacao": "2261914",
#           "idTrabalho": "7",
#           "horas": [...]
#       }
#   ]
# }
#
# IMPORTANTE:
#
# O ID relativo do trabalho somente é único dentro da solicitação.
#
# Portanto:
#
# 2262412 + 18
#
# é diferente de:
#
# 2261914 + 18
# ================================================================

def extrair_trabalhos(dados):

    trabalhos = dados.get(
        "trabalhos",
        [],
    )

    # ============================================================
    # NOVO FORMATO
    # ============================================================

    if isinstance(
        trabalhos,
        list,
    ) and trabalhos:

        resultado = []

        for trabalho in trabalhos:

            if not isinstance(
                trabalho,
                dict,
            ):

                continue

            solicitacao = str(
                trabalho.get(
                    "solicitacao",
                    "",
                )
                or ""
            ).strip()

            id_trabalho = str(
                trabalho.get(
                    "idTrabalho",
                    trabalho.get(
                        "id_trabalho",
                        "",
                    ),
                )
                or ""
            ).strip()

            horas = trabalho.get(
                "horas",
                [],
            )

            if not isinstance(
                horas,
                list,
            ):

                horas = []

            resultado.append(
                {
                    "solicitacao": solicitacao,
                    "id_trabalho": id_trabalho,
                    "horas": horas,
                }
            )

        return resultado

    # ============================================================
    # COMPATIBILIDADE COM FORMATO ANTIGO
    # ============================================================

    solicitacao = extrair_solicitacao(
        dados
    )

    id_trabalho = extrair_id_trabalho(
        dados
    )

    horas = extrair_horas(
        dados
    )

    if solicitacao and id_trabalho:

        return [
            {
                "solicitacao": solicitacao,
                "id_trabalho": id_trabalho,
                "horas": horas,
            }
        ]

    return []


# ================================================================
# DESCRITIVO DA HORA
# ================================================================

def obter_descritivo_hora(hora):

    if not isinstance(
        hora,
        dict,
    ):

        return ""

    campos = [
        "descritivo",
        "descricao",
        "descrição",
        "description",
        "atividade",
        "motivo",
        "observacao",
        "observação",
    ]

    for campo in campos:

        valor = hora.get(
            campo,
            "",
        )

        if valor is None:

            continue

        valor = str(
            valor
        ).strip()

        if valor:

            return valor

    return ""


# ================================================================
# LIMPAR DESCRITIVO
# ================================================================

def limpar_descritivo_hora(
    descritivo,
    data,
):

    descritivo = str(
        descritivo or ""
    ).strip()

    data = str(
        data or ""
    ).strip()

    if not descritivo:

        return ""

    # ------------------------------------------------------------
    # Remove um "-" inicial.
    # ------------------------------------------------------------

    descritivo = re.sub(
        r"^\s*-\s*",
        "",
        descritivo,
    ).strip()

    # ------------------------------------------------------------
    # Remove a data recebida no início.
    # ------------------------------------------------------------

    if data:

        padrao_data = re.escape(
            data
        )

        descritivo = re.sub(
            rf"^\s*{padrao_data}\s*:?\s*-?\s*",
            "",
            descritivo,
            count=1,
        ).strip()

    # ------------------------------------------------------------
    # Remove qualquer data DD/MM/AAAA no início.
    # ------------------------------------------------------------

    descritivo = re.sub(
        r"^\s*\d{2}/\d{2}/\d{4}\s*:?\s*-?\s*",
        "",
        descritivo,
        count=1,
    ).strip()

    return descritivo


# ================================================================
# DATA DA HORA
# ================================================================

def obter_data_hora(hora):

    if not isinstance(
        hora,
        dict,
    ):

        return ""

    campos = [
        "data",
        "date",
        "dt",
    ]

    for campo in campos:

        valor = hora.get(
            campo,
            "",
        )

        if valor is None:

            continue

        valor = str(
            valor
        ).strip()

        if valor:

            return valor

    return ""


# ================================================================
# INÍCIO DA HORA
# ================================================================

def obter_inicio_hora(hora):

    if not isinstance(
        hora,
        dict,
    ):

        return ""

    campos = [
        "inicio",
        "início",
        "horaInicio",
        "hora_inicio",
        "start",
    ]

    for campo in campos:

        valor = hora.get(
            campo,
            "",
        )

        if valor is None:

            continue

        valor = str(
            valor
        ).strip()

        if valor:

            return valor

    return ""


# ================================================================
# FIM DA HORA
# ================================================================

def obter_fim_hora(hora):

    if not isinstance(
        hora,
        dict,
    ):

        return ""

    campos = [
        "fim",
        "horaFim",
        "hora_fim",
        "end",
    ]

    for campo in campos:

        valor = hora.get(
            campo,
            "",
        )

        if valor is None:

            continue

        valor = str(
            valor
        ).strip()

        if valor:

            return valor

    return ""


# ================================================================
# MODO DE ENVIO
# ================================================================

def obter_modo_envio(dados):

    valor = dados.get(
        "enviar",
        False,
    )

    if isinstance(
        valor,
        bool,
    ):

        return valor

    texto = str(
        valor
    ).strip().lower()

    return texto in [
        "true",
        "1",
        "sim",
        "yes",
        "envio",
    ]


def obter_manter_navegador_aberto(dados):

    valor = dados.get(
        "manterNavegadorAberto",
        False,
    )

    if isinstance(
        valor,
        bool,
    ):

        return valor

    texto = str(
        valor
    ).strip().lower()

    return texto in [
        "true",
        "1",
        "sim",
        "yes",
    ]


# ================================================================
# NORMALIZAÇÃO
# ================================================================

def normalizar_texto_resposta(texto):

    if not texto:

        return ""

    texto = str(
        texto
    )

    texto = html.unescape(
        texto
    )

    texto = texto.replace(
        "\\/",
        "/",
    )

    texto = texto.replace(
        "\\u0026",
        "&",
    )

    texto = texto.replace(
        "\\x26",
        "&",
    )

    for _ in range(5):

        novo = unquote(
            texto
        )

        if novo == texto:

            break

        texto = novo

    return texto


# ================================================================
# GUID
# ================================================================

def obter_guid_da_url(url):

    try:

        parametros = parse_qs(
            urlparse(url).query
        )

        return parametros.get(
            "GUID",
            [""],
        )[0]

    except Exception:

        return ""


# ================================================================
# PARSE URL
# ================================================================

def extrair_dados_url(url):

    resultado = {

        "url": url,

        "pagina": "",

        "guid": "",

        "solicitacao": "",

        "cmd": "",

        "id_trabalho": "",

        "projeto": "",

        "atividade": "",

        "cmdprj": "",
    }

    try:

        partes = urlparse(
            url
        )

        resultado["pagina"] = partes.path

        parametros = parse_qs(
            partes.query
        )

        resultado["guid"] = parametros.get(
            "GUID",
            [""],
        )[0]

        resultado["solicitacao"] = parametros.get(
            "solicitacao",
            [""],
        )[0]

        resultado["cmd"] = parametros.get(
            "cmd",
            [""],
        )[0]

        resultado["id_trabalho"] = parametros.get(
            "id_trabalho",
            [""],
        )[0]

        if not resultado["id_trabalho"]:

            resultado["id_trabalho"] = parametros.get(
                "idTrabalho",
                [""],
            )[0]

    except Exception as erro:

        resultado["erro"] = str(
            erro
        )

    return resultado


def extrair_dados_url_trabalho(url):

    return extrair_dados_url(
        url
    )


# ================================================================
# IDENTIFICAR PÁGINA
# ================================================================

def nome_pagina(url):

    try:

        return (
            urlparse(url)
            .path
            .split("/")[-1]
            .lower()
        )

    except Exception:

        return ""


def eh_solicitacao(url):

    return (
        nome_pagina(url)
        == "solicitacao.aspx"
    )


def eh_trabalho(url):

    return (
        nome_pagina(url)
        == "trabalho.aspx"
    )


def eh_trabalho_retroativo(url):

    return (
        nome_pagina(url)
        == "trabalhoretroativo.aspx"
    )


# ================================================================
# MONITOR DE NAVEGAÇÃO
# ================================================================

def instalar_monitor_navegacao(
    context,
):

    log("")
    log(
        "============================================"
    )
    log(
        "INSTALANDO MONITOR DE NAVEGAÇÃO"
    )
    log(
        "============================================"
    )

    def navegacao(frame):

        try:

            if frame.parent_frame is not None:

                return

            url = frame.url

            if not url:

                return

            pagina = nome_pagina(
                url
            )

            if pagina not in [
                "solicitacao.aspx",
                "trabalho.aspx",
                "trabalhoretroativo.aspx",
            ]:

                return

            log("")
            log(
                "****************************************"
            )
            log(
                "NAVEGAÇÃO E-DESK DETECTADA"
            )
            log(
                "****************************************"
            )

            log(
                f"Página: {pagina}"
            )

            log(
                f"URL: {url}"
            )

            log(
                "****************************************"
            )
            log("")

        except Exception as erro:

            log(
                f"Erro no monitor de navegação: {erro}"
            )

    context.on(
        "framenavigated",
        navegacao,
    )


# ================================================================
# LOGIN
# ================================================================

def aguardar_login(
    page,
    timeout_segundos=300,
):

    log("")
    log(
        "========================================"
    )
    log(
        "AGUARDANDO AUTENTICAÇÃO DO PROMOB"
    )
    log(
        "========================================"
    )
    log("")

    inicio = time.time()
    ultimo_url = ""

    while True:

        if (
            time.time() - inicio
            > timeout_segundos
        ):

            raise RuntimeError(
                "Tempo limite de autenticação excedido."
            )

        try:

            url_atual = page.url

        except Exception:

            url_atual = ""

        if url_atual != ultimo_url:

            log(
                f"URL atual: {url_atual}"
            )

            ultimo_url = url_atual

        if (
            "/Portal/PortalAtendente.aspx"
            in url_atual
        ):

            return

        try:

            botao = page.locator(
                "#cph1_BtCom"
            )

            if botao.count() > 0:

                if botao.first.is_visible(
                    timeout=1000
                ):

                    return

        except Exception:

            pass

        time.sleep(1)


# ================================================================
# ACESSAR GRID
# ================================================================

def acessar_minha_grid(page):

    log("")
    log(
        "============================================"
    )
    log(
        "ACESSANDO MINHA GRID"
    )
    log(
        "============================================"
    )

    guid = obter_guid_da_url(
        page.url
    )

    if not guid:

        raise RuntimeError(
            "GUID da sessão do E-Desk não encontrado."
        )

    url_grid = (
        "https://promob.e-desk.com.br/"
        "Portal/ListaSolicitacao.aspx"
        f"?GUID={guid}"
    )

    log(
        f"Acessando Grid: {url_grid}"
    )

    page.goto(
        url_grid,
        wait_until="commit",
        timeout=60000,
    )

    page.wait_for_timeout(
        5000
    )


# ================================================================
# MONITOR REQUEST
# ================================================================

def instalar_monitor_requests(page):

    def monitor_request(request):

        try:

            url = request.url

            paginas_interesse = [
                "ListaSolicitacao.aspx",
                "Solicitacao.aspx",
                "Trabalho.aspx",
                "TrabalhoRetroativo.aspx",
            ]

            if not any(
                pagina in url
                for pagina in paginas_interesse
            ):

                return

        except Exception:

            pass

    page.on(
        "request",
        monitor_request,
    )


# ================================================================
# LOCALIZAR SOLICITAÇÃO NA GRID
# ================================================================

def localizar_solicitacao(
    page,
    numero_solicitacao,
):

    numero_solicitacao = str(
        numero_solicitacao
    ).strip()

    log("")
    log(
        "============================================"
    )
    log(
        "LOCALIZANDO SOLICITAÇÃO NA GRID"
    )
    log(
        "============================================"
    )

    seletor_tabela = (
        "#ctl00_cph1_hgrSol_ctl00"
    )

    try:

        page.wait_for_selector(
            seletor_tabela,
            state="attached",
            timeout=30000,
        )

    except Exception:

        pass

    linhas = page.locator(
        "#ctl00_cph1_hgrSol_ctl00 tr.rgRow"
    )

    quantidade = linhas.count()

    log(
        f"Linhas rgRow encontradas na tabela: {quantidade}"
    )

    for i in range(
        quantidade
    ):

        linha = linhas.nth(i)

        try:

            celulas = linha.locator(
                "td"
            )

            if celulas.count() < 2:

                continue

            numero = celulas.nth(
                1
            ).inner_text(
                timeout=1000
            ).strip()

            if numero != numero_solicitacao:

                continue

            log(
                f"Solicitação {numero_solicitacao} encontrada na linha {i}."
            )

            return linha

        except Exception:

            continue

    log(
        f"Solicitação {numero_solicitacao} não encontrada."
    )

    return None


# ================================================================
# ABRIR TRABALHO NA SOLICITAÇÃO
# ================================================================

def abrir_trabalho_na_solicitacao(
    page,
    context,
    id_trabalho,
):

    log("")
    log(
        "=" * 60
    )
    log(
        "ABRINDO TRABALHO NA ABA TRABALHOS"
    )
    log(
        "=" * 60
    )

    id_trabalho = str(
        id_trabalho or ""
    ).strip()

    if not id_trabalho:

        log(
            "ID do trabalho não informado."
        )

        return None

    seletor_aba = "#cph1_rpvTrabalhos"

    try:

        aba = page.locator(
            seletor_aba
        ).first

        aba.wait_for(
            state="visible",
            timeout=10000,
        )

    except Exception as erro:

        log(
            f"Aba de trabalhos não visível: {erro}"
        )

        return None

    tabela = aba.locator(
        "#cph1_gvwTra"
    ).first

    try:

        tabela.wait_for(
            state="visible",
            timeout=10000,
        )

    except Exception as erro:

        log(
            f"Tabela de trabalhos não visível: {erro}"
        )

        return None

    linhas = tabela.locator(
        "tr"
    )

    quantidade = linhas.count()

    log(
        f"Linhas encontradas na tabela de trabalhos: {quantidade}"
    )

    linha_alvo = None

    for i in range(
        quantidade
    ):

        linha = linhas.nth(i)

        try:

            celulas = linha.locator(
                "td"
            )

            if celulas.count() < 2:

                continue

            valor_id = (
                celulas
                .nth(1)
                .inner_text()
                .strip()
            )

            log(
                f"LINHA {i} - ID E-DESK VISÍVEL: {valor_id}"
            )

            if valor_id == id_trabalho:

                linha_alvo = linha

                log(
                    f"Trabalho {id_trabalho} encontrado pelo ID exato na linha {i}."
                )

                break

        except Exception:

            continue

    if linha_alvo is None:

        log("")
        log(
            "============================================================"
        )
        log(
            "ID EXATO NÃO ENCONTRADO"
        )
        log(
            "============================================================"
        )

        log(
            f"ID recebido do Flutter: {id_trabalho}"
        )

        log(
            "Nenhum trabalho foi selecionado automaticamente."
        )

        return None

    celulas_selecao = (
        linha_alvo.locator(
            'td[onclick*="btnSelTra"]'
        )
    )

    if celulas_selecao.count() == 0:

        log(
            "A linha encontrada não possui btnSelTra."
        )

        return None

    alvo = (
        celulas_selecao.first
    )

    try:

        onclick = (
            alvo.get_attribute(
                "onclick"
            )
            or ""
        )

    except Exception:

        onclick = ""

    log(
        f"POSTBACK ENCONTRADO: {onclick}"
    )

    if not onclick:

        log(
            "O elemento de seleção não possui onclick."
        )

        return None

    postback_match = re.search(
        r"__doPostBack\('([^']+)'\s*,\s*'([^']*)'\)",
        onclick,
    )

    if postback_match:

        log(
            f"EVENT TARGET: {postback_match.group(1)}"
        )

        log(
            f"EVENT ARGUMENT: {postback_match.group(2)}"
        )

    log(
        "Executando clique original do botão de seleção..."
    )

    try:

        alvo.scroll_into_view_if_needed(
            timeout=5000
        )

    except Exception:

        pass

    try:

        alvo.click(
            timeout=15000,
            force=True,
        )

    except Exception as erro:

        log(
            f"Erro no clique do btnSelTra: {erro}"
        )

        return None

    log(
        "Clique executado."
    )

    page.wait_for_timeout(
        1000
    )

    log(
        "Aguardando abertura de Trabalho.aspx..."
    )

    inicio = time.time()
    ultimo_url = ""

    while (
        time.time() - inicio < 30
    ):

        for pagina in context.pages:

            try:

                if pagina.is_closed():

                    continue

                url_atual = pagina.url

                if url_atual != ultimo_url:

                    log(
                        f"URL durante abertura do trabalho: {url_atual}"
                    )

                    ultimo_url = url_atual

                if eh_trabalho(
                    url_atual
                ):

                    log("")
                    log(
                        "****************************************"
                    )
                    log(
                        "TRABALHO ABERTO COM SUCESSO"
                    )
                    log(
                        "****************************************"
                    )
                    log(
                        f"URL: {url_atual}"
                    )
                    log("")

                    return pagina

            except Exception:

                continue

        try:

            if eh_trabalho(
                page.url
            ):

                return page

        except Exception:

            pass

        time.sleep(
            0.5
        )

    log(
        "Tempo limite aguardando Trabalho.aspx."
    )

    log(
        f"URL atual: {page.url}"
    )

    return None


# ================================================================
# ABRIR TRABALHO RETROATIVO
# ================================================================

def abrir_trabalho_retroativo(
    pagina_trabalho,
    dados_trabalho,
):

    log("")
    log(
        "============================================================"
    )
    log(
        "ABRINDO TELA TRABALHO RETROATIVO"
    )
    log(
        "============================================================"
    )

    if pagina_trabalho is None:

        return None

    dados_url = extrair_dados_url(
        pagina_trabalho.url
    )

    guid = str(
        (
            dados_trabalho.get(
                "guid",
                "",
            )
            or dados_url.get(
                "guid",
                "",
            )
            or obter_guid_da_url(
                pagina_trabalho.url
            )
        )
        or ""
    ).strip()

    solicitacao = str(
        (
            dados_trabalho.get(
                "solicitacao",
                "",
            )
            or dados_url.get(
                "solicitacao",
                "",
            )
        )
        or ""
    ).strip()

    id_trabalho = str(
        (
            dados_trabalho.get(
                "id_trabalho",
                "",
            )
            or dados_url.get(
                "id_trabalho",
                "",
            )
        )
        or ""
    ).strip()

    log(
        f"GUID: {guid}"
    )

    log(
        f"SOLICITAÇÃO: {solicitacao}"
    )

    log(
        f"ID TRABALHO E-DESK: {id_trabalho}"
    )

    if not guid:

        log(
            "GUID não encontrado."
        )

        return pagina_trabalho

    if not id_trabalho:

        log(
            "ID do trabalho E-Desk não encontrado."
        )

        return pagina_trabalho

    parametros = {
        "GUID": guid,
        "id_trabalho": id_trabalho,
    }

    if solicitacao:

        parametros["solicitacao"] = solicitacao

    url_retroativo = (
        "https://promob.e-desk.com.br/"
        "Portal/TrabalhoRetroativo.aspx?"
        + urlencode(
            parametros
        )
    )

    log(
        f"Acessando TrabalhoRetroativo: {url_retroativo}"
    )

    try:

        pagina_trabalho.goto(
            url_retroativo,
            wait_until="domcontentloaded",
            timeout=30000,
        )

        pagina_trabalho.wait_for_timeout(
            2500
        )

        if eh_trabalho_retroativo(
            pagina_trabalho.url
        ):

            log("")
            log(
                "****************************************"
            )
            log(
                "TELA TRABALHO RETROATIVO ABERTA COM SUCESSO"
            )
            log(
                "****************************************"
            )
            log(
                f"URL: {pagina_trabalho.url}"
            )
            log("")

            return pagina_trabalho

    except Exception as erro:

        log(
            f"Erro ao abrir TrabalhoRetroativo: {erro}"
        )

    return pagina_trabalho


# ================================================================
# SALVAR MAPEAMENTO
# ================================================================

def salvar_mapeamento(
    dados,
):

    arquivo = (
        LOGS_PATH
        / "mapeamento_trabalho_cmd.json"
    )

    try:

        registros = []

        if arquivo.exists():

            try:

                with arquivo.open(
                    "r",
                    encoding="utf-8",
                ) as f:

                    registros = json.load(
                        f
                    )

            except Exception:

                registros = []

        registros.append(
            dados
        )

        with arquivo.open(
            "w",
            encoding="utf-8",
        ) as f:

            json.dump(
                registros,
                f,
                ensure_ascii=False,
                indent=2,
            )

    except Exception:

        pass


# ================================================================
# ABRIR SOLICITAÇÃO E TRABALHO
# ================================================================

def abrir_trabalho(
    page,
    context,
    linha_grid,
    numero_solicitacao,
    id_trabalho,
):

    id_trabalho = str(
        id_trabalho
    ).strip()

    numero_solicitacao = str(
        numero_solicitacao
        or ""
    ).strip()

    log("")
    log(
        "============================================================"
    )
    log(
        "ABERTURA DA SOLICITAÇÃO E TRABALHO"
    )
    log(
        "============================================================"
    )

    log(
        f"SOLICITAÇÃO: {numero_solicitacao}"
    )

    log(
        f"TRABALHO RELATIVO: {id_trabalho}"
    )

    guid = obter_guid_da_url(
        page.url
    )

    if linha_grid is not None:

        try:

            linha_grid.scroll_into_view_if_needed()

            page.wait_for_timeout(
                300
            )

            linha_grid.click(
                timeout=10000
            )

        except Exception:

            pass

    inicio = time.time()

    pagina_solicitacao = None

    while (
        time.time() - inicio < 10
    ):

        for pagina in context.pages:

            try:

                if pagina.is_closed():

                    continue

                if eh_solicitacao(
                    pagina.url
                ):

                    pagina_solicitacao = pagina

                    break

            except Exception:

                pass

        if pagina_solicitacao:

            break

        time.sleep(
            0.5
        )

    if not pagina_solicitacao:

        log(
            "Clique na grade não abriu a Solicitação.aspx automaticamente."
        )

        try:

            link_sol = page.locator(
                f"a:has-text('{numero_solicitacao}')"
            ).first

            if link_sol.count() > 0:

                link_sol.click(
                    timeout=5000
                )

                page.wait_for_timeout(
                    3000
                )

        except Exception:

            pass

    for pagina in context.pages:

        try:

            if pagina.is_closed():

                continue

            if eh_solicitacao(
                pagina.url
            ):

                pagina_solicitacao = pagina

                break

        except Exception:

            pass

    if not pagina_solicitacao:

        raise RuntimeError(
            "O E-Desk não abriu a Solicitação.aspx."
        )

    page = pagina_solicitacao

    log(
        f"Solicitação aberta: {page.url}"
    )

    dados_solicitacao = extrair_dados_url(
        page.url
    )

    solicitacao_encoded = (
        dados_solicitacao.get(
            "solicitacao"
        )
    )

    cmd = (
        dados_solicitacao.get(
            "cmd"
        )
    )

    # ============================================================
    # IMPORTANTE:
    #
    # O ID DO TRABALHO É PROCURADO DENTRO DESTA SOLICITAÇÃO.
    #
    # Isso evita confundir:
    #
    # Solicitação 2262412 / Trabalho 18
    #
    # com:
    #
    # Solicitação 2261914 / Trabalho 18
    # ============================================================

    pagina_trabalho = (
        abrir_trabalho_na_solicitacao(
            page,
            context,
            id_trabalho,
        )
    )

    if not pagina_trabalho:

        log(
            "Não foi possível abrir Trabalho.aspx."
        )

        return page

    dados_trabalho = (
        extrair_dados_url(
            pagina_trabalho.url
        )
    )

    id_efetivo = (
        dados_trabalho.get(
            "id_trabalho",
            "",
        )
        or id_trabalho
    )

    if not dados_trabalho.get(
        "guid"
    ):

        dados_trabalho[
            "guid"
        ] = guid

    if not dados_trabalho.get(
        "solicitacao"
    ):

        dados_trabalho[
            "solicitacao"
        ] = solicitacao_encoded

    if not dados_trabalho.get(
        "id_trabalho"
    ):

        dados_trabalho[
            "id_trabalho"
        ] = id_efetivo

    mapeamento = {

        "idTrabalhoFlutter":
            id_trabalho,

        "idTrabalhoEdesk":
            id_efetivo,

        "solicitacao":
            numero_solicitacao,

        "solicitacaoEncoded":
            solicitacao_encoded,

        "cmd":
            cmd,

        "guid":
            guid,

        "urlSolicitacao":
            page.url,

        "urlTrabalho":
            pagina_trabalho.url,

        "timestamp":
            time.strftime(
                "%Y-%m-%dT%H:%M:%S"
            ),
    }

    salvar_mapeamento(
        mapeamento
    )

    log("")
    log(
        "MAPEAMENTO DO TRABALHO"
    )
    log(
        json.dumps(
            mapeamento,
            ensure_ascii=False,
            indent=2,
        )
    )
    log("")

    return abrir_trabalho_retroativo(
        pagina_trabalho,
        dados_trabalho,
    )


# ================================================================
# SALVAR UMA HORA NO E-DESK
# ================================================================

def salvar_hora(
    page,
    hora,
    indice_hora,
    total_horas,
):

    log("")
    log(
        "============================================================"
    )
    log(
        f"SALVANDO HORA {indice_hora} DE {total_horas}"
    )
    log(
        "============================================================"
    )

    if not isinstance(
        hora,
        dict,
    ):

        raise RuntimeError(
            f"A HORA {indice_hora} não é um objeto JSON válido."
        )

    data = obter_data_hora(
        hora
    )

    inicio = obter_inicio_hora(
        hora
    )

    fim = obter_fim_hora(
        hora
    )

    descritivo_original = obter_descritivo_hora(
        hora
    )

    descritivo = limpar_descritivo_hora(
        descritivo_original,
        data,
    )

    log("")
    log(
        f"DADOS DA HORA {indice_hora}"
    )
    log(
        f"Data: {data}"
    )
    log(
        f"Início: {inicio}"
    )
    log(
        f"Fim: {fim}"
    )
    log(
        f"Descritivo recebido: "
        f"{descritivo_original or '[NÃO INFORMADO]'}"
    )
    log(
        f"Descritivo limpo: "
        f"{descritivo or '[NÃO INFORMADO]'}"
    )
    log("")

    # ============================================================
    # VALIDAR DADOS
    # ============================================================

    if not data:

        raise RuntimeError(
            f"A HORA {indice_hora} não possui data."
        )

    if not inicio:

        raise RuntimeError(
            f"A HORA {indice_hora} não possui horário de início."
        )

    if not fim:

        raise RuntimeError(
            f"A HORA {indice_hora} não possui horário de fim."
        )

    if not descritivo:

        raise RuntimeError(
            f"A HORA {indice_hora} não possui descritivo. "
            "O Flutter precisa enviar o campo 'descritivo'."
        )

    # ============================================================
    # LOCALIZAR CAMPOS
    # ============================================================

    campo_data = page.locator(
        "#cph1_txtDatTem"
    )

    campo_inicio = page.locator(
        "#cph1_txtHorIni"
    )

    campo_fim = page.locator(
        "#cph1_txtHorFin"
    )

    campo_tipo = page.locator(
        "#cph1_ddlTipReg"
    )

    campo_rea = page.locator(
        "#cph1_txtRea"
    )

    botao_salvar = page.locator(
        "#cph1_BtAtu"
    )

    for nome, elemento in [
        ("Data", campo_data),
        ("Início", campo_inicio),
        ("Fim", campo_fim),
        ("Tipo", campo_tipo),
        ("Descritivo", campo_rea),
        ("Salvar", botao_salvar),
    ]:

        try:

            elemento.wait_for(
                state="visible",
                timeout=15000,
            )

        except Exception as erro:

            raise RuntimeError(
                f"Campo '{nome}' não ficou disponível "
                f"para a HORA {indice_hora}: {erro}"
            )

    # ============================================================
    # LER TEXTO EXISTENTE
    # ============================================================

    try:

        texto_existente = campo_rea.input_value()

    except Exception:

        texto_existente = ""

    texto_existente = str(
        texto_existente or ""
    ).strip()

    log("")
    log(
        "CONTEÚDO ATUAL DO CAMPO txtRea:"
    )
    log(
        texto_existente
        if texto_existente
        else "[VAZIO]"
    )

    # ============================================================
    # PREENCHER DATA
    # ============================================================

    log("")
    log(
        f"Preenchendo DATA: {data}"
    )

    campo_data.fill(
        data
    )

    # ============================================================
    # PREENCHER INÍCIO
    # ============================================================

    log(
        f"Preenchendo INÍCIO: {inicio}"
    )

    campo_inicio.fill(
        inicio
    )

    # ============================================================
    # PREENCHER FIM
    # ============================================================

    log(
        f"Preenchendo FIM: {fim}"
    )

    campo_fim.fill(
        fim
    )

    # ============================================================
    # TIPO DE REGISTRO
    #
    # 0 = Registrar somente um tempo trabalhado
    # ============================================================

    log(
        "Selecionando TIPO DE REGISTRO: 0"
    )

    try:

        campo_tipo.select_option(
            "0"
        )

    except Exception as erro:

        raise RuntimeError(
            f"Erro ao selecionar tipo de registro "
            f"na HORA {indice_hora}: {erro}"
        )

    # ============================================================
    # AGUARDAR EVENTUAL POSTBACK DO SELECT
    # ============================================================

    page.wait_for_timeout(
        1000
    )

    try:

        campo_rea = page.locator(
            "#cph1_txtRea"
        )

        campo_rea.wait_for(
            state="visible",
            timeout=10000,
        )

    except Exception as erro:

        raise RuntimeError(
            f"Campo txtRea não disponível após seleção "
            f"do tipo na HORA {indice_hora}: {erro}"
        )

    # ============================================================
    # LER NOVAMENTE O TEXTO EXISTENTE
    # ============================================================

    try:

        texto_existente = campo_rea.input_value()

    except Exception:

        texto_existente = ""

    texto_existente = str(
        texto_existente or ""
    ).strip()

    # ============================================================
    # MONTAR NOVO DESCRITIVO
    #
    # Exemplo:
    #
    # 02/09/2026:
    # - Agenda / E-mails
    #
    # 10/09/2026: - Agenda
    #
    # 15/09/2026:
    # - teste
    #
    # A data não é duplicada dentro do descritivo.
    # ============================================================

    novo_bloco = (
        f"{data}: -"
        f"{descritivo}"
    )

    if texto_existente:

        if novo_bloco not in texto_existente:

            texto_final = (
                texto_existente
                + "\n"
                + novo_bloco
            )

        else:

            texto_final = texto_existente

    else:

        texto_final = novo_bloco

    log("")
    log(
        "NOVO CONTEÚDO DO txtRea:"
    )
    log(
        texto_final
    )

    # ============================================================
    # PREENCHER DESCRITIVO
    # ============================================================

    campo_rea.fill(
        texto_final
    )

    # ============================================================
    # CONFERÊNCIA ANTES DE SALVAR
    # ============================================================

    log("")
    log(
        "============================================================"
    )
    log(
        f"CONFERÊNCIA ANTES DO SALVAMENTO - HORA {indice_hora}"
    )
    log(
        "============================================================"
    )

    try:

        log(
            f"DATA: {campo_data.input_value()}"
        )

    except Exception:

        pass

    try:

        log(
            f"INÍCIO: {campo_inicio.input_value()}"
        )

    except Exception:

        pass

    try:

        log(
            f"FIM: {campo_fim.input_value()}"
        )

    except Exception:

        pass

    try:

        log(
            f"TIPO: {campo_tipo.input_value()}"
        )

    except Exception:

        pass

    try:

        log(
            "DESCRITIVO:"
        )

        log(
            campo_rea.input_value()
        )

    except Exception:

        pass

    # ============================================================
    # SALVAR
    # ============================================================

    log("")
    log(
        f"Clicando no botão SALVAR - HORA {indice_hora}..."
    )

    try:

        botao_salvar = page.locator(
            "#cph1_BtAtu"
        )

        botao_salvar.wait_for(
            state="visible",
            timeout=10000,
        )

        botao_salvar.click(
            timeout=15000,
        )

    except Exception as erro:

        raise RuntimeError(
            f"Erro ao clicar em Salvar na HORA "
            f"{indice_hora}: {erro}"
        )

    log(
        "Clique em SALVAR executado."
    )

    # ============================================================
    # AGUARDAR POSTBACK
    # ============================================================

    page.wait_for_timeout(
        3000
    )

    log(
        f"URL após salvar: {page.url}"
    )

    # ============================================================
    # VERIFICAR SE A PÁGINA CONTINUA NO RETROATIVO
    # ============================================================

    if not eh_trabalho_retroativo(
        page.url
    ):

        log(
            "ATENÇÃO: após salvar a URL mudou."
        )

    # ============================================================
    # VERIFICAR TABELA DE HORAS
    # ============================================================

    log("")
    log(
        "============================================================"
    )
    log(
        f"VERIFICANDO REGISTRO SALVO - HORA {indice_hora}"
    )
    log(
        "============================================================"
    )

    try:

        tabela = page.locator(
            "#cph1_gvwTempos"
        )

        quantidade = tabela.count()

        log(
            f"Tabela #cph1_gvwTempos encontrada: {quantidade}"
        )

        if quantidade > 0:

            tabela.wait_for(
                state="visible",
                timeout=10000,
            )

            texto_tabela = (
                tabela.inner_text(
                    timeout=5000
                )
                .strip()
            )

            log("")
            log(
                "CONTEÚDO DA TABELA DE HORAS:"
            )
            log(
                texto_tabela
            )

            encontrou_horario = (
                inicio in texto_tabela
                or fim in texto_tabela
            )

            if encontrou_horario:

                log("")
                log(
                    "****************************************"
                )
                log(
                    f"HORA {indice_hora} SALVA COM SUCESSO"
                )
                log(
                    "****************************************"
                )
                log("")

                return True

            log("")
            log(
                "A tabela foi encontrada, mas não foi possível "
                "confirmar o horário pelo texto."
            )

            # O clique de salvar ocorreu.
            return True

    except Exception as erro:

        log(
            f"Não foi possível validar a tabela de horas: {erro}"
        )

    log("")
    log(
        f"HORA {indice_hora}: SALVAMENTO EXECUTADO. "
        "Não foi possível confirmar pela tabela."
    )
    log("")

    return True


# ================================================================
# DIAGNÓSTICO DA TELA DE HORAS
# ================================================================

def diagnosticar_tela_horas(
    page,
):

    log("")
    log(
        "============================================================"
    )
    log(
        "DIAGNÓSTICO COMPLETO DA TELA DE HORAS"
    )
    log(
        "============================================================"
    )

    log(
        f"URL atual: {page.url}"
    )

    campos_procurados = [

        "txtDatTem",

        "txtHorIni",

        "txtHorFin",

        "ddlTipReg",

        "txlGtt",

        "txlTtr",

        "txlEqt",

        "txlAte",

        "txtDet",

        "txtRea",

    ]

    try:

        frames = page.frames

        log("")
        log(
            f"TOTAL DE FRAMES ENCONTRADOS: {len(frames)}"
        )

    except Exception as erro:

        log(
            f"Erro ao obter frames: {erro}"
        )

        frames = []

    for indice_frame, frame in enumerate(frames):

        log("")
        log(
            "------------------------------------------------------------"
        )
        log(
            f"FRAME {indice_frame}"
        )
        log(
            "------------------------------------------------------------"
        )

        try:

            log(
                f"URL DO FRAME: {frame.url}"
            )

        except Exception:

            log(
                "URL DO FRAME: não disponível"
            )

        for nome_campo in campos_procurados:

            try:

                elementos = frame.locator(
                    f'[id*="{nome_campo}"], '
                    f'[name*="{nome_campo}"]'
                )

                quantidade = elementos.count()

                if quantidade > 0:

                    log("")
                    log(
                        f"*** CAMPO PROCURADO: {nome_campo} "
                        f"-> {quantidade} encontrado(s)"
                    )

                    for indice in range(
                        quantidade
                    ):

                        elemento = elementos.nth(
                            indice
                        )

                        try:

                            tag = elemento.evaluate(
                                "(el) => el.tagName"
                            )

                        except Exception:

                            tag = ""

                        try:

                            id_elemento = (
                                elemento.get_attribute(
                                    "id"
                                )
                                or ""
                            )

                        except Exception:

                            id_elemento = ""

                        try:

                            name_elemento = (
                                elemento.get_attribute(
                                    "name"
                                )
                                or ""
                            )

                        except Exception:

                            name_elemento = ""

                        try:

                            tipo_elemento = (
                                elemento.get_attribute(
                                    "type"
                                )
                                or ""
                            )

                        except Exception:

                            tipo_elemento = ""

                        try:

                            valor_elemento = (
                                elemento.get_attribute(
                                    "value"
                                )
                                or ""
                            )

                        except Exception:

                            valor_elemento = ""

                        try:

                            texto_elemento = (
                                elemento.inner_text(
                                    timeout=1000
                                )
                                .strip()
                            )

                        except Exception:

                            texto_elemento = ""

                        log(
                            f"  TAG: {tag}"
                        )

                        log(
                            f"  ID: {id_elemento}"
                        )

                        log(
                            f"  NAME: {name_elemento}"
                        )

                        log(
                            f"  TYPE: {tipo_elemento}"
                        )

                        log(
                            f"  VALUE: {valor_elemento}"
                        )

                        if texto_elemento:

                            log(
                                f"  TEXTO: {texto_elemento[:300]}"
                            )

            except Exception as erro:

                log(
                    f"Erro procurando {nome_campo}: {erro}"
                )

        # ========================================================
        # INPUTS
        # ========================================================

        try:

            inputs = frame.locator(
                "input"
            )

            quantidade_inputs = inputs.count()

            log("")
            log(
                f"INPUTS ENCONTRADOS NO FRAME: {quantidade_inputs}"
            )

            for indice in range(
                quantidade_inputs
            ):

                elemento = inputs.nth(
                    indice
                )

                try:

                    id_elemento = (
                        elemento.get_attribute(
                            "id"
                        )
                        or ""
                    )

                    name_elemento = (
                        elemento.get_attribute(
                            "name"
                        )
                        or ""
                    )

                    tipo_elemento = (
                        elemento.get_attribute(
                            "type"
                        )
                        or ""
                    )

                    valor_elemento = (
                        elemento.get_attribute(
                            "value"
                        )
                        or ""
                    )

                    placeholder = (
                        elemento.get_attribute(
                            "placeholder"
                        )
                        or ""
                    )

                    onclick = (
                        elemento.get_attribute(
                            "onclick"
                        )
                        or ""
                    )

                    descricao = (
                        f"INPUT {indice} | "
                        f"id={id_elemento} | "
                        f"name={name_elemento} | "
                        f"type={tipo_elemento} | "
                        f"value={valor_elemento} | "
                        f"placeholder={placeholder}"
                    )

                    texto_busca = (
                        descricao
                        + " "
                        + onclick
                    ).lower()

                    relevante = any(
                        campo.lower()
                        in texto_busca
                        for campo in campos_procurados
                    )

                    if relevante:

                        log(
                            f"  [RELEVANTE] {descricao}"
                        )

                        if onclick:

                            log(
                                f"      onclick={onclick[:500]}"
                            )

                    else:

                        log(
                            f"  {descricao}"
                        )

                except Exception as erro:

                    log(
                        f"  INPUT {indice} -> erro: {erro}"
                    )

        except Exception as erro:

            log(
                f"Erro ao listar inputs: {erro}"
            )

        # ========================================================
        # SELECTS
        # ========================================================

        try:

            selects = frame.locator(
                "select"
            )

            quantidade_selects = selects.count()

            log("")
            log(
                f"SELECTS ENCONTRADOS NO FRAME: {quantidade_selects}"
            )

            for indice in range(
                quantidade_selects
            ):

                elemento = selects.nth(
                    indice
                )

                try:

                    id_elemento = (
                        elemento.get_attribute(
                            "id"
                        )
                        or ""
                    )

                    name_elemento = (
                        elemento.get_attribute(
                            "name"
                        )
                        or ""
                    )

                    valor_elemento = (
                        elemento.input_value()
                    )

                    texto = (
                        elemento.inner_text(
                            timeout=1000
                        )
                        .strip()
                    )

                    log(
                        f"  SELECT {indice} | "
                        f"id={id_elemento} | "
                        f"name={name_elemento} | "
                        f"value={valor_elemento}"
                    )

                    if texto:

                        log(
                            f"      opções/texto: {texto[:500]}"
                        )

                except Exception as erro:

                    log(
                        f"  SELECT {indice} -> erro: {erro}"
                    )

        except Exception as erro:

            log(
                f"Erro ao listar selects: {erro}"
            )

        # ========================================================
        # TEXTAREAS
        # ========================================================

        try:

            textareas = frame.locator(
                "textarea"
            )

            quantidade_textareas = textareas.count()

            log("")
            log(
                f"TEXTAREAS ENCONTRADOS NO FRAME: {quantidade_textareas}"
            )

            for indice in range(
                quantidade_textareas
            ):

                elemento = textareas.nth(
                    indice
                )

                try:

                    id_elemento = (
                        elemento.get_attribute(
                            "id"
                        )
                        or ""
                    )

                    name_elemento = (
                        elemento.get_attribute(
                            "name"
                        )
                        or ""
                    )

                    valor_elemento = (
                        elemento.input_value()
                    )

                    log(
                        f"  TEXTAREA {indice} | "
                        f"id={id_elemento} | "
                        f"name={name_elemento} | "
                        f"value={valor_elemento[:500]}"
                    )

                except Exception as erro:

                    log(
                        f"  TEXTAREA {indice} -> erro: {erro}"
                    )

        except Exception as erro:

            log(
                f"Erro ao listar textareas: {erro}"
            )

        # ========================================================
        # BOTÕES
        # ========================================================

        try:

            botoes = frame.locator(
                "button, input[type='button'], input[type='submit']"
            )

            quantidade_botoes = botoes.count()

            log("")
            log(
                f"BOTÕES ENCONTRADOS NO FRAME: {quantidade_botoes}"
            )

            for indice in range(
                quantidade_botoes
            ):

                elemento = botoes.nth(
                    indice
                )

                try:

                    id_elemento = (
                        elemento.get_attribute(
                            "id"
                        )
                        or ""
                    )

                    name_elemento = (
                        elemento.get_attribute(
                            "name"
                        )
                        or ""
                    )

                    tipo_elemento = (
                        elemento.get_attribute(
                            "type"
                        )
                        or ""
                    )

                    value_elemento = (
                        elemento.get_attribute(
                            "value"
                        )
                        or ""
                    )

                    texto_elemento = (
                        elemento.inner_text(
                            timeout=500
                        )
                        .strip()
                    )

                    onclick = (
                        elemento.get_attribute(
                            "onclick"
                        )
                        or ""
                    )

                    log(
                        f"  BOTÃO {indice} | "
                        f"id={id_elemento} | "
                        f"name={name_elemento} | "
                        f"type={tipo_elemento} | "
                        f"value={value_elemento} | "
                        f"texto={texto_elemento[:150]}"
                    )

                    if onclick:

                        log(
                            f"      onclick={onclick[:500]}"
                        )

                except Exception:

                    continue

        except Exception as erro:

            log(
                f"Erro ao listar botões: {erro}"
            )

    log("")
    log(
        "============================================================"
    )
    log(
        "FIM DO DIAGNÓSTICO DA TELA DE HORAS"
    )
    log(
        "============================================================"
    )
    log("")


# ================================================================
# AGUARDAR NAVEGADOR
# ================================================================

def aguardar_navegador(
    context,
):

    while True:

        try:

            paginas = [
                pagina
                for pagina in context.pages
                if not pagina.is_closed()
            ]

            if not paginas:

                break

            time.sleep(
                0.5
            )

        except Exception:

            break


# ================================================================
# FECHAR PLAYWRIGHT
# ================================================================

def fechar_playwright(
    context,
    playwright,
):

    log("")
    log(
        "============================================================"
    )
    log(
        "ENCERRANDO AUTOMAÇÃO E-DESK"
    )
    log(
        "============================================================"
    )

    # ------------------------------------------------------------
    # Fechar contexto primeiro.
    # ------------------------------------------------------------

    if context is not None:

        try:

            paginas = list(
                context.pages
            )

            log(
                f"Páginas abertas antes do encerramento: {len(paginas)}"
            )

        except Exception:

            paginas = []

        try:

            context.close()

            log(
                "Contexto Playwright encerrado."
            )

        except Exception as erro:

            log(
                f"Aviso ao fechar contexto Playwright: {erro}"
            )

    # ------------------------------------------------------------
    # Depois parar Playwright.
    # ------------------------------------------------------------

    if playwright is not None:

        try:

            playwright.stop()

            log(
                "Playwright encerrado."
            )

        except Exception as erro:

            log(
                f"Aviso ao parar Playwright: {erro}"
            )

    log(
        "Automação E-Desk finalizada."
    )
    log("")


# ================================================================
# MAIN
# ================================================================

def main():

    dados = carregar_request()

    url = obter_url(
        dados
    )

    trabalhos = extrair_trabalhos(
        dados
    )

    enviar = obter_modo_envio(
        dados
    )

    manter_navegador_aberto = (
        obter_manter_navegador_aberto(
            dados
        )
    )

    # ============================================================
    # VALIDAR TRABALHOS
    # ============================================================

    if not trabalhos:

        raise RuntimeError(
            "Nenhum trabalho foi informado no request."
        )

    # ============================================================
    # RESUMO
    # ============================================================

    log("")
    log(
        "============================================================"
    )
    log(
        "RESUMO DOS DADOS DO REQUEST"
    )
    log(
        "============================================================"
    )

    log(
        f"URL: {url}"
    )

    log(
        f"Quantidade de trabalhos: {len(trabalhos)}"
    )

    total_horas = 0

    for indice_trabalho, trabalho in enumerate(
        trabalhos,
        start=1,
    ):

        solicitacao = str(
            trabalho.get(
                "solicitacao",
                "",
            )
            or ""
        ).strip()

        id_trabalho = str(
            trabalho.get(
                "id_trabalho",
                "",
            )
            or ""
        ).strip()

        horas = trabalho.get(
            "horas",
            [],
        )

        if not isinstance(
            horas,
            list,
        ):

            horas = []

        total_horas += len(
            horas
        )

        log("")
        log(
            f"TRABALHO {indice_trabalho}:"
        )
        log(
            f"  Solicitação: {solicitacao}"
        )
        log(
            f"  ID Trabalho: {id_trabalho}"
        )
        log(
            f"  Quantidade de horas: {len(horas)}"
        )

    log("")
    log(
        f"Quantidade TOTAL de horas: {total_horas}"
    )

    log(
        f"Modo envio: {enviar}"
    )

    log(
        f"Manter navegador aberto: {manter_navegador_aberto}"
    )

    log(
        "============================================================"
    )
    log("")

    # ============================================================
    # QUANDO O FLUTTER ESTÁ ENVIANDO:
    #
    # nunca deixar o Python ficar aguardando o navegador.
    # ============================================================

    if enviar:

        manter_navegador_aberto = False

    playwright = None
    context = None

    try:

        # ========================================================
        # INICIAR PLAYWRIGHT
        # ========================================================

        playwright = sync_playwright().start()

        context = (
            playwright.chromium
            .launch_persistent_context(
                user_data_dir=str(
                    PROFILE_PATH
                ),
                headless=False,
                args=[
                    "--start-maximized",
                ],
                viewport=None,
            )
        )

        instalar_monitor_navegacao(
            context
        )

        # ========================================================
        # OBTER PÁGINA
        # ========================================================

        if context.pages:

            page = context.pages[0]

        else:

            page = context.new_page()

        instalar_monitor_requests(
            page
        )

        # ========================================================
        # ABRIR E-DESK
        # ========================================================

        log("")
        log(
            "============================================================"
        )
        log(
            "ABRINDO E-DESK"
        )
        log(
            "============================================================"
        )

        page.goto(
            url,
            wait_until="domcontentloaded",
            timeout=60000,
        )

        # ========================================================
        # LOGIN
        # ========================================================

        aguardar_login(
            page
        )

        # ========================================================
        # PROCESSAR CADA TRABALHO
        # ========================================================

        for indice_trabalho, trabalho in enumerate(
            trabalhos,
            start=1,
        ):

            if not isinstance(
                trabalho,
                dict,
            ):

                raise RuntimeError(
                    f"O TRABALHO {indice_trabalho} "
                    "não é um objeto JSON válido."
                )

            solicitacao = str(
                trabalho.get(
                    "solicitacao",
                    "",
                )
                or ""
            ).strip()

            id_trabalho = str(
                trabalho.get(
                    "id_trabalho",
                    "",
                )
                or ""
            ).strip()

            horas = trabalho.get(
                "horas",
                [],
            )

            if not isinstance(
                horas,
                list,
            ):

                horas = []

            log("")
            log(
                "############################################################"
            )
            log(
                f"INICIANDO TRABALHO {indice_trabalho} DE {len(trabalhos)}"
            )
            log(
                "############################################################"
            )

            log(
                f"SOLICITAÇÃO: {solicitacao}"
            )

            log(
                f"ID TRABALHO RELATIVO: {id_trabalho}"
            )

            log(
                f"QUANTIDADE DE HORAS: {len(horas)}"
            )

            # ====================================================
            # VALIDAR IDENTIFICAÇÃO
            # ====================================================

            if not solicitacao:

                raise RuntimeError(
                    f"O TRABALHO {indice_trabalho} "
                    "não possui número de solicitação."
                )

            if not id_trabalho:

                raise RuntimeError(
                    f"O TRABALHO {indice_trabalho} "
                    f"da solicitação {solicitacao} "
                    "não possui ID do trabalho."
                )

            # ====================================================
            # VOLTAR PARA A GRID
            #
            # Isto é necessário porque, depois de processar um
            # trabalho, a página está em TrabalhoRetroativo.aspx.
            #
            # Para cada novo trabalho voltamos à Grid e procuramos
            # novamente a solicitação.
            # ====================================================

            log("")
            log(
                "------------------------------------------------------------"
            )
            log(
                "VOLTANDO PARA A GRID PARA LOCALIZAR O PRÓXIMO TRABALHO"
            )
            log(
                "------------------------------------------------------------"
            )

            acessar_minha_grid(
                page
            )

            # ====================================================
            # LOCALIZAR SOLICITAÇÃO
            # ====================================================

            linha_grid = localizar_solicitacao(
                page,
                solicitacao,
            )

            if linha_grid is None:

                raise RuntimeError(
                    f"Solicitação {solicitacao} não encontrada "
                    "na Grid."
                )

            # ====================================================
            # ABRIR TRABALHO
            #
            # O ID É RELATIVO À SOLICITAÇÃO.
            #
            # Exemplo:
            #
            # solicitação 2262412 / trabalho 18
            #
            # e:
            #
            # solicitação 2261914 / trabalho 18
            #
            # são tratados separadamente.
            # ====================================================

            pagina_final = abrir_trabalho(
                page,
                context,
                linha_grid,
                solicitacao,
                id_trabalho,
            )

            if pagina_final is None:

                raise RuntimeError(
                    f"Não foi possível abrir o trabalho "
                    f"{id_trabalho} da solicitação "
                    f"{solicitacao}."
                )

            page = pagina_final

            # ====================================================
            # CONFIRMAR PÁGINA
            # ====================================================

            if not eh_trabalho_retroativo(
                page.url
            ):

                log(
                    f"Página atual antes do diagnóstico: {page.url}"
                )

            # ====================================================
            # DIAGNÓSTICO
            #
            # Mantido porque já está sendo usado para validar os
            # campos do E-Desk.
            # ====================================================

            diagnosticar_tela_horas(
                page
            )

            # ====================================================
            # SALVAR HORAS DESTE TRABALHO
            # ====================================================

            if horas:

                for indice_hora, hora in enumerate(
                    horas,
                    start=1,
                ):

                    sucesso_hora = salvar_hora(
                        page,
                        hora,
                        indice_hora,
                        len(horas),
                    )

                    if not sucesso_hora:

                        raise RuntimeError(
                            f"Não foi possível salvar a "
                            f"HORA {indice_hora} do trabalho "
                            f"{id_trabalho}, solicitação "
                            f"{solicitacao}."
                        )

                    log("")
                    log(
                        "------------------------------------------------------------"
                    )
                    log(
                        f"HORA {indice_hora} DE {len(horas)} "
                        "CONCLUÍDA"
                    )
                    log(
                        f"Solicitação: {solicitacao}"
                    )
                    log(
                        f"Trabalho: {id_trabalho}"
                    )
                    log(
                        "------------------------------------------------------------"
                    )

                log("")
                log(
                    "============================================================"
                )
                log(
                    f"TODAS AS {len(horas)} HORAS DO TRABALHO "
                    f"{id_trabalho} FORAM PROCESSADAS"
                )
                log(
                    f"SOLICITAÇÃO: {solicitacao}"
                )
                log(
                    "============================================================"
                )
                log("")

            else:

                log("")
                log(
                    f"Nenhuma hora enviada para o trabalho "
                    f"{id_trabalho} da solicitação {solicitacao}."
                )
                log("")

        # ========================================================
        # NAVEGADOR ABERTO SOMENTE SE SOLICITADO
        # ========================================================

        if manter_navegador_aberto:

            log(
                "Modo 'manter navegador aberto' ativado."
            )

            aguardar_navegador(
                context
            )

        # ========================================================
        # RESULTADO FINAL
        # ========================================================

        log("")
        log(
            "############################################################"
        )
        log(
            "PROCESSAMENTO DE TODOS OS TRABALHOS CONCLUÍDO"
        )
        log(
            "############################################################"
        )

        log(
            f"Trabalhos processados: {len(trabalhos)}"
        )

        log(
            f"Horas processadas: {total_horas}"
        )

        log("")

        return 0

    except Exception as erro:

        log("")
        log(
            "============================================================"
        )
        log(
            "ERRO DURANTE A EXECUÇÃO"
        )
        log(
            "============================================================"
        )

        log(
            f"{erro}"
        )

        import traceback

        traceback.print_exc()

        if (
            context is not None
            and manter_navegador_aberto
            and not enviar
        ):

            try:

                aguardar_navegador(
                    context
                )

            except Exception:

                pass

        raise

    finally:

        # ========================================================
        # IMPORTANTE:
        #
        # Quando o Flutter está enviando, o Python precisa terminar
        # completamente para que o processo não fique travado.
        # ========================================================

        if not manter_navegador_aberto:

            fechar_playwright(
                context,
                playwright,
            )


# ================================================================
# EXECUÇÃO
# ================================================================

if __name__ == "__main__":

    try:

        codigo = main()

        sys.exit(
            codigo
            if codigo is not None
            else 0
        )

    except KeyboardInterrupt:

        sys.exit(1)

    except Exception:

        sys.exit(1)
