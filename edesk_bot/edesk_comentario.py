import sys
import json
import time
from pathlib import Path

from playwright.sync_api import (
    sync_playwright,
    TimeoutError as PlaywrightTimeoutError,
)


# ============================================================
# CAMINHOS
# ============================================================

BASE_DIR = Path(__file__).resolve().parent
PERFIL_DIR = BASE_DIR / "perfil"


# ============================================================
# LOG
# ============================================================

def log(mensagem):
    print(
        f"[E-Desk][Comentario] {mensagem}",
        flush=True,
    )


# ============================================================
# REQUEST
# ============================================================

def carregar_request():

    if len(sys.argv) < 2:
        raise Exception(
            "Caminho do request.json não informado."
        )

    caminho = Path(sys.argv[1])

    if not caminho.exists():
        raise Exception(
            f"Request não encontrado: {caminho}"
        )

    with open(
        caminho,
        "r",
        encoding="utf-8",
    ) as arquivo:

        return json.load(arquivo)


# ============================================================
# AUTENTICAÇÃO
# ============================================================

def esta_autenticado(page):

    try:

        url = page.url

        if "/Portal/" in url:
            return True

        if page.locator(
            "#cph1_BtCom"
        ).count() > 0:
            return True

        if page.locator(
            "#cph1_txtSol"
        ).count() > 0:
            return True

    except Exception:
        pass

    return False


def aguardar_login(page):

    log(
        "Aguardando autenticação..."
    )

    inicio = time.time()

    while time.time() - inicio < 300:

        try:

            log(
                f"URL: {page.url}"
            )

            if esta_autenticado(page):

                log(
                    "AUTENTICAÇÃO CONFIRMADA."
                )

                return

        except Exception:
            pass

        time.sleep(1)

    raise Exception(
        "Tempo limite aguardando autenticação."
    )


# ============================================================
# MINHA GRID
# ============================================================

def abrir_minha_grid(page):

    log(
        "============================================"
    )

    log(
        "ETAPA 2 - ABRINDO MINHA GRID"
    )

    log(
        "============================================"
    )

    seletores = [

        "a[href*='ListaSolicitacao.aspx']",
        "a[href*='listaSolicitacao.aspx']",
        "#cph1_BtSol",
        "#cph1_BtSol_input",
        "#cph1_BtSol_text",
        "#ctl00_cph1_BtSol",
        "text=Minha Grid",

    ]

    botao = None

    for seletor in seletores:

        try:

            quantidade = page.locator(
                seletor
            ).count()

            log(
                f"Seletor: {seletor} | encontrados: {quantidade}"
            )

            if quantidade > 0:

                for i in range(quantidade):

                    elemento = page.locator(
                        seletor
                    ).nth(i)

                    try:

                        if elemento.is_visible():

                            botao = elemento
                            break

                    except Exception:
                        pass

            if botao is not None:
                break

        except Exception:
            pass

    if botao is None:

        raise Exception(
            "Botão Minha Grid não encontrado."
        )

    try:

        log(
            f"Clicando em: "
            f"{botao.get_attribute('id') or 'Minha Grid'}"
        )

    except Exception:

        log(
            "Clicando em Minha Grid."
        )

    botao.scroll_into_view_if_needed()

    botao.click(
        force=True
    )

    log(
        "Clique executado."
    )

    log(
        "Aguardando carregamento da Minha Grid..."
    )

    inicio = time.time()

    while time.time() - inicio < 20:

        try:

            url_atual = page.url

            if "ListaSolicitacao.aspx" in url_atual:

                log(
                    "MINHA GRID ABERTA."
                )

                log(
                    f"URL: {url_atual}"
                )

                return page

            campo_pesquisa = page.locator(
                "#cph1_txtSol"
            )

            if campo_pesquisa.count() > 0:

                visivel = False

                for i in range(
                    campo_pesquisa.count()
                ):

                    try:

                        if campo_pesquisa.nth(i).is_visible():

                            visivel = True
                            break

                    except Exception:
                        pass

                if visivel:

                    log(
                        "MINHA GRID ABERTA."
                    )

                    log(
                        "Campo #cph1_txtSol encontrado."
                    )

                    log(
                        f"URL: {url_atual}"
                    )

                    return page

        except Exception:
            pass

        time.sleep(0.5)

    try:

        log(
            f"URL após espera: {page.url}"
        )

        quantidade_campo = page.locator(
            "#cph1_txtSol"
        ).count()

        log(
            f"#cph1_txtSol após espera: "
            f"{quantidade_campo}"
        )

    except Exception:
        pass

    raise Exception(
        "Minha Grid não foi aberta."
    )


