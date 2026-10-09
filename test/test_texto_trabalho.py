import unittest

from edesk_bot.texto_trabalho import acrescentar_trabalho_realizado


class TextoTrabalhoTest(unittest.TestCase):
    def test_preserva_comentarios_e_acrescenta_abaixo(self):
        anterior = "07/10/2026: - Dúvidas configurador + ajustes construtor"
        resultado = acrescentar_trabalho_realizado(
            anterior, "08/10/2026", "Planilha acabamentos"
        )
        self.assertEqual(
            resultado,
            anterior + "\n08/10/2026: - Planilha acabamentos",
        )

    def test_preserva_espacos_e_quebras_existentes(self):
        for anterior in ["  Comentário anterior  ", "Comentário\n", "Comentário\n\n", "A\r\nB\r\n"]:
            with self.subTest(anterior=anterior):
                resultado = acrescentar_trabalho_realizado(anterior, "08/10/2026", "Novo")
                self.assertTrue(resultado.startswith(anterior))
                self.assertEqual(resultado[len(anterior):], ("" if anterior.endswith("\n") else "\n") + "08/10/2026: - Novo")

    def test_varios_apontamentos_preservam_todo_o_historico(self):
        resultado = "Histórico já registrado"
        for dia in ["07/10/2026", "08/10/2026", "08/10/2026"]:
            resultado = acrescentar_trabalho_realizado(resultado, dia, "Atividade")
        self.assertEqual(resultado.splitlines(), [
            "Histórico já registrado", "07/10/2026: - Atividade",
            "08/10/2026: - Atividade", "08/10/2026: - Atividade",
        ])

    def test_campo_vazio_nao_recebe_linha_em_branco(self):
        self.assertEqual(acrescentar_trabalho_realizado("", "08/10/2026", "Novo"), "08/10/2026: - Novo")


if __name__ == "__main__":
    unittest.main()
