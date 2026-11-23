import 'package:flutter/material.dart';
import '../../core/theme/app_appearance.dart';
import '../../core/theme/app_palette.dart';
import '../../core/theme/cores_app.dart';
import '../../data/services/edesk_credentials_service.dart';

/// Owns the credentials interaction independently of the header layout.
/// The origin's lifetime is kept separate from the dialog's lifetime.
class HeaderEdeskCredentialsDialog {
  HeaderEdeskCredentialsDialog({
    required this.context,
    required EdeskCredentialsService credentials,
    required bool Function() isOriginMounted,
  })  : _edeskCredentials = credentials,
        _isOriginMounted = isOriginMounted;

  final BuildContext context;
  final EdeskCredentialsService _edeskCredentials;
  final bool Function() _isOriginMounted;
  bool get mounted => _isOriginMounted();

  Future<void> show() async {
    final emailController = TextEditingController();
    final senhaController = TextEditingController();

    bool mostrarSenha = false;
    bool salvando = false;
    bool possuiCredenciais = false;
    String? erroCarregamento;

    try {
      final dados = await _edeskCredentials.ler();

      if (dados != null) {
        emailController.text = dados['email'] ?? '';
        senhaController.text = dados['senha'] ?? '';
        possuiCredenciais = true;
      }
    } catch (_) {
      erroCarregamento =
          'Não foi possível recuperar as credenciais. Verifique a conexão e reabra esta janela.';
    }

    if (!mounted || !context.mounted) {
      emailController.dispose();
      senhaController.dispose();
      return;
    }

    final route = DialogRoute<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        AppAppearance.watch(dialogContext);

        return StatefulBuilder(
          builder: (context, setDialogState) {
            AppAppearance.watch(context);
            return AlertDialog(
              backgroundColor: CoresApp.superficie,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
              title: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: CoresApp.primaria.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.lock_outline_rounded,
                      color: CoresApp.primaria,
                      size: 21,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Credenciais E-Desk',
                      style: TextStyle(
                        color: CoresApp.textoPrincipal,
                        fontWeight: FontWeight.w700,
                        fontSize: 17,
                      ),
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Configure o acesso que será utilizado '
                        'automaticamente nas ações do E-Desk.',
                        style: TextStyle(
                          color: CoresApp.textoSecundario,
                          fontSize: 12,
                          height: 1.4,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    if (erroCarregamento != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text(erroCarregamento,
                            style: TextStyle(color: CoresApp.erro)),
                      ),

                    // ==================================================
                    // E-MAIL
                    // ==================================================

                    TextField(
                      controller: emailController,
                      keyboardType: TextInputType.emailAddress,
                      style: TextStyle(
                        color: CoresApp.textoPrincipal,
                        fontSize: 13,
                      ),
                      decoration: InputDecoration(
                        labelText: 'E-mail do E-Desk',
                        labelStyle: TextStyle(
                          color: CoresApp.textoSecundario,
                        ),
                        prefixIcon: Icon(
                          Icons.email_outlined,
                          color: CoresApp.textoSecundario,
                        ),
                        filled: true,
                        fillColor: CoresApp.superficieEscura,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(11),
                          borderSide: BorderSide(
                            color: CoresApp.bordaSuave,
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(11),
                          borderSide: BorderSide(
                            color: CoresApp.bordaSuave,
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(11),
                          borderSide: BorderSide(
                            color: CoresApp.primaria,
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 14),

                    // ==================================================
                    // SENHA
                    // ==================================================

                    TextField(
                      controller: senhaController,
                      obscureText: !mostrarSenha,
                      style: TextStyle(
                        color: CoresApp.textoPrincipal,
                        fontSize: 13,
                      ),
                      decoration: InputDecoration(
                        labelText: 'Senha do E-Desk',
                        labelStyle: TextStyle(
                          color: CoresApp.textoSecundario,
                        ),
                        prefixIcon: Icon(
                          Icons.password_rounded,
                          color: CoresApp.textoSecundario,
                        ),
                        suffixIcon: IconButton(
                          tooltip:
                              mostrarSenha ? 'Ocultar senha' : 'Mostrar senha',
                          onPressed: () {
                            setDialogState(() {
                              mostrarSenha = !mostrarSenha;
                            });
                          },
                          icon: Icon(
                            mostrarSenha
                                ? Icons.visibility_off_rounded
                                : Icons.visibility_rounded,
                            color: CoresApp.textoSecundario,
                          ),
                        ),
                        filled: true,
                        fillColor: CoresApp.superficieEscura,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(11),
                          borderSide: BorderSide(
                            color: CoresApp.bordaSuave,
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(11),
                          borderSide: BorderSide(
                            color: CoresApp.bordaSuave,
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(11),
                          borderSide: BorderSide(
                            color: CoresApp.primaria,
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    // ==================================================
                    // AVISO
                    // ==================================================

                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.blue.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: Colors.blue.withValues(alpha: 0.18),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.security_rounded,
                            color: Colors.blueAccent,
                            size: 18,
                          ),
                          const SizedBox(width: 9),
                          Expanded(
                            child: Text(
                              'As credenciais serão salvas na sua conta do app no Firebase '
                              'e carregadas ao entrar em outro computador. '
                              'Uma cópia local permite reutilizar as credenciais neste navegador.',
                              style: TextStyle(
                                color: CoresApp.textoSecundario,
                                fontSize: 11,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    if (possuiCredenciais) ...[
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Row(
                          children: [
                            const Icon(
                              Icons.check_circle_rounded,
                              color: Colors.green,
                              size: 17,
                            ),
                            const SizedBox(width: 7),
                            Text(
                              'Credenciais cadastradas',
                              style: TextStyle(
                                color: CoresApp.textoSecundario,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                // ======================================================
                // REMOVER
                // ======================================================

                if (possuiCredenciais)
                  TextButton.icon(
                    onPressed: salvando
                        ? null
                        : () async {
                            try {
                              setDialogState(() {
                                salvando = true;
                              });

                              await _edeskCredentials.apagar();

                              emailController.clear();
                              senhaController.clear();

                              setDialogState(() {
                                salvando = false;
                                possuiCredenciais = false;
                              });

                              if (mounted && context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Credenciais do E-Desk removidas.',
                                    ),
                                    behavior: SnackBarBehavior.floating,
                                  ),
                                );
                              }
                            } catch (e) {
                              if (!dialogContext.mounted) return;
                              setDialogState(() {
                                salvando = false;
                              });

                              if (mounted && context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'Erro ao remover credenciais: $e',
                                    ),
                                    behavior: SnackBarBehavior.floating,
                                  ),
                                );
                              }
                            }
                          },
                    icon: Icon(
                      Icons.delete_outline_rounded,
                      size: 18,
                      color: CoresApp.erro,
                    ),
                    label: Text(
                      'Remover',
                      style: TextStyle(
                        color: CoresApp.erro,
                      ),
                    ),
                  ),

                // ======================================================
                // CANCELAR
                // ======================================================

                TextButton(
                  onPressed: salvando
                      ? null
                      : () {
                          Navigator.of(dialogContext).pop();
                        },
                  child: Text(
                    'Cancelar',
                    style: TextStyle(
                      color: CoresApp.textoSecundario,
                    ),
                  ),
                ),

                // ======================================================
                // SALVAR
                // ======================================================

                ElevatedButton.icon(
                  onPressed: salvando
                      ? null
                      : () async {
                          final email = emailController.text.trim();

                          final senha = senhaController.text;

                          if (email.isEmpty) {
                            ScaffoldMessenger.of(
                              dialogContext,
                            ).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Informe o e-mail do E-Desk.',
                                ),
                              ),
                            );
                            return;
                          }

                          if (senha.isEmpty) {
                            ScaffoldMessenger.of(
                              dialogContext,
                            ).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Informe a senha do E-Desk.',
                                ),
                              ),
                            );
                            return;
                          }

                          setDialogState(() {
                            salvando = true;
                          });

                          try {
                            await _edeskCredentials.salvar(
                              email: email,
                              senha: senha,
                            );

                            if (!dialogContext.mounted || !context.mounted) {
                              return;
                            }

                            Navigator.of(dialogContext).pop();

                            if (mounted && context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Credenciais do E-Desk salvas na sua conta do app.',
                                  ),
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                            }
                          } catch (e) {
                            if (!dialogContext.mounted) return;
                            setDialogState(() {
                              salvando = false;
                            });

                            if (!dialogContext.mounted || !context.mounted) {
                              return;
                            }

                            ScaffoldMessenger.of(dialogContext).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Erro ao salvar credenciais: $e',
                                ),
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: CoresApp.primaria,
                    foregroundColor: AppPalette.foregroundOn(CoresApp.primaria),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 11,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  icon: salvando
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                          ),
                        )
                      : const Icon(
                          Icons.save_rounded,
                          size: 17,
                        ),
                  label: Text(
                    salvando ? 'Salvando...' : 'Salvar',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );

    await Navigator.of(context).push(route);
    // A pop completes before the closing animation removes the TextFields.
    // Keep their controllers alive until the route's overlay is disposed.
    await route.completed;
    emailController.dispose();
    senhaController.dispose();
  }
}