# ============================================================
# PESQUISAR SOLICITAÇÃO
# ============================================================

def pesquisar_solicitacao(
    page,
    solicitacao,
):

    log(
        "============================================"
    )

    log(
        "ETAPA 3 - PESQUISANDO SOLICITAÇÃO"
    )

    log(
        "============================================"
    )

    log(
        f"Solicitação: {solicitacao}"
    )

    paginas_antes = list(
        page.context.pages
    )

    url_antes = page.url

    campo = page.locator(
        "#cph1_txtSol"
    )

    if campo.count() == 0:

        raise Exception(
            "Campo #cph1_txtSol não encontrado."
        )

    campo.fill(
        str(solicitacao)
    )

    log(
        f"Valor preenchido: {campo.input_value()}"
    )

    botao = page.locator(
        "#cph1_btnLocSol"
    )

    if botao.count() == 0:

        raise Exception(
            "Botão #cph1_btnLocSol não encontrado."
        )

    log(
        f"Botão ID: {botao.get_attribute('id')}"
    )

    log(
        f"Botão NAME: {botao.get_attribute('name')}"
    )

    log(
        f"URL antes do Localizar: {url_antes}"
    )

    botao.click(
        force=True
    )

    log(
        "CLICK LOCALIZAR EXECUTADO."
    )

    log(
        "Aguardando resposta do E-DESK..."
    )

    inicio = time.time()

    while time.time() - inicio < 30:

        time.sleep(0.5)

        paginas = page.context.pages

        for outra_page in paginas:

            if outra_page in paginas_antes:
                continue

            try:

                url = outra_page.url

                if "/Portal/Solicitacao.aspx" in url:

                    log(
                        "SOLICITAÇÃO ABERTA EM NOVA ABA."
                    )

                    log(
                        f"URL: {url}"
                    )

                    return outra_page

            except Exception:
                pass

        try:

            url_atual = page.url

            if "/Portal/Solicitacao.aspx" in url_atual:

                log(
                    "SOLICITAÇÃO ABERTA NA PRÓPRIA PÁGINA."
                )

                log(
                    f"URL: {url_atual}"
                )

                return page

        except Exception:
            pass

        for outra_page in paginas:

            try:

                url = outra_page.url

                if "/Portal/Solicitacao.aspx" in url:

                    log(
                        "SOLICITAÇÃO ENCONTRADA EM UMA "
                        "DAS PÁGINAS DO CONTEXTO."
                    )

                    log(
                        f"URL: {url}"
                    )

                    return outra_page

            except Exception:
                pass

        try:

            linhas = page.locator(
                "tr.rgRow"
            )

            quantidade = linhas.count()

            if quantidade > 0:

                for i in range(quantidade):

                    linha = linhas.nth(i)

                    try:

                        texto_linha = (
                            linha.inner_text()
                        )

                        if str(solicitacao) in texto_linha:

                            log(
                                "SOLICITAÇÃO ENCONTRADA "
                                "NA GRID."
                            )

                            log(
                                f"Linha: {i}"
                            )

                            linha.click(
                                force=True
                            )

                            log(
                                "Clique na linha executado."
                            )

                            time.sleep(2)

                            for pagina in page.context.pages:

                                try:

                                    if (
                                        "/Portal/Solicitacao.aspx"
                                        in pagina.url
                                    ):

                                        log(
                                            "SOLICITAÇÃO ABERTA "
                                            "APÓS CLIQUE NA LINHA."
                                        )

                                        log(
                                            f"URL: {pagina.url}"
                                        )

                                        return pagina

                                except Exception:
                                    pass

                    except Exception:
                        pass

        except Exception:
            pass

    log(
        "Nenhuma Solicitação.aspx foi encontrada "
        "após Localizar."
    )

    log(
        f"Páginas abertas: "
        f"{len(page.context.pages)}"
    )

    for i, pagina in enumerate(
        page.context.pages
    ):

        try:

            log(
                f"Página {i}: {pagina.url}"
            )

        except Exception:
            pass

    raise Exception(
        f"A solicitação {solicitacao} "
        "não abriu após a pesquisa."
    )


