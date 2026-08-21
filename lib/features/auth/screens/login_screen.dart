import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:gerenciador_horas/core/theme/cores_app.dart';
import 'register_screen.dart';

class LoginScreen extends StatefulWidget {
  final VoidCallback onLoginSuccess;

  const LoginScreen({
    super.key,
    required this.onLoginSuccess,
  });

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Por favor, preencha o e-mail e a senha.'),
          backgroundColor: CoresApp.erro,
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        String errorMessage = 'Erro ao fazer login.';
        if (e.code == 'user-not-found') {
          errorMessage = 'Usuário não encontrado.';
        } else if (e.code == 'wrong-password') {
          errorMessage = 'Senha incorreta.';
        } else if (e.code == 'invalid-email') {
          errorMessage = 'O formato do e-mail é inválido.';
        } else if (e.code == 'invalid-credential') {
          errorMessage = 'E-mail ou senha incorretos.';
        } else {
          errorMessage = 'Erro: ${e.message ?? "Tente novamente."}';
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage,
                style: const TextStyle(color: CoresApp.textoPrincipal)),
            backgroundColor: CoresApp.erro,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _resetPassword() async {
    final email = _emailController.text.trim();

    if (email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text('Por favor, digite seu e-mail no campo acima primeiro.'),
          backgroundColor: CoresApp.erro,
        ),
      );
      return;
    }

    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'E-mail de redefinição enviado! Verifique sua caixa de entrada e spam.'),
            backgroundColor: CoresApp.sucesso,
          ),
        );
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao enviar e-mail: ${e.message}',
                style: const TextStyle(color: CoresApp.textoPrincipal)),
            backgroundColor: CoresApp.erro,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CoresApp.fundo,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 420),
            padding: const EdgeInsets.fromLTRB(36.0, 20.0, 36.0, 36.0),
            decoration: BoxDecoration(
              color: CoresApp.superficie,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: CoresApp.borda, width: 1),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.5),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Logo grande preenchendo o espaço superior perfeitamente
                Center(
                  child: SizedBox(
                    height: 200,
                    width: double.infinity,
                    child: Image.asset(
                      'assets/images/Logo.png',
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) {
                        return const Icon(
                          Icons.access_time_rounded,
                          color: CoresApp.primaria,
                          size: 48,
                        );
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Bem-vindo de volta',
                  style: TextStyle(
                    color: CoresApp.textoPrincipal,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 6),
                const Text(
                  'Faça login para continuar',
                  style: TextStyle(
                    color: CoresApp.textoSecundario,
                    fontSize: 13,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),

                // Campo de E-mail
                TextField(
                  controller: _emailController,
                  style: const TextStyle(
                      color: CoresApp.textoPrincipal, fontSize: 14),
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                    labelText: 'E-mail',
                    labelStyle: const TextStyle(
                        color: CoresApp.textoSecundario, fontSize: 13),
                    prefixIcon: const Icon(Icons.email_outlined,
                        color: CoresApp.primaria, size: 20),
                    filled: true,
                    fillColor: CoresTelas.campoFormulario,
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: CoresApp.borda),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(
                          color: CoresApp.primaria, width: 1.2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Campo de Senha
                TextField(
                  controller: _passwordController,
                  style: const TextStyle(
                      color: CoresApp.textoPrincipal, fontSize: 14),
                  obscureText: _obscurePassword,
                  decoration: InputDecoration(
                    labelText: 'Senha',
                    labelStyle: const TextStyle(
                        color: CoresApp.textoSecundario, fontSize: 13),
                    prefixIcon: const Icon(Icons.lock_outline,
                        color: CoresApp.primaria, size: 20),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility_off
                            : Icons.visibility,
                        color: CoresApp.textoFraco,
                        size: 20,
                      ),
                      onPressed: () {
                        setState(() {
                          _obscurePassword = !_obscurePassword;
                        });
                      },
                    ),
                    filled: true,
                    fillColor: CoresTelas.campoFormulario,
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: CoresApp.borda),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(
                          color: CoresApp.primaria, width: 1.2),
                    ),
                  ),
                ),
                const SizedBox(height: 8),

                // Botão Esqueci a senha
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: _resetPassword,
                    style: TextButton.styleFrom(
                      foregroundColor: CoresApp.primaria,
                      padding: EdgeInsets.zero,
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text(
                      'Esqueceu a senha?',
                      style: TextStyle(color: CoresApp.primaria, fontSize: 13),
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // Botão de Entrar
                SizedBox(
                  height: 48,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: CoresApp.primaria,
                      foregroundColor: CoresApp.fundo,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      elevation: 0,
                    ),
                    onPressed: _isLoading ? null : _handleLogin,
                    child: _isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: CoresApp.fundo,
                            ),
                          )
                        : const Text(
                            'Entrar',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 20),

                // Botão para ir para a Tela de Cadastro
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text(
                      'Não tem uma conta?',
                      style: TextStyle(
                          color: CoresApp.textoSecundario, fontSize: 13),
                    ),
                    TextButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => RegisterScreen(
                              onRegisterSuccess: () {
                                Navigator.pop(context);
                              },
                            ),
                          ),
                        );
                      },
                      child: const Text(
                        'Cadastre-se',
                        style: TextStyle(
                          color: CoresApp.primaria,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
