def acrescentar_trabalho_realizado(existente: str, data: str, descritivo: str) -> str:
    """Preserva o texto anterior e acrescenta o apontamento em uma nova linha."""
    novo_bloco = f"{data}: - {descritivo}"
    if not existente:
        return novo_bloco
    if existente.endswith(("\n", "\r")):
        return existente + novo_bloco
    separador = "\r\n" if "\r\n" in existente else "\n"
    return existente + separador + novo_bloco