# ============================================================
# ABRIR SOLICITAÇÃO
# ============================================================

def abrir_solicitacao(page):

    log(
        "============================================"
    )

    log(
        "ETAPA 4 - CONFIRMANDO SOLICITAÇÃO"
    )

    log(
        "============================================"
    )

    if "/Portal/Solicitacao.aspx" not in page.url:

        raise Exception(
            "A página atual não é Solicitação.aspx."
        )

    log(
        "ETAPA 4 CONCLUÍDA"
    )

    log(
        "SOLICITAÇÃO ABERTA"
    )

    log(
        f"URL: {page.url}"
    )

    return page


# ============================================================
# ABRIR COMENTÁRIOS
# ============================================================

def abrir_comentarios(page):

    log(
        "============================================"
    )

    log(
        "ETAPA 5 - ABRINDO COMENTÁRIOS"
    )

    log(
        "============================================"
    )

    log(
        f"URL atual: {page.url}"
    )

    if "/Portal/Solicitacao.aspx" not in page.url:

        raise Exception(
            "A página atual não é Solicicitacao.aspx."
        )

    botao = page.locator(
        "#cph1_BtCom"
    )

    quantidade = botao.count()

    log(
        f"#cph1_BtCom encontrados: {quantidade}"
    )

    if quantidade == 0:

        raise Exception(
            "Botão #cph1_BtCom não encontrado."
        )

    botao_visivel = None

    for i in range(quantidade):

        elemento = botao.nth(i)

        try:

            if elemento.is_visible():

                botao_visivel = elemento

                log(
                    f"Botão Comentários visível "
                    f"encontrado no índice {i}."
                )

                break

        except Exception:
            pass

    if botao_visivel is None:

        raise Exception(
            "O botão #cph1_BtCom existe, "
            "mas não está visível."
        )

    try:

        log(
            f"TAG: "
            f"{botao_visivel.evaluate('(e) => e.tagName')}"
        )

        log(
            f"TYPE: "
            f"{botao_visivel.get_attribute('type')}"
        )

        log(
            f"NAME: "
            f"{botao_visivel.get_attribute('name')}"
        )

        log(
            f"VALUE: "
            f"{botao_visivel.get_attribute('value')}"
        )

    except Exception:
        pass

    log(
        "Executando CLICK no submit Comentário..."
    )

    botao_visivel.scroll_into_view_if_needed()

    botao_visivel.click(
        force=True
    )

    log(
        "CLICK NO SUBMIT EXECUTADO."
    )

    log(
        "Aguardando processamento..."
    )

    time.sleep(3)

    log(
        f"URL após clique: {page.url}"
    )

    log(
        "--------------------------------------------"
    )

    log(
        "LOCALIZANDO FORMULÁRIO DE COMENTÁRIO"
    )

    frame_comentario = None

    try:

        if page.locator(
            "#popC_ddlTipCom"
        ).count() > 0:

            frame_comentario = page

            log(
                "Formulário encontrado na página principal."
            )

    except Exception:
        pass

    if frame_comentario is None:

        log(
            f"Frames encontrados: "
            f"{len(page.frames)}"
        )

        for indice, frame in enumerate(
            page.frames
        ):

            try:

                log(
                    f"Frame {indice}: "
                    f"name={frame.name!r} "
                    f"url={frame.url!r}"
                )

                quantidade_tipo = frame.locator(
                    "#popC_ddlTipCom"
                ).count()

                log(
                    f"Frame {indice} -> "
                    f"#popC_ddlTipCom: "
                    f"{quantidade_tipo}"
                )

                if quantidade_tipo > 0:

                    frame_comentario = frame

                    log(
                        "FORMULÁRIO DE COMENTÁRIO "
                        "ENCONTRADO NO FRAME."
                    )

                    break

            except Exception as e:

                log(
                    f"Erro verificando frame "
                    f"{indice}: {e}"
                )

    if frame_comentario is None:

        log(
            "Nenhum formulário de comentário "
            "foi encontrado."
        )

        raise Exception(
            "Formulário de comentário não encontrado "
            "em nenhum frame."
        )

    seletores = [

        "#popC_BtCom",
        "#popC_ddlTipCom",
        "#ctl00_popC_rdeCom",
        "#ctl00_popC_rdeCom_contentIframe",
        "#ctl00_popC_rdeComContentHiddenTextarea",
        "#popC_BtAtu",

    ]

    for seletor in seletores:

        try:

            quantidade = frame_comentario.locator(
                seletor
            ).count()

            log(
                f"{seletor} -> {quantidade}"
            )

        except Exception as e:

            log(
                f"Erro verificando "
                f"{seletor}: {e}"
            )

    log(
        "FORMULÁRIO DE COMENTÁRIO LOCALIZADO."
    )

    return frame_comentario


# ============================================================
# NORMALIZAR IMAGEM BASE64
# ============================================================

def normalizar_imagem_base64(
    imagem_base64,
):

    if not imagem_base64:
        return None

    imagem = str(
        imagem_base64
    ).strip()

    if not imagem:
        return None

    if imagem.startswith(
        "data:image/"
    ):

        return imagem

    return (
        "data:image/png;base64,"
        + imagem
    )


# ============================================================
# CADASTRAR COMENTÁRIO
#
# IMPORTANTE:
# NÃO SALVA.
# ============================================================

def cadastrar_comentario(
    page,
    tipo,
    texto,
    enviar,
    imagem_base64=None,
):

    log(
        "============================================"
    )

    log(
        "ETAPA 6 - PREENCHENDO COMENTÁRIO"
    )

    log(
        "============================================"
    )

    tipo_comentario = (
        "Interno"
        if tipo is None
        else str(tipo).strip()
    )

    texto_comentario = (
        ""
        if texto is None
        else str(texto)
    )

    imagem_data_url = (
        normalizar_imagem_base64(
            imagem_base64
        )
    )

    log(
        f"TIPO RECEBIDO DO JSON: "
        f"{tipo_comentario!r}"
    )

    log(
        f"DESCRITIVO RECEBIDO DO JSON: "
        f"{texto_comentario!r}"
    )

    log(
        f"IMAGEM RECEBIDA: "
        f"{'SIM' if imagem_data_url else 'NÃO'}"
    )

    log(
        f"ENVIAR RECEBIDO DO JSON: "
        f"{enviar}"
    )

    # ========================================================
    # 1. TIPO
    # ========================================================

    log(
        "--------------------------------------------"
    )

    log(
        "1. LOCALIZANDO TIPO DO COMENTÁRIO"
    )

    seletor_tipo = page.locator(
        "#popC_ddlTipCom"
    )

    quantidade_tipo = (
        seletor_tipo.count()
    )

    log(
        f"#popC_ddlTipCom encontrados: "
        f"{quantidade_tipo}"
    )

    if quantidade_tipo == 0:

        raise Exception(
            "Campo #popC_ddlTipCom não encontrado."
        )

    tipo_elemento = seletor_tipo.first

    tipo_elemento.wait_for(
        state="visible",
        timeout=15000,
    )

    opcoes = tipo_elemento.locator(
        "option"
    )

    quantidade_opcoes = (
        opcoes.count()
    )

    tipo_normalizado = (
        tipo_comentario.lower()
    )

    valor_tipo = None
    texto_tipo = None

    for i in range(
        quantidade_opcoes
    ):

        opcao = opcoes.nth(i)

        texto_opcao = (
            opcao.inner_text()
            .strip()
        )

        valor_opcao = (
            opcao.get_attribute(
                "value"
            )
        )

        log(
            f"Opção {i}: "
            f"text={texto_opcao!r} "
            f"value={valor_opcao!r}"
        )

        if (
            texto_opcao.lower()
            == tipo_normalizado
        ):

            valor_tipo = valor_opcao
            texto_tipo = texto_opcao
            break

    if valor_tipo is None:

        raise Exception(
            f"Tipo de comentário "
            f"'{tipo_comentario}' não encontrado."
        )

    log(
        f"Selecionando tipo: "
        f"{texto_tipo!r}"
    )

    tipo_elemento.select_option(
        value=valor_tipo
    )

    tipo_elemento.dispatch_event(
        "change"
    )

    time.sleep(0.5)

    tipo_atual = (
        tipo_elemento
        .locator("option:checked")
        .inner_text()
        .strip()
    )

    valor_atual = (
        tipo_elemento.input_value()
    )

    log(
        f"TIPO SELECIONADO: "
        f"{tipo_atual!r}"
    )

    log(
        f"VALOR DO TIPO: "
        f"{valor_atual!r}"
    )

    if (
        tipo_atual.lower()
        != tipo_normalizado
    ):

        raise Exception(
            "O tipo selecionado no E-Desk "
            "não corresponde ao tipo recebido."
        )

    log(
        "TIPO CONFIRMADO."
    )

    # ========================================================
    # 2. LOCALIZAR RAD EDITOR
    # ========================================================

    log(
        "--------------------------------------------"
    )

    log(
        "2. LOCALIZANDO RAD EDITOR TELERIK"
    )

    editor_id = (
        "ctl00_popC_rdeCom"
    )

    iframe_seletor = (
        "#ctl00_popC_rdeCom_contentIframe"
    )

    iframe = page.locator(
        iframe_seletor
    )

    quantidade_iframe = (
        iframe.count()
    )

    log(
        f"{iframe_seletor} encontrados: "
        f"{quantidade_iframe}"
    )

    if quantidade_iframe == 0:

        raise Exception(
            "Iframe do editor de comentário "
            "não encontrado."
        )

    iframe.first.wait_for(
        state="attached",
        timeout=15000,
    )

    frame = page.frame_locator(
        iframe_seletor
    )

    body = frame.locator(
        "body"
    )

    body.wait_for(
        state="visible",
        timeout=15000,
    )

    log(
        "EDITOR TELERIK ENCONTRADO."
    )

    # ========================================================
    # 3. VERIFICAR OBJETO JAVASCRIPT DO RAD EDITOR
    # ========================================================

    log(
        "--------------------------------------------"
    )

    log(
        "3. VERIFICANDO OBJETO JAVASCRIPT DO RAD EDITOR"
    )

    editor_info = page.evaluate(
        """(editorId) => {

            const resultado = {
                encontrado: false,
                possuiSetHtml: false,
                possuiGetHtml: false
            };

            try {

                if (typeof $find !== "function") {
                    return resultado;
                }

                const editor = $find(editorId);

                if (!editor) {
                    return resultado;
                }

                resultado.encontrado = true;

                resultado.possuiSetHtml =
                    typeof editor.set_html === "function";

                resultado.possuiGetHtml =
                    typeof editor.get_html === "function";

                return resultado;

            } catch (e) {

                return {
                    encontrado: false,
                    possuiSetHtml: false,
                    possuiGetHtml: false,
                    erro: String(e)
                };

            }

        }""",
        editor_id,
    )

    log(
        f"RadEditor encontrado: "
        f"{editor_info.get('encontrado')}"
    )

    log(
        f"RadEditor possui set_html: "
        f"{editor_info.get('possuiSetHtml')}"
    )

    log(
        f"RadEditor possui get_html: "
        f"{editor_info.get('possuiGetHtml')}"
    )

    if not editor_info.get(
        "encontrado"
    ):

        raise Exception(
            "O objeto JavaScript do RadEditor "
            "não foi encontrado."
        )

    if not editor_info.get(
        "possuiSetHtml"
    ):

        raise Exception(
            "O RadEditor foi encontrado, "
            "mas não possui o método set_html."
        )

    # ========================================================
    # 4. MONTAR HTML
    #
    # ORDEM:
    #
    # IMAGEM
    # ↓
    # DESCRIÇÃO
    # ========================================================

    log(
        "--------------------------------------------"
    )

    log(
        "4. MONTANDO CONTEÚDO DO COMENTÁRIO"
    )

    html_conteudo = ""

    if imagem_data_url:

        html_conteudo += (
            '<img '
            'src="'
            + imagem_data_url
            + '" '
            'alt="Imagem do comentário" '
            'style="'
            'width:500px;'
            'max-width:500px;'
            'height:auto;'
            'display:block;'
            'margin:0 0 10px 0;'
            '"'
            '>'
        )

        log(
            "IMAGEM SERÁ INSERIDA PRIMEIRO."
        )

        log(
            "TAMANHO MÁXIMO DA IMAGEM: 500px."
        )

    if texto_comentario:

        texto_html = (
            texto_comentario
            .replace("&", "&amp;")
            .replace("<", "&lt;")
            .replace(">", "&gt;")
            .replace('"', "&quot;")
        )

        texto_html = (
            texto_html
            .replace("\r\n", "<br>")
            .replace("\r", "<br>")
            .replace("\n", "<br>")
        )

        if imagem_data_url:

            html_conteudo += (
                "<div>"
            )

        else:

            html_conteudo += (
                "<div>"
            )

        html_conteudo += (
            texto_html
        )

        html_conteudo += (
            "</div>"
        )

        log(
            "DESCRIÇÃO SERÁ INSERIDA "
            "DEPOIS DA IMAGEM."
        )

    log(
        f"Tamanho do HTML final: "
        f"{len(html_conteudo)}"
    )

    # ========================================================
    # 5. PREENCHER PELO RAD EDITOR
    #
    # NÃO SALVAR.
    # ========================================================

    log(
        "--------------------------------------------"
    )

    log(
        "5. PREENCHENDO PELO RAD EDITOR"
    )

    resultado_set_html = page.evaluate(
        """({editorId, html}) => {

            try {

                if (typeof $find !== "function") {
                    return {
                        sucesso: false,
                        erro: "$find não existe"
                    };
                }

                const editor = $find(editorId);

                if (!editor) {
                    return {
                        sucesso: false,
                        erro: "RadEditor não encontrado"
                    };
                }

                if (typeof editor.set_html !== "function") {
                    return {
                        sucesso: false,
                        erro: "set_html não existe"
                    };
                }

                editor.set_html(html);

                return {
                    sucesso: true
                };

            } catch (e) {

                return {
                    sucesso: false,
                    erro: String(e)
                };

            }

        }""",
        {
            "editorId": editor_id,
            "html": html_conteudo,
        },
    )

    log(
        f"Resultado set_html: "
        f"{resultado_set_html}"
    )

    if not resultado_set_html.get(
        "sucesso"
    ):

        raise Exception(
            "Falha ao executar "
            "RadEditor.set_html(): "
            + str(
                resultado_set_html.get(
                    "erro"
                )
            )
        )

    log(
        "RAD EDITOR RECEBEU O HTML."
    )

    # ========================================================
    # 6. MONITORAR O EDITOR
    #
    # NÃO ALTERA O CONTEÚDO.
    #
    # SOMENTE OBSERVA SE O E-DESK/TELERIK
    # ESTÁ ALTERANDO O HTML.
    # ========================================================

    log(
        "--------------------------------------------"
    )

    log(
        "6. MONITORANDO O CONTEÚDO DO RAD EDITOR"
    )

    log(
        "Nenhum salvamento será executado."
    )

    tempos = [
        0.2,
        0.5,
        1.0,
        1.5,
        2.0,
        3.0,
        4.0,
        5.0,
    ]

    inicio_monitoramento = time.time()

    ultimo_html = None

    for tempo_alvo in tempos:

        while (
            time.time()
            - inicio_monitoramento
            < tempo_alvo
        ):

            time.sleep(0.05)

        try:

            resultado_monitoramento = page.evaluate(
                """(editorId) => {

                    try {

                        const editor = $find(editorId);

                        if (!editor) {
                            return {
                                encontrado: false,
                                html: ""
                            };
                        }

                        const html =
                            typeof editor.get_html === "function"
                            ? editor.get_html()
                            : "";

                        return {
                            encontrado: true,
                            html: html
                        };

                    } catch (e) {

                        return {
                            encontrado: false,
                            html: "",
                            erro: String(e)
                        };

                    }

                }""",
                editor_id,
            )

            html_atual = (
                resultado_monitoramento.get(
                    "html",
                    ""
                )
            )

            quantidade_img = html_atual.lower().count(
                "<img"
            )

            tamanho_html = len(
                html_atual
            )

            alterou = (
                ultimo_html is not None
                and html_atual != ultimo_html
            )

            log(
                f"Após {tempo_alvo:.1f}s -> "
                f"HTML={tamanho_html} "
                f"IMG={quantidade_img} "
                f"ALTEROU={alterou}"
            )

            if tamanho_html == 0:

                log(
                    "ATENÇÃO: O RAD EDITOR FICOU VAZIO."
                )

            elif quantidade_img > 0:

                log(
                    "Imagem continua presente."
                )

            else:

                log(
                    "HTML existe, mas sem imagem."
                )

            ultimo_html = html_atual

        except Exception as e:

            log(
                f"Erro durante monitoramento: {e}"
            )

    # ========================================================
    # 7. CONFIRMAR IFRAME VISUAL
    # ========================================================

    log(
        "--------------------------------------------"
    )

    log(
        "7. CONFIRMANDO CONTEÚDO VISUAL"
    )

    try:

        html_visual = (
            body.inner_html()
        )

        texto_editor = (
            body.inner_text()
        )

        quantidade_imagens = body.locator(
            "img"
        ).count()

        log(
            f"Tamanho HTML visual: "
            f"{len(html_visual)}"
        )

        log(
            f"Quantidade de imagens no editor: "
            f"{quantidade_imagens}"
        )

        log(
            f"Texto atual do editor: "
            f"{texto_editor!r}"
        )

    except Exception as e:

        raise Exception(
            "Não foi possível ler o conteúdo "
            f"visual do editor: {e}"
        )

    # ========================================================
    # 8. NÃO SALVAR
    # ========================================================

    log(
        "--------------------------------------------"
    )

    log(
        "8. SALVAMENTO"
    )

    log(
        "NÃO CLICAR NO BOTÃO DE SALVAR."
    )

    log(
        f"#popC_BtAtu encontrado: "
        f"{page.locator('#popC_BtAtu').count()}"
    )

    log(
        f"Valor enviar recebido: {enviar}"
    )

    log(
        "O parâmetro 'enviar' NÃO será utilizado "
        "nesta etapa."
    )

    log(
        "============================================"
    )

    log(
        "ETAPA 6 CONCLUÍDA."
    )

    log(
        "TIPO: OK"
    )

    log(
        f"IMAGEM: "
        f"{'INSERIDA' if imagem_data_url else 'NÃO INFORMADA'}"
    )

    log(
        "DESCRITIVO: INSERIDO"
    )

    log(
        "RAD EDITOR: MONITORADO"
    )

    log(
        "SALVAMENTO: NÃO EXECUTADO"
    )

    log(
        "============================================"
    )

    return page


# ============================================================
# MANTER NAVEGADOR ABERTO
# ============================================================

def manter_navegador_aberto():

    log(
        "============================================"
    )

    log(
        "NAVEGADOR MANTIDO ABERTO"
    )

    log(
        "============================================"
    )

    log(
        "O Python permanecerá aguardando."
    )

    while True:

        time.sleep(1)


# ============================================================
# MAIN
# ============================================================

def main():

    request = carregar_request()

    solicitacao = str(
        request.get(
            "solicitacao",
            ""
        )
    )

    id_trabalho = str(
        request.get(
            "idTrabalho",
            ""
        )
    )

    tipo = str(
        request.get(
            "tipo",
            "Interno"
        )
    )

    texto = request.get(
        "texto",
        ""
    )

    imagem_base64 = request.get(
        "imagemBase64"
    )

    enviar = bool(
        request.get(
            "enviar",
            False
        )
    )

    url_edesk = request.get(
        "url",
        "https://promob.e-desk.com.br"
    )

    log(
        "============================================"
    )

    log(
        "INÍCIO EXECUÇÃO E-DESK"
    )

    log(
        "============================================"
    )

    log(
        f"Solicitação recebida: {solicitacao}"
    )

    log(
        f"ID Trabalho recebido: {id_trabalho}"
    )

    log(
        f"Tipo recebido: {tipo}"
    )

    log(
        f"Enviar: {enviar}"
    )

    log(
        f"Imagem: "
        f"{'SIM' if imagem_base64 else 'NÃO'}"
    )

    log(
        f"Perfil: {PERFIL_DIR}"
    )

    with sync_playwright() as playwright:

        contexto = playwright.chromium.launch_persistent_context(

            user_data_dir=str(
                PERFIL_DIR
            ),

            headless=False,

            viewport={
                "width": 1400,
                "height": 900,
            },

        )

        try:

            paginas = contexto.pages

            if len(paginas) > 0:

                page = paginas[0]

            else:

                page = contexto.new_page()

            log(
                f"Página atual: {page.url}"
            )

            if page.url == "about:blank":

                log(
                    "Abrindo E-Desk..."
                )

                page.goto(
                    url_edesk,
                    wait_until="domcontentloaded",
                    timeout=60000,
                )

            elif not esta_autenticado(page):

                log(
                    "Página atual não autenticada."
                )

                log(
                    "Abrindo E-Desk..."
                )

                page.goto(
                    url_edesk,
                    wait_until="domcontentloaded",
                    timeout=60000,
                )

            aguardar_login(
                page
            )

            page = abrir_minha_grid(
                page
            )

            page = pesquisar_solicitacao(
                page,
                solicitacao,
            )

            page = abrir_solicitacao(
                page
            )

            contexto_comentario = abrir_comentarios(
                page
            )

            page = cadastrar_comentario(
                contexto_comentario,
                tipo,
                texto,
                enviar,
                imagem_base64,
            )

            log(
                "============================================"
            )

            log(
                "FLUXO CONCLUÍDO."
            )

            log(
                "============================================"
            )

            log(
                f"URL FINAL: {page.url}"
            )

            manter_navegador_aberto()

        except Exception as e:

            log(
                "============================================"
            )

            log(
                "ERRO DURANTE A EXECUÇÃO"
            )

            log(
                "============================================"
            )

            log(
                f"Exception: {e}"
            )

            log(
                "============================================"
            )

            log(
                "NAVEGADOR SERÁ MANTIDO ABERTO"
            )

            log(
                "============================================"
            )

            log(
                f"Páginas abertas: "
                f"{len(contexto.pages)}"
            )

            for i, pagina in enumerate(
                contexto.pages
            ):

                try:

                    log(
                        f"Página {i}: {pagina.url}"
                    )

                except Exception:
                    pass

            manter_navegador_aberto()


# ============================================================
# EXECUÇÃO
# ============================================================

if __name__ == "__main__":

    main()